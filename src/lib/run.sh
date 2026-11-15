# shellcheck shell=sh
# softwary: `merge` (and `run`). Sourced by bin/softwary. POSIX sh.
#
# `merge <job>` trusts no recorded PASS: it recomputes every condition on the
# exact commit it is about to merge, and either calls `gh pr merge` bound to
# that commit or hands the job to a human with the condition that failed.

# sw_merge_refuse JOB CONDITION: escalates the job; gh pr merge is not called.
sw_merge_refuse() {
	sw_job_apply "$1" escalate "merge refused: $2" >/dev/null
	printf 'merge %s: refused: %s\n' "$1" "$2"
	return 1
}

# sw_merge_job JOB
sw_merge_job() {
	if [ $# -ne 1 ]; then
		printf 'usage: ./softwary merge <job>\n' >&2
		return 2
	fi
	_mg_job=$1
	sw_job_known "$_mg_job" || return 2
	_mg_st=$(sw_job_get "$_mg_job" state)
	[ "$_mg_st" = approving ] || { sw_job_refuse "$_mg_job" "state is $_mg_st, not approving"; return 1; }
	_mg_dir=$SOFTWARY_ROOT/$SW_JOBS_REL/$_mg_job
	if [ -f "$_mg_dir/decision.md" ]; then
		sw_fm_read "$_mg_dir/decision.md"
		_mg_dec=$(sw_fm_get decision)
	else
		_mg_dec=
	fi
	[ "$_mg_dec" = merge ] || { sw_job_refuse "$_mg_job" "no decision to merge (decision.md: ${_mg_dec:-missing})"; return 1; }
	sw_job_on_branch "$_mg_job" || return 2
	_mg_base=$(sw_job_integration) || { printf 'merge: integration_branch is not set\n'; return 2; }
	sw_job_locate "$_mg_job" || return 2
	_mg_spec=$SW_JOB_SPEC
	_mg_slice=$SW_JOB_SLICE
	_mg_sfile=$SW_JOB_SLICEFILE
	sw_loop_load || { printf '%s' "$SW_LOOP_ERRORS"; return 2; }

	# 1. limits
	_mg_over=$(sw_job_budget "$_mg_job")
	[ -z "$_mg_over" ] || { sw_merge_refuse "$_mg_job" "$_mg_over"; return 1; }
	# 2. bring in the integration branch; what is checked from here on is the
	# commit that will be merged
	if ! _mg_o=$(git -C "$SOFTWARY_ROOT" fetch -q origin "$_mg_base" 2>&1); then
		sw_merge_refuse "$_mg_job" "could not fetch origin/$_mg_base: $_mg_o"
		return 1
	fi
	if ! git -C "$SOFTWARY_ROOT" merge-base --is-ancestor "origin/$_mg_base" HEAD; then
		if ! git -C "$SOFTWARY_ROOT" merge -q --no-edit "origin/$_mg_base" >/dev/null 2>&1; then
			git -C "$SOFTWARY_ROOT" merge --abort >/dev/null 2>&1
			sw_merge_refuse "$_mg_job" "conflict with $_mg_base"
			return 1
		fi
	fi
	sw_job_push "$_mg_job" >/dev/null || { sw_merge_refuse "$_mg_job" "push failed"; return 1; }
	_mg_sha=$(git -C "$SOFTWARY_ROOT" rev-parse HEAD)
	# 3. approvals
	for _mg_k in $SW_APPROVAL_KINDS; do
		_mg_a=$(sw_approval_state "$_mg_k") || _mg_a=malformed
		[ "$_mg_a" = approved ] || { sw_merge_refuse "$_mg_job" "$_mg_k approval is $_mg_a"; return 1; }
	done
	# 4. the slice is done and its review approves
	sw_fm_read "$_mg_sfile"
	_mg_ss=$(sw_fm_get status)
	_mg_rd=
	if [ -f "$SOFTWARY_ROOT/specs/$_mg_spec/reviews/$_mg_slice.md" ]; then
		sw_fm_read "$SOFTWARY_ROOT/specs/$_mg_spec/reviews/$_mg_slice.md"
		_mg_rd=$(sw_fm_get decision)
	fi
	if [ "$_mg_ss" != "done" ] || [ "$_mg_rd" != approve ]; then
		sw_merge_refuse "$_mg_job" "the slice is not done with an approving review"
		return 1
	fi
	# 5. risk
	_mg_ref=$(sw_job_verify_base "$_mg_base")
	_mg_risk=$(sh "$SOFTWARY_HOME/bin/softwary" risk "${_mg_job%%-*}" --base "$_mg_ref" 2>&1) || _mg_risk="risk: could not be computed"
	case $(printf '%s\n' "$_mg_risk" | tail -n 1) in
	"risk "*R3) sw_merge_refuse "$_mg_job" "risk tier is R3 (a human merges)"; return 1 ;;
	"risk "*R[12]) ;;
	*) sw_merge_refuse "$_mg_job" "risk could not be computed"; return 1 ;;
	esac
	# 6. the full verify
	if ! sh "$SOFTWARY_HOME/bin/softwary" verify --base "$_mg_ref" >"$_mg_dir/merge.log" 2>&1; then
		sw_merge_refuse "$_mg_job" "verify fails (see $SW_JOBS_REL/$_mg_job/merge.log)"
		return 1
	fi
	# 7. the PR's head is this commit and its checks pass
	if ! sw_job_pr_green "$_mg_job" "$_mg_sha" "$_mg_sha"; then
		sw_merge_refuse "$_mg_job" "$SW_JOB_WHY"
		return 1
	fi
	# 8. merge exactly this commit
	if ! gh pr merge "$(sw_job_get "$_mg_job" pr)" --squash --match-head-commit "$_mg_sha" >"$_mg_dir/merge-gh.log" 2>&1; then
		sw_merge_refuse "$_mg_job" "gh pr merge failed"
		return 1
	fi
	git -C "$SOFTWARY_ROOT" checkout -q "$_mg_base" || return 2
	git -C "$SOFTWARY_ROOT" pull -q --ff-only origin "$_mg_base" >/dev/null 2>&1 || printf 'merge: could not update %s from origin\n' "$_mg_base"
	sw_job_apply "$_mg_job" merged "$_mg_sha" || return 2
	printf 'merged: %s\n' "$_mg_sha" >>"$_mg_dir/decision.md"
}
