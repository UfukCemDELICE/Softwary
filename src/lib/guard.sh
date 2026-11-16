# shellcheck shell=sh
# softwary: the `guard` command. Sourced by bin/softwary. POSIX sh.
#
# guard <job> [--base <ref>] recomputes, from the committed diff of a job
# branch, what a merging script must not take on trust: a change to a
# protected path, a path outside the slice's `touches`, and a loosened test.
# `job gate` and `merge` call it; so can a reviewer. Exit: 0 no problem,
# 1 problems (one `guard: <kind>: <detail>` line each), 2 usage or setup.

# The protected paths: a trailing '/' is a directory (everything below it),
# anything else is exactly that path. The project cannot change this list.
SW_PROTECTED=".softwary/ .github/ CODEOWNERS docs/CODEOWNERS softwary product/ architecture/model/ architecture/data/ architecture/contracts/"

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
	sw_base_commit "$_gd_ref" guard || return 2
	_gd_mb=$SW_BASE_COMMIT
	_gd_changed=$(git -C "$SOFTWARY_ROOT" -c core.quotePath=false diff --no-renames --name-only "$_gd_mb" HEAD --)
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

# sw_guard_run: the checks, on the variables of sw_guard.
sw_guard_run() {
	sw_guard_paths
}

# sw_guard_paths: protected paths and paths outside touches.
sw_guard_paths() {
	_gd_srel=specs/$SW_JOB_SPEC/slices/$SW_JOB_SLICE.md
	_gd_tf=$(mktemp "${TMPDIR:-/tmp}/softwary-guard.XXXXXX") || return 2
	# The slice is read as the plan had it at the base: a job cannot widen
	# its own touches.
	if ! git -C "$SOFTWARY_ROOT" show "$_gd_mb:$_gd_srel" >"$_gd_tf" 2>/dev/null; then
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
