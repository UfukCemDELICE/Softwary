# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: `merge`. Sourced by bin/softwary. POSIX sh.
#
# `merge <job>` puts an approved job in the merge queue (approving -> queued)
# and, when nobody holds the merge lock, drains the queue (queue.sh). The job
# at the head of the queue is merged by sw_merge_one, which trusts no recorded
# PASS: it recomputes every condition on the exact commit it is about to merge
# (in the job's worktree), and either calls `gh pr merge` bound to that commit
# or hands the job to a human with the condition that failed.

# sw_merge_refuse JOB CONDITION: the job goes to the human and leaves the
# queue in one state section; gh pr merge is not called.
sw_merge_refuse() {
	sw_state_locked sw_merge_refuse_locked "$1" "$2"
	printf 'merge %s: refused: %s\n' "$1" "$2"
	return 1
}

sw_merge_refuse_locked() {
	sw_job_apply "$1" escalate "merge refused: $2" >/dev/null
	sw_queue_del "$1"
}

# sw_merge_conditions JOB BASE: the conditions, in the job's worktree
# (SOFTWARY_ROOT is the worktree while it runs). Sets SW_MERGE_SHA, the commit
# to merge. 0 all hold, 1 refused (already recorded), 2 cannot run.
sw_merge_conditions() {
	_mc_job=$1
	_mc_base=$2
	_mc_dir=$SW_STATE_ROOT/$SW_JOBS_REL/$_mc_job
	_mc_wt=$SOFTWARY_ROOT
	sw_job_locate "$_mc_job" || return 2
	_mc_spec=$SW_JOB_SPEC
	_mc_slice=$SW_JOB_SLICE
	_mc_sfile=$SW_JOB_SLICEFILE
	sw_loop_load || { printf '%s' "$SW_LOOP_ERRORS"; return 2; }

	# 1. limits
	_mc_over=$(sw_job_budget "$_mc_job")
	[ -z "$_mc_over" ] || { sw_merge_refuse "$_mc_job" "$_mc_over"; return 1; }
	# 2. bring in the integration branch; what is checked from here on is the
	# commit that will be merged
	if ! _mc_o=$(git -C "$_mc_wt" fetch -q origin "$_mc_base" 2>&1); then
		sw_merge_refuse "$_mc_job" "could not fetch origin/$_mc_base: $_mc_o"
		return 1
	fi
	if ! git -C "$_mc_wt" merge-base --is-ancestor "origin/$_mc_base" HEAD; then
		if ! git -C "$_mc_wt" merge -q --no-edit "origin/$_mc_base" >/dev/null 2>&1; then
			git -C "$_mc_wt" merge --abort >/dev/null 2>&1
			sw_merge_refuse "$_mc_job" "conflict with $_mc_base"
			return 1
		fi
	fi
	sw_job_push "$_mc_job" >/dev/null || { sw_merge_refuse "$_mc_job" "push failed"; return 1; }
	SW_MERGE_SHA=$(git -C "$_mc_wt" rev-parse HEAD)
	# 3. guard: protected paths, touches and loosened tests, before anything
	# the job could have changed (verify, approvals) is trusted
	_mc_ref=$(sw_job_verify_base "$_mc_base")
	_mc_grc=0
	_mc_g=$(sw_wt_softwary "$_mc_job" guard "$_mc_job" --base "$_mc_ref" 2>&1) || _mc_grc=$?
	if [ "$_mc_grc" -eq 2 ]; then
		sw_merge_refuse "$_mc_job" "guard could not run: $(printf '%s\n' "$_mc_g" | head -n 1)"
		return 1
	elif [ "$_mc_grc" -ne 0 ]; then
		_mc_first=$(printf '%s\n' "$_mc_g" | head -n 1)
		_mc_more=$(($(sw_count "$_mc_g") - 2))
		[ "$_mc_more" -le 0 ] || _mc_first="$_mc_first (+$_mc_more more)"
		sw_merge_refuse "$_mc_job" "$_mc_first"
		return 1
	fi
	# 4. approvals
	for _mc_k in $SW_APPROVAL_KINDS; do
		_mc_a=$(sw_approval_state "$_mc_k") || _mc_a=malformed
		[ "$_mc_a" = approved ] || { sw_merge_refuse "$_mc_job" "$_mc_k approval is $_mc_a"; return 1; }
	done
	# 5. the slice is done and its review approves
	sw_fm_read "$_mc_sfile"
	_mc_ss=$(sw_fm_get status)
	_mc_rd=
	if [ -f "$_mc_wt/specs/$_mc_spec/reviews/$_mc_slice.md" ]; then
		sw_fm_read "$_mc_wt/specs/$_mc_spec/reviews/$_mc_slice.md"
		_mc_rd=$(sw_fm_get decision)
	fi
	if [ "$_mc_ss" != "done" ] || [ "$_mc_rd" != approve ]; then
		sw_merge_refuse "$_mc_job" "the slice is not done with an approving review"
		return 1
	fi
	# 6. risk (a tier of the job's own paths counts as much as the spec's)
	_mc_risk=$(sw_wt_softwary "$_mc_job" risk "${_mc_job%%-*}" --base "$_mc_ref" 2>&1) || _mc_risk="risk: could not be computed"
	case $(printf '%s\n' "$_mc_risk" | tail -n 1) in
	"risk "*R3) sw_merge_refuse "$_mc_job" "risk tier is R3 (a human merges)"; return 1 ;;
	"risk "*R[12]) ;;
	*) sw_merge_refuse "$_mc_job" "risk could not be computed"; return 1 ;;
	esac
	# 7. the full verify
	if ! sw_wt_softwary "$_mc_job" verify --base "$_mc_ref" >"$_mc_dir/merge.log" 2>&1; then
		sw_merge_refuse "$_mc_job" "verify fails (see $SW_JOBS_REL/$_mc_job/merge.log)"
		return 1
	fi
	# 8. the PR's head is this commit and its checks pass
	if ! sw_job_pr_green "$_mc_job" "$SW_MERGE_SHA" "$SW_MERGE_SHA"; then
		sw_merge_refuse "$_mc_job" "$SW_JOB_WHY"
		return 1
	fi
	# 9. the evaluation of the reviewer must be current and meet the threshold,
	# or the merge is left to the human
	_mc_ev=$(sw_eval_state)
	case $_mc_ev in
	ok*) ;;
	*)
		sw_merge_refuse "$_mc_job" "auto-merge is off (evaluation $_mc_ev); merge the PR yourself and run ./softwary job merged $_mc_job"
		return 1
		;;
	esac
}

# sw_merge_record JOB SHA [DETAIL]: the job is merged: event, queue, the
# decision file, the main checkout and the job's worktree, in one state
# section.
sw_merge_record() {
	sw_state_locked sw_merge_record_locked "$@"
}

sw_merge_record_locked() {
	sw_job_apply "$1" merged "${3:-$2}" >/dev/null || return $?
	sw_queue_del "$1"
	printf 'merged: %s\n' "$2" >>"$SW_STATE_ROOT/$SW_JOBS_REL/$1/decision.md"
	_mr_base=$(sw_job_integration) || return 0
	if [ "$(sw_job_branch_now)" = "$_mr_base" ] && sw_job_clean; then
		git -C "$SW_STATE_ROOT" pull -q --ff-only origin "$_mr_base" >/dev/null 2>&1 ||
			printf 'merge: could not update %s from origin\n' "$_mr_base"
	fi
	sw_wt_remove_locked "$1" branch
}

# sw_merge_one JOB: merges the job at the head of the queue (state queued).
# Prints `merged: <job> <sha>` or the refusal; 0 merged, 1 refused, 2 error.
# A PR that is already merged (a drainer died after `gh pr merge`) is
# recorded, not merged again.
sw_merge_one() {
	_mo_job=$1
	_mo_base=$(sw_job_integration) || { printf 'merge: integration_branch is not set\n'; return 2; }
	_mo_n=$(sw_job_get "$_mo_job" pr)
	if [ -n "$_mo_n" ]; then
		_mo_st=$(gh pr view "$_mo_n" --json state --jq .state 2>/dev/null) || _mo_st=
		if [ "$_mo_st" = MERGED ]; then
			_mo_sha=$(sw_job_get "$_mo_job" merge_sha)
			sw_queue_integration "$_mo_job" "$_mo_sha" || return 2
			sw_merge_record "$_mo_job" "${_mo_sha:--}" "recovered: PR #$_mo_n already merged" || return 2
			printf 'merged: %s %s\n' "$_mo_job" "${_mo_sha:--}"
			return 0
		fi
	fi
	sw_wt_ensure "$_mo_job" || { sw_merge_refuse "$_mo_job" "no worktree and no branch softwary/$_mo_job"; return 1; }
	_mo_root=$SOFTWARY_ROOT
	SOFTWARY_ROOT=$(sw_wt_path "$_mo_job")
	_mo_rc=0
	sw_merge_conditions "$_mo_job" "$_mo_base" || _mo_rc=$?
	SOFTWARY_ROOT=$_mo_root
	[ "$_mo_rc" -eq 0 ] || return "$_mo_rc"
	_mo_sha=$SW_MERGE_SHA
	# merge exactly this commit; the SHA is kept first, so that a drainer that
	# dies after the merge can still check the integration branch
	sw_job_put "$_mo_job" merge_sha "$_mo_sha" || return 2
	if ! gh pr merge "$_mo_n" --squash --match-head-commit "$_mo_sha" >"$SW_STATE_ROOT/$SW_JOBS_REL/$_mo_job/merge-gh.log" 2>&1; then
		sw_merge_refuse "$_mo_job" "gh pr merge failed"
		return 1
	fi
	sw_queue_integration "$_mo_job" "$_mo_sha" || return 2
	sw_merge_record "$_mo_job" "$_mo_sha" || return 2
	printf 'merged: %s %s\n' "$_mo_job" "$_mo_sha"
}

# sw_merge_enqueue JOB: puts the job in the queue and tries the merge lock, in
# one state section. SW_MERGE_ROLE is `drainer` when this process got the lock.
sw_merge_enqueue() {
	SW_MERGE_ROLE=waiter
	sw_state_locked sw_merge_enqueue_locked "$1"
}

sw_merge_enqueue_locked() {
	if sw_run_halted; then
		sw_job_refuse "$1" "run is halted: $(sw_run_get halted)"
		return 1
	fi
	sw_job_state_is "$1" approving || return 1
	sw_queue_add "$1"
	sw_job_apply "$1" enqueue >/dev/null || { sw_queue_del "$1"; return 1; }
	_me_rc=0
	sw_lock_try merge || _me_rc=$?
	case $_me_rc in
	0) SW_MERGE_ROLE=drainer ;;
	1) printf 'queued: %s (position %s)\n' "$1" "$(sw_queue_pos "$1")" ;;
	*) return 2 ;;
	esac
}

# sw_merge_job JOB
sw_merge_job() {
	if [ $# -ne 1 ]; then
		printf 'usage: ./softwary merge <job>\n' >&2
		return 2
	fi
	_mg_job=$1
	sw_job_known "$_mg_job" || return 2
	sw_job_state_is "$_mg_job" approving || return 1
	if [ -f "$SW_STATE_ROOT/$SW_JOBS_REL/$_mg_job/decision.md" ]; then
		sw_fm_read "$SW_STATE_ROOT/$SW_JOBS_REL/$_mg_job/decision.md"
		_mg_dec=$(sw_fm_get decision)
	else
		_mg_dec=
	fi
	[ "$_mg_dec" = merge ] || { sw_job_refuse "$_mg_job" "no decision to merge (decision.md: ${_mg_dec:-missing})"; return 1; }
	sw_wt_check "$_mg_job" || return 2
	_mg_rc=0
	sw_merge_enqueue "$_mg_job" || _mg_rc=$?
	[ "$_mg_rc" -eq 0 ] || return "$_mg_rc"
	[ "$SW_MERGE_ROLE" = drainer ] || return 0
	sw_queue_drain "$_mg_job" || return $?
	if sw_queue_has "$_mg_job"; then
		printf 'queued: %s (position %s)\n' "$_mg_job" "$(sw_queue_pos "$_mg_job")"
		return 0
	fi
	[ "$SW_DRAIN_OWN" -eq 0 ] || return 1
	return 0
}
