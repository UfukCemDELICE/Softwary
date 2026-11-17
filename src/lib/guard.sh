# shellcheck shell=sh
# softwary: the `guard` command. Sourced by bin/softwary. POSIX sh.
#
# guard <job> [--base <ref>] recomputes, from the committed diff of a job
# branch, what a merging script must not take on trust: a change to a
# protected path, a path outside the slice's `touches`, and a loosened test.
# `job gate` and `merge` call it; so can a reviewer. The job's branch is
# softwary/<job> when that branch exists (the main checkout need not be on it),
# else HEAD. Exit: 0 no problem, 1 problems (one `guard: <kind>: <detail>`
# line each), 2 usage or setup.

# The protected paths: a trailing '/' is a directory (everything below it),
# anything else is exactly that path. The project cannot change this list.
SW_PROTECTED=".softwary/ .github/ CODEOWNERS docs/CODEOWNERS softwary product/ architecture/model/ architecture/data/ architecture/contracts/ architecture/proofs/ architecture/drift.md"

SW_TESTSKIP_REL=.softwary/config/test-skip.conf

sw_guard_usage() {
	printf 'usage: ./softwary guard <job> [--base <ref>]\n' >&2
}

# sw_guard_protected PATH: true if PATH is a protected path.
sw_guard_protected() {
	for _gp in $SW_PROTECTED; do
		case $_gp in
		*/) case $1 in "$_gp"*) return 0 ;; esac ;;
		*) [ "$1" = "$_gp" ] && return 0 ;;
		esac
	done
	return 1
}

# sw_guard_covers ENTRY PATH: true if the touches entry covers PATH. An entry
# with a glob character is a pattern like those of risk.conf ('*' matches
# '/'); any other entry is the path itself or a directory above it.
sw_guard_covers() {
	_gc=${1#./}
	case $_gc in
	*[*?[]*)
		# shellcheck disable=SC2254 # the entry is a pattern on purpose
		case $2 in $_gc) return 0 ;; esac
		return 1
		;;
	esac
	_gc=${_gc%/}
	[ -n "$_gc" ] || return 1
	[ "$2" = "$_gc" ] && return 0
	case $2 in "$_gc"/*) return 0 ;; esac
	return 1
}

# sw_guard_touches_of FILE: prints the touches of the slice (one per line).
sw_guard_touches_of() {
	sw_fm_read "$1"
	sw_list "$(sw_fm_get touches)"
}

# sw_testskip_load: parses test-skip.conf. Sets SW_TS_PATTERNS (one ERE per
# line), SW_TS_NONE (1 for `NONE: <reason>`) and SW_TS_ERRORS (one
# "REL[:LINE]: problem" per line). Returns 0 when the file is usable, else 2.
sw_testskip_load() {
	SW_TS_PATTERNS='' SW_TS_NONE=0 SW_TS_ERRORS=''
	_ts_f=$SOFTWARY_ROOT/$SW_TESTSKIP_REL
	if [ ! -f "$_ts_f" ]; then
		SW_TS_ERRORS="$SW_TESTSKIP_REL: file not found; rerun install.sh
"
		return 2
	fi
	_ts_n=0
	while IFS= read -r _ts_l || [ -n "$_ts_l" ]; do
		_ts_n=$((_ts_n + 1))
		_ts_l=$(sw_trim "$(printf '%s' "$_ts_l" | tr -d '\r')")
		case $_ts_l in '' | '#'*) continue ;; esac
		case $_ts_l in
		NONE | NONE:*)
			if [ -z "$(sw_none_reason "$_ts_l")" ]; then
				SW_TS_ERRORS="${SW_TS_ERRORS}$SW_TESTSKIP_REL:$_ts_n: 'NONE' needs a reason: 'NONE: <reason>'
"
			else
				SW_TS_NONE=1
			fi
			continue
			;;
		esac
		_ts_rc=0
		printf '' | grep -E -e "$_ts_l" >/dev/null 2>&1 || _ts_rc=$?
		if [ "$_ts_rc" -eq 2 ]; then
			SW_TS_ERRORS="${SW_TS_ERRORS}$SW_TESTSKIP_REL:$_ts_n: invalid pattern '$_ts_l'
"
			continue
		fi
		SW_TS_PATTERNS="${SW_TS_PATTERNS}$_ts_l
"
	done <"$_ts_f"
	if [ "$SW_TS_NONE" -eq 1 ] && [ -n "$SW_TS_PATTERNS" ]; then
		SW_TS_ERRORS="${SW_TS_ERRORS}$SW_TESTSKIP_REL: NONE must be the only entry (remove the patterns or the NONE line)
"
	fi
	if [ -z "$SW_TS_ERRORS" ] && [ "$SW_TS_NONE" -eq 0 ] && [ -z "$SW_TS_PATTERNS" ]; then
		SW_TS_ERRORS="$SW_TESTSKIP_REL: no patterns: add your test framework's skip and focus markers, or NONE: <reason>
"
	fi
	[ -z "$SW_TS_ERRORS" ]
}

# sw_guard JOB [--base REF]
sw_guard() {
	_gd_job=
	_gd_ref=
	while [ $# -gt 0 ]; do
		case $1 in
		--base)
			[ $# -ge 2 ] || { sw_guard_usage; return 2; }
			_gd_ref=$2
			shift 2
			;;
		-*)
			sw_guard_usage
			return 2
			;;
		*)
			[ -z "$_gd_job" ] || { sw_guard_usage; return 2; }
			_gd_job=$1
			shift
			;;
		esac
	done
	[ -n "$_gd_job" ] || { sw_guard_usage; return 2; }
	sw_job_valid_id "$_gd_job" || { printf 'guard: %s is not a job (NNN-S<n>)\n' "$_gd_job"; return 2; }
	sw_job_locate "$_gd_job" || { printf 'guard: no slice %s\n' "$_gd_job"; return 2; }
	if [ -z "$_gd_ref" ]; then
		sw_default_base guard || return 2
		_gd_ref=$SW_DEFAULT_BASE
	fi
	_gd_head=HEAD
	if git -C "$SOFTWARY_ROOT" rev-parse -q --verify "refs/heads/softwary/$_gd_job" >/dev/null 2>&1; then
		_gd_head=refs/heads/softwary/$_gd_job
	fi
	sw_base_commit "$_gd_ref" guard "$_gd_head" || return 2
	_gd_mb=$SW_BASE_COMMIT
	sw_guard_config || return 2
	_gd_changed=$(git -C "$SOFTWARY_ROOT" -c core.quotePath=false diff --no-renames --name-only "$_gd_mb" "$_gd_head" --)
	_gd_out=
	sw_guard_run
	if [ -z "$_gd_out" ]; then
		printf 'guard: no problems\n'
		return 0
	fi
	printf '%s' "$_gd_out"
	printf 'guard: %s problem(s)\n' "$(sw_count "$_gd_out")"
	return 1
}

# sw_guard_add KIND DETAIL: records a problem.
sw_guard_add() {
	_gd_out="${_gd_out}guard: $1: $2
"
}

# sw_guard_config: test_paths and test-skip.conf must be usable. Sets
# _gd_tp. Prints the reason and returns 2 when they are not.
sw_guard_config() {
	sw_conf_load "$SOFTWARY_ROOT/$SW_CONF_REL"
	_gd_tp=
	! sw_conf_has test_paths || _gd_tp=$(sw_conf_get test_paths)
	case $_gd_tp in
	'' | UNSET | NONE*)
		printf 'guard: test_paths is not set in %s\n' "$SW_CONF_REL"
		return 2
		;;
	esac
	sw_testskip_load || { printf '%s' "$SW_TS_ERRORS"; return 2; }
}

# sw_guard_run: the checks, on the variables of sw_guard.
sw_guard_run() {
	sw_guard_paths
	sw_guard_formal
	sw_guard_tests
}

# sw_guard_formal: under architecture/formal/ only what binds a human is
# protected (V8): a file that is added, deleted or renamed, and a record whose
# invariants or findings table differs from the base's. The model, its
# configurations and the other sections of a record are the loop's to keep
# up; the touches rule applies to them as to any path.
sw_guard_formal() {
	_gd_fl=$(git -C "$SOFTWARY_ROOT" -c core.quotePath=false diff --no-renames --name-status "$_gd_mb" "$_gd_head" -- architecture/formal/)
	while IFS='	' read -r _gd_st _gd_p; do
		[ -n "$_gd_p" ] || continue
		if [ "$_gd_st" != M ]; then
			sw_guard_add protected "$_gd_p"
			continue
		fi
		case $_gd_p in *.md) ;; *) continue ;; esac
		for _gd_sec in Invariants Findings; do
			_gd_a=$(git -C "$SOFTWARY_ROOT" show "$_gd_mb:$_gd_p" | sw_fmaint_section_raw "$_gd_sec")
			_gd_b=$(git -C "$SOFTWARY_ROOT" show "$_gd_head:$_gd_p" | sw_fmaint_section_raw "$_gd_sec")
			if [ "$_gd_a" != "$_gd_b" ]; then
				sw_guard_add protected "$_gd_p"
				break
			fi
		done
	done <<FORMAL
$_gd_fl
FORMAL
}

# sw_guard_paths: protected paths and paths outside touches.
sw_guard_paths() {
	_gd_srel=specs/$SW_JOB_SPEC/slices/$SW_JOB_SLICE.md
	_gd_tf=$(mktemp "${TMPDIR:-/tmp}/softwary-guard.XXXXXX") || return 2
	# The slice is read as the plan had it at the base: a job cannot widen
	# its own touches.
	if ! git -C "$SOFTWARY_ROOT" show "$_gd_mb:$_gd_srel" >"$_gd_tf" 2>/dev/null &&
		! git -C "$SOFTWARY_ROOT" show "$_gd_head:$_gd_srel" >"$_gd_tf" 2>/dev/null; then
		cat "$SW_JOB_SLICEFILE" >"$_gd_tf"
	fi
	_gd_touches=$(sw_guard_touches_of "$_gd_tf")
	rm -f "$_gd_tf"
	_gd_rrel=specs/$SW_JOB_SPEC/reviews/$SW_JOB_SLICE.md
	while IFS= read -r _gd_p; do
		[ -n "$_gd_p" ] || continue
		if sw_guard_protected "$_gd_p"; then
			sw_guard_add protected "$_gd_p"
		fi
		[ "$_gd_p" = "$_gd_srel" ] || [ "$_gd_p" = "$_gd_rrel" ] && continue
		_gd_hit=0
		while IFS= read -r _gd_e; do
			[ -n "$_gd_e" ] || continue
			if sw_guard_covers "$_gd_e" "$_gd_p"; then
				_gd_hit=1
				break
			fi
		done <<TOUCHES
$_gd_touches
TOUCHES
		[ "$_gd_hit" -eq 1 ] || sw_guard_add "outside touches" "$_gd_p"
	done <<CHANGED
$_gd_changed
CHANGED
}

# sw_guard_tests: deleted test files, criterion ids that left the tests and
# added lines that match a skip or focus marker, all under test_paths.
sw_guard_tests() {
	set -f
	# shellcheck disable=SC2086 # test_paths is a space-separated list of paths
	set -- $_gd_tp
	set +f
	_gd_del=$(git -C "$SOFTWARY_ROOT" -c core.quotePath=false diff --no-renames --name-only --diff-filter=D "$_gd_mb" "$_gd_head" -- "$@")
	while IFS= read -r _gd_p; do
		[ -z "$_gd_p" ] || sw_guard_add "test deleted" "$_gd_p"
	done <<DELETED
$_gd_del
DELETED
	_gd_ids='AC-[A-Z0-9]+-[0-9]{2}'
	_gd_old=$(git -C "$SOFTWARY_ROOT" grep -h -o -E "$_gd_ids" "$_gd_mb" -- "$@" | sort -u)
	_gd_new=$(git -C "$SOFTWARY_ROOT" grep -h -o -E "$_gd_ids" "$_gd_head" -- "$@" | sort -u)
	while IFS= read -r _gd_id; do
		[ -n "$_gd_id" ] || continue
		printf '%s\n' "$_gd_new" | grep -Fqx -e "$_gd_id" || sw_guard_add "criterion dropped" "$_gd_id"
	done <<OLD
$_gd_old
OLD
	[ "$SW_TS_NONE" -eq 0 ] || return 0
	_gd_pf=$(mktemp "${TMPDIR:-/tmp}/softwary-guard.XXXXXX") || return 2
	printf '%s' "$SW_TS_PATTERNS" >"$_gd_pf"
	_gd_added=$(git -C "$SOFTWARY_ROOT" -c core.quotePath=false diff -U0 --no-renames "$_gd_mb" "$_gd_head" -- "$@" | tr -d '\r' | awk '
		/^diff --git / { hdr = 1; next }
		/^@@/ { hdr = 0; next }
		hdr && /^\+\+\+ / { f = substr($0, 7); next }
		!hdr && /^\+/ { print f "\t" substr($0, 2) }')
	while IFS='	' read -r _gd_p _gd_l; do
		[ -n "$_gd_p" ] || continue
		if printf '%s\n' "$_gd_l" | grep -Eq -f "$_gd_pf"; then
			sw_guard_add "skip marker" "$_gd_p: $(sw_trim "$_gd_l")"
		fi
	done <<ADDED
$_gd_added
ADDED
	rm -f "$_gd_pf"
}
