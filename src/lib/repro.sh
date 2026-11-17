# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_REPRO_* globals are read by job.sh and merge.sh
# softwary: `repro` (V7). Sourced by bin/softwary. POSIX sh.
#
# A slice that fixes a bug names the tests that reproduce it (`repro:` in its
# front matter). Test first is proved here, by computing it: each of those
# tests must fail on the base (the code before the job) and pass on the job.
# The base run happens in a temporary worktree at the common ancestor, made
# ready with `bootstrap`, with the job's copy of the tests put in; that
# worktree is removed whatever happens. The job's own worktree and the main
# checkout are not touched.
# `job gate` runs it after guard and before verify; `merge` works it out again
# on the commit it is about to merge.

SW_REPRO_REL=.softwary/state/repro
# The lines that are a problem (the others say what held).
SW_REPRO_PROBLEM_RE=' (passes on the base \(it does not reproduce the bug\)|fails on the job|is not changed by the job|is missing in the job)$'

sw_repro_usage() {
	printf 'usage: ./softwary repro <job> [--base <ref>]\n' >&2
}

# sw_repro_first_problem: reads repro's output on stdin and prints the first
# line that is a problem (the first line when none is).
sw_repro_first_problem() {
	_rf_all=$(cat)
	_rf_p=$(printf '%s\n' "$_rf_all" | grep -E -e "$SW_REPRO_PROBLEM_RE" | head -n 1)
	if [ -n "$_rf_p" ]; then printf '%s\n' "$_rf_p"; else printf '%s\n' "$_rf_all" | head -n 1; fi
}

# sw_repro_remove DIR / sw_repro_add DIR COMMIT: the temporary worktree (the
# state lock is held by the caller, as for every git worktree command).
sw_repro_remove() {
	if [ -e "$1" ]; then
		git -C "$SW_STATE_ROOT" worktree remove --force "$1" >/dev/null 2>&1 || rm -rf "$1"
	fi
	git -C "$SW_STATE_ROOT" worktree prune >/dev/null 2>&1
	rmdir "$SW_STATE_ROOT/$SW_REPRO_REL" 2>/dev/null || :
}

sw_repro_add() {
	mkdir -p "$(dirname "$1")" || return 2
	if ! _ra_o=$(git -C "$SW_STATE_ROOT" worktree add -q --detach "$1" "$2" 2>&1); then
		printf 'repro: could not open the base: %s\n' "$_ra_o"
		return 2
	fi
}

# sw_repro_cleanup: the exit trap of the run.
sw_repro_cleanup() {
	[ -z "${_rp_wt:-}" ] || sw_state_locked sw_repro_remove "$_rp_wt"
}

# sw_repro_exec DIR CMD LOG PATH: runs CMD in DIR, its output appended to LOG
# under a line with PATH; the exit code of CMD.
sw_repro_exec() {
	printf '== %s\n' "$4" >>"$3"
	_re_rc=0
	(cd "$1" && sh -c "$2") >>"$3" 2>&1 </dev/null || _re_rc=$?
	return "$_re_rc"
}

# sw_repro_run: the two runs, in a subshell of sw_repro that removes the base
# worktree on every way out. Uses _rp_* of sw_repro.
sw_repro_run() {
	_rp_wt=$SW_STATE_ROOT/$SW_REPRO_REL/$_rp_job
	trap 'sw_repro_cleanup' EXIT
	trap 'exit 129' HUP
	trap 'exit 130' INT
	trap 'exit 143' TERM
	set -f
	sw_state_locked sw_repro_remove "$_rp_wt"
	_rp_blog=$SW_STATE_ROOT/$SW_LOGS_REL/repro-$_rp_job-base.log
	_rp_jlog=$SW_STATE_ROOT/$SW_LOGS_REL/repro-$_rp_job-job.log
	mkdir -p "$SW_STATE_ROOT/$SW_LOGS_REL" || return 2
	: >"$_rp_blog"
	: >"$_rp_jlog"
	_rp_bad=0
	_rp_todo=
	for _rp_p in $_rp_paths; do
		if ! git -C "$_rp_tree" cat-file -e "HEAD:./$_rp_p" 2>/dev/null; then
			printf 'repro: %s is missing in the job\n' "$_rp_p"
			_rp_bad=$((_rp_bad + 1))
		elif git -C "$_rp_tree" diff --quiet "$_rp_mb" HEAD -- "$_rp_p"; then
			printf 'repro: %s is not changed by the job\n' "$_rp_p"
			_rp_bad=$((_rp_bad + 1))
		else
			_rp_todo="$_rp_todo$_rp_p
"
		fi
	done
	if [ -n "$_rp_todo" ]; then
		_rp_boot=$(sw_wt_bootstrap_cmd) || { printf 'repro: %s\n' "$_rp_boot"; return 2; }
		sw_state_locked sw_repro_add "$_rp_wt" "$_rp_mb" || return 2
		if [ -n "$_rp_boot" ] && ! sw_repro_exec "$_rp_wt" "$_rp_boot" "$_rp_blog" bootstrap; then
			printf 'repro: bootstrap failed on the base (see %s/repro-%s-base.log)\n' "$SW_LOGS_REL" "$_rp_job"
			return 2
		fi
		_rp_bl=
		while IFS= read -r _rp_p; do
			[ -n "$_rp_p" ] || continue
			# the job's copy of the test goes into the base
			mkdir -p "$(dirname "$_rp_wt/$_rp_p")" || return 2
			git -C "$_rp_tree" show "HEAD:./$_rp_p" >"$_rp_wt/$_rp_p" || return 2
			case $(git -C "$_rp_tree" ls-tree HEAD -- "$_rp_p") in 100755*) chmod +x "$_rp_wt/$_rp_p" ;; esac
			_rp_cmd=$(sw_scoped_command "$_rp_test_files" "$(sw_scoped_list "$_rp_p")")
			if sw_repro_exec "$_rp_wt" "$_rp_cmd" "$_rp_blog" "$_rp_p"; then
				_rp_bl="${_rp_bl}repro: $_rp_p passes on the base (it does not reproduce the bug)
"
				_rp_bad=$((_rp_bad + 1))
			else
				_rp_bl="${_rp_bl}repro: $_rp_p fails on the base
"
			fi
		done <<REPRO_TODO
$_rp_todo
REPRO_TODO
		printf '%s' "$_rp_bl"
		while IFS= read -r _rp_p; do
			[ -n "$_rp_p" ] || continue
			_rp_cmd=$(sw_scoped_command "$_rp_test_files" "$(sw_scoped_list "$_rp_p")")
			if sw_repro_exec "$_rp_tree" "$_rp_cmd" "$_rp_jlog" "$_rp_p"; then
				printf 'repro: %s passes on the job\n' "$_rp_p"
			else
				printf 'repro: %s fails on the job\n' "$_rp_p"
				_rp_bad=$((_rp_bad + 1))
			fi
		done <<REPRO_TODO2
$_rp_todo
REPRO_TODO2
	fi
	if [ "$_rp_bad" -eq 0 ]; then
		printf 'repro: no problems\n'
		return 0
	fi
	printf 'repro: %s problem(s)\n' "$_rp_bad"
	return 1
}

# sw_repro JOB [--base REF]: exit 0 the tests fail on the base and pass on the
# job (or there are none), 1 a problem, 2 usage or configuration.
sw_repro() {
	_rp_job=
	_rp_ref=
	while [ $# -gt 0 ]; do
		case $1 in
		--base)
			[ $# -ge 2 ] || { sw_repro_usage; return 2; }
			_rp_ref=$2
			shift 2
			;;
		-*)
			sw_repro_usage
			return 2
			;;
		*)
			[ -z "$_rp_job" ] || { sw_repro_usage; return 2; }
			_rp_job=$1
			shift
			;;
		esac
	done
	[ -n "$_rp_job" ] || { sw_repro_usage; return 2; }
	sw_job_valid_id "$_rp_job" || { printf 'repro: %s is not a job (NNN-S<n>)\n' "$_rp_job"; return 2; }
	# the job's code is in its worktree when it has one
	if sw_wt_exists "$_rp_job"; then SOFTWARY_ROOT=$(sw_wt_path "$_rp_job"); fi
	_rp_tree=$SOFTWARY_ROOT
	sw_job_locate "$_rp_job" || { printf 'repro: no slice %s\n' "$_rp_job"; return 2; }
	if [ -z "$_rp_ref" ]; then
		sw_default_base repro || return 2
		_rp_ref=$SW_DEFAULT_BASE
	fi
	sw_base_commit "$_rp_ref" repro || return 2
	_rp_mb=$SW_BASE_COMMIT
	# the slice as the base had it: a job cannot take its own repro out
	_rp_f=$(mktemp "${TMPDIR:-/tmp}/softwary-repro.XXXXXX") || return 2
	if ! git -C "$SOFTWARY_ROOT" show "$_rp_mb:./specs/$SW_JOB_SPEC/slices/$SW_JOB_SLICE.md" >"$_rp_f" 2>/dev/null; then
		cat "$SW_JOB_SLICEFILE" >"$_rp_f"
	fi
	sw_fm_read "$_rp_f"
	rm -f "$_rp_f"
	_rp_paths=$(sw_fm_get repro)
	if [ -z "$_rp_paths" ]; then
		printf 'repro: none\n'
		return 0
	fi
	sw_conf_load "$SOFTWARY_ROOT/$SW_CONF_REL"
	if [ -n "$SW_CONF_ERRORS" ]; then
		printf '%s' "$SW_CONF_ERRORS"
		return 2
	fi
	_rp_sp=$(sw_scoped_problems)
	if [ -n "$_rp_sp" ]; then
		printf '%s\n' "$_rp_sp"
		return 2
	fi
	_rp_test_files=
	! sw_conf_has test_files || _rp_test_files=$(sw_conf_get test_files)
	case $_rp_test_files in
	'' | UNSET | NONE | NONE:*)
		printf 'repro: test_files is %s in %s (it must be the command that runs given tests, with {files})\n' \
			"$(case $_rp_test_files in NONE | NONE:*) printf NONE ;; *) printf UNSET ;; esac)" "$SW_CONF_REL"
		return 2
		;;
	esac
	( sw_repro_run )
}
