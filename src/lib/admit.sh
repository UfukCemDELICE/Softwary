# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: the admission of a job. Sourced by bin/softwary. POSIX sh.
#
# `job start` admits a slice only when the run is open and not halted, fewer
# than `concurrency` jobs are active and the slice's `touches` cross those of
# no job that is not final (an escalated job still holds its paths). The
# admission and the opening of the job's record are one state-lock section.

# sw_admit_glob ENTRY: true when the touches entry has a glob character.
sw_admit_glob() {
	case $1 in *[*?[]*) return 0 ;; esac
	return 1
}

# sw_admit_cross A B: true when two touches entries can name the same path.
# Plain entries cross when equal or when one is a directory above the other
# (a trailing '/' is ignored); with a glob, the text up to the first glob
# character of each is taken, and the entries cross when one such prefix
# starts the other (cautious).
sw_admit_cross() {
	_ax_a=${1#./}
	_ax_b=${2#./}
	if ! sw_admit_glob "$_ax_a" && ! sw_admit_glob "$_ax_b"; then
		_ax_a=${_ax_a%/}
		_ax_b=${_ax_b%/}
		[ "$_ax_a" != "$_ax_b" ] || return 0
		case $_ax_a in "$_ax_b"/*) return 0 ;; esac
		case $_ax_b in "$_ax_a"/*) return 0 ;; esac
		return 1
	fi
	_ax_a=${_ax_a%%[*?[]*}
	_ax_b=${_ax_b%%[*?[]*}
	case $_ax_a in "$_ax_b"*) return 0 ;; esac
	case $_ax_b in "$_ax_a"*) return 0 ;; esac
	return 1
}

# sw_admit_touches JOB: the touches of the job's slice, one per line (nothing
# when the slice cannot be found).
sw_admit_touches() {
	sw_job_locate "$1" || return 0
	sw_guard_touches_of "$SW_JOB_SLICEFILE"
}

# sw_admit_pair JOB OTHER: prints "<entry> ~ <entry>" for the first pair of
# touches entries of the two jobs that cross; true when there is one.
sw_admit_pair() {
	_ap_mine=$(sw_admit_touches "$1")
	_ap_theirs=$(sw_admit_touches "$2")
	[ -n "$_ap_mine" ] && [ -n "$_ap_theirs" ] || return 1
	while IFS= read -r _ap_a; do
		[ -n "$_ap_a" ] || continue
		while IFS= read -r _ap_b; do
			[ -n "$_ap_b" ] || continue
			if sw_admit_cross "$_ap_a" "$_ap_b"; then
				printf '%s ~ %s\n' "$_ap_a" "$_ap_b"
				return 0
			fi
		done <<THEIRS
$_ap_theirs
THEIRS
	done <<MINE
$_ap_mine
MINE
	return 1
}

# sw_admit_open_jobs: the jobs that are not final (escalated ones included).
sw_admit_open_jobs() {
	for _ao in "$SW_STATE_ROOT/$SW_JOBS_REL"/*/job; do
		[ -f "$_ao" ] || continue
		sw_job_terminal "$(sw_kvf_get "$_ao" state)" && continue
		_ao=${_ao%/job}
		printf '%s\n' "${_ao##*/}"
	done
}

# sw_admit_overlap JOB [OTHER...]: prints "<other> (<entry> ~ <entry>)" for the
# first job, among the open ones and OTHER..., whose touches cross JOB's.
sw_admit_overlap() {
	_aj=$1
	shift
	for _ao_o in $(sw_admit_open_jobs) "$@"; do
		[ "$_ao_o" != "$_aj" ] || continue
		if _ao_p=$(sw_admit_pair "$_aj" "$_ao_o"); then
			printf '%s (%s)\n' "$_ao_o" "$_ao_p"
			return 0
		fi
	done
	return 0
}

# sw_admit_locked JOB BASE: every condition of `job start`, then the job's
# record (state ready) and its worktree. State lock held. Returns 0 (SW_ADMIT
# is `new`, or `resume` for a job that was left in `ready`), 1 refused, 2 error.
sw_admit_locked() {
	_ad_job=$1
	_ad_base=$2
	SW_ADMIT=new
	sw_run_open || { sw_job_refuse "$_ad_job" "no open run (./softwary run start)"; return 1; }
	if sw_run_halted; then
		sw_job_refuse "$_ad_job" "run is halted: $(sw_run_get halted)"
		return 1
	fi
	if [ -e "$(sw_job_file "$_ad_job")" ]; then
		[ "$(sw_job_get "$_ad_job" state)" = ready ] || { sw_job_refuse "$_ad_job" "the job already exists"; return 1; }
		SW_ADMIT=resume
		return 0
	fi
	sw_loop_load || { printf '%s' "$SW_LOOP_ERRORS"; return 2; }
	_ad_act=$(sw_job_active)
	if [ "$(printf '%s' "$_ad_act" | grep -c .)" -ge "$(sw_loop_get concurrency)" ]; then
		sw_job_refuse "$_ad_job" "concurrency limit $(sw_loop_get concurrency) reached ($(printf '%s' "$_ad_act" | paste -sd' ' -))"
		return 1
	fi
	_ad_ov=$(sw_admit_overlap "$_ad_job")
	[ -z "$_ad_ov" ] || { sw_job_refuse "$_ad_job" "touches overlap with $_ad_ov"; return 1; }
	[ "$(sw_job_branch_now)" = "$_ad_base" ] || { sw_job_refuse "$_ad_job" "not on the integration branch $_ad_base"; return 1; }
	sw_job_clean || { sw_job_refuse "$_ad_job" "working tree is not clean"; return 1; }
	if sw_wt_origin; then
		if ! git -C "$SW_STATE_ROOT" fetch -q origin "$_ad_base" >/dev/null 2>&1 ||
			! git -C "$SW_STATE_ROOT" merge -q --ff-only "origin/$_ad_base" >/dev/null 2>&1; then
			sw_job_refuse "$_ad_job" "could not fast-forward $_ad_base from origin"
			return 1
		fi
	fi
	if git -C "$SW_STATE_ROOT" rev-parse -q --verify "refs/heads/softwary/$_ad_job" >/dev/null 2>&1; then
		sw_job_refuse "$_ad_job" "branch softwary/$_ad_job exists"
		return 1
	fi
	sw_job_locate "$_ad_job" || return 2
	sw_fm_read "$SW_JOB_SLICEFILE"
	[ "$(sw_fm_get status)" = planned ] || { sw_job_refuse "$_ad_job" "slice is not planned"; return 1; }
	sw_fm_read "$SOFTWARY_ROOT/specs/$SW_JOB_SPEC/spec.md"
	[ "$(sw_fm_get status)" = approved ] || { sw_job_refuse "$_ad_job" "spec ${_ad_job%%-*} is not approved"; return 1; }
	_ad_un=$(sw_job_unmet "$_ad_job" "$SW_JOB_SLICEFILE")
	[ -z "$_ad_un" ] || { sw_job_refuse "$_ad_job" "dependency $_ad_un is not done"; return 1; }
	for _ad_k in $SW_APPROVAL_KINDS; do
		_ad_a=$(sw_approval_state "$_ad_k") || { sw_job_refuse "$_ad_job" "approvals.conf is malformed"; return 1; }
		[ "$_ad_a" = approved ] || { sw_job_refuse "$_ad_job" "$_ad_k approval is $_ad_a"; return 1; }
	done
	mkdir -p "$SW_STATE_ROOT/$SW_JOBS_REL/$_ad_job" || return 2
	sw_job_put "$_ad_job" state ready
	sw_job_put "$_ad_job" round 0
	sw_job_put "$_ad_job" started "$(date +%s)"
	sw_job_put "$_ad_job" tokens 0
	sw_job_put "$_ad_job" branch "softwary/$_ad_job"
	if ! sw_wt_add "$_ad_job" "$_ad_base"; then
		rm -rf "${SW_STATE_ROOT:?}/$SW_JOBS_REL/$_ad_job"
		return 2
	fi
}
