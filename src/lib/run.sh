# shellcheck shell=sh
# softwary: `merge` and `run`. Sourced by bin/softwary. POSIX sh.
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
	# 3. guard: protected paths, touches and loosened tests, before anything
	# the job could have changed (verify, approvals) is trusted
	_mg_ref=$(sw_job_verify_base "$_mg_base")
	_mg_grc=0
	_mg_g=$(sh "$SOFTWARY_HOME/bin/softwary" guard "$_mg_job" --base "$_mg_ref" 2>&1) || _mg_grc=$?
	if [ "$_mg_grc" -eq 2 ]; then
		sw_merge_refuse "$_mg_job" "guard could not run: $(printf '%s\n' "$_mg_g" | head -n 1)"
		return 1
	elif [ "$_mg_grc" -ne 0 ]; then
		_mg_first=$(printf '%s\n' "$_mg_g" | head -n 1)
		_mg_more=$(($(sw_count "$_mg_g") - 2))
		[ "$_mg_more" -le 0 ] || _mg_first="$_mg_first (+$_mg_more more)"
		sw_merge_refuse "$_mg_job" "$_mg_first"
		return 1
	fi
	# 4. approvals
	for _mg_k in $SW_APPROVAL_KINDS; do
		_mg_a=$(sw_approval_state "$_mg_k") || _mg_a=malformed
		[ "$_mg_a" = approved ] || { sw_merge_refuse "$_mg_job" "$_mg_k approval is $_mg_a"; return 1; }
	done
	# 5. the slice is done and its review approves
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
	# 6. risk (a tier of the job's own paths counts as much as the spec's)
	_mg_risk=$(sh "$SOFTWARY_HOME/bin/softwary" risk "${_mg_job%%-*}" --base "$_mg_ref" 2>&1) || _mg_risk="risk: could not be computed"
	case $(printf '%s\n' "$_mg_risk" | tail -n 1) in
	"risk "*R3) sw_merge_refuse "$_mg_job" "risk tier is R3 (a human merges)"; return 1 ;;
	"risk "*R[12]) ;;
	*) sw_merge_refuse "$_mg_job" "risk could not be computed"; return 1 ;;
	esac
	# 7. the full verify
	if ! sh "$SOFTWARY_HOME/bin/softwary" verify --base "$_mg_ref" >"$_mg_dir/merge.log" 2>&1; then
		sw_merge_refuse "$_mg_job" "verify fails (see $SW_JOBS_REL/$_mg_job/merge.log)"
		return 1
	fi
	# 8. the PR's head is this commit and its checks pass
	if ! sw_job_pr_green "$_mg_job" "$_mg_sha" "$_mg_sha"; then
		sw_merge_refuse "$_mg_job" "$SW_JOB_WHY"
		return 1
	fi
	# 9. the evaluation of the reviewer must be current and meet the threshold,
	# or the merge is left to the human
	_mg_ev=$(sw_eval_state)
	case $_mg_ev in
	ok*) ;;
	*)
		sw_merge_refuse "$_mg_job" "auto-merge is off (evaluation $_mg_ev); merge the PR yourself and run ./softwary job merged $_mg_job"
		return 1
		;;
	esac
	# 10. merge exactly this commit
	if ! gh pr merge "$(sw_job_get "$_mg_job" pr)" --squash --match-head-commit "$_mg_sha" >"$_mg_dir/merge-gh.log" 2>&1; then
		sw_merge_refuse "$_mg_job" "gh pr merge failed"
		return 1
	fi
	git -C "$SOFTWARY_ROOT" checkout -q "$_mg_base" || return 2
	git -C "$SOFTWARY_ROOT" pull -q --ff-only origin "$_mg_base" >/dev/null 2>&1 || printf 'merge: could not update %s from origin\n' "$_mg_base"
	sw_job_apply "$_mg_job" merged "$_mg_sha" || return 2
	printf 'merged: %s\n' "$_mg_sha" >>"$_mg_dir/decision.md"
}

# --- run --------------------------------------------------------------------

# sw_run_time EPOCH: a UTC time for an epoch (the epoch itself when `date`
# cannot format one).
sw_run_time() {
	date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$1"
}

# sw_run_start: opens the run when everything it needs is in order; an open
# run is resumed with its clock as it was.
sw_run_start() {
	if sw_run_open; then
		printf 'run: resuming (started %s)\n' "$(sw_run_time "$(sw_run_get started)")"
		return 0
	fi
	sw_loop_load || { printf '%s' "$SW_LOOP_ERRORS"; return 2; }
	sw_models_load || { printf '%s' "$SW_MODELS_ERRORS"; return 2; }
	if ! _rs_ap=$(sw_approvals_problems); then
		printf '%s\n' "$_rs_ap"
		return 2
	fi
	_rs_base=$(sw_job_integration) || { printf 'run start: integration_branch is not set in %s\n' "$SW_CONF_REL"; return 2; }
	if ! _rs_pp=$(sw_plan_problems); then
		printf '%s\n' "$_rs_pp"
		printf 'run start: the plan has problems (./softwary plan check)\n'
		return 1
	fi
	[ "$(sw_job_branch_now)" = "$_rs_base" ] || { printf 'run start: not on the integration branch %s\n' "$_rs_base"; return 2; }
	sw_job_clean || { printf 'run start: working tree is not clean\n'; return 2; }
	rm -f "$SOFTWARY_ROOT/$SW_RUN_REL"
	sw_kvf_put "$SOFTWARY_ROOT/$SW_RUN_REL" started "$(date +%s)" || return 2
	sw_kvf_put "$SOFTWARY_ROOT/$SW_RUN_REL" tokens 0
	sw_event - run_start - - "" || return 2
	printf 'run: started\n'
}

# sw_run_over: prints the run limit that is exceeded (loop.conf loaded).
sw_run_over() {
	_ro_l=$(sw_loop_num max_run_minutes)
	_ro_s=$(sw_run_get started)
	if [ -n "$_ro_l" ] && [ -n "$_ro_s" ] && [ $(($(date +%s) - _ro_s)) -gt $((_ro_l * 60)) ]; then
		printf 'max_run_minutes\n'
		return 0
	fi
	_ro_l=$(sw_loop_num max_run_tokens)
	if [ -n "$_ro_l" ] && [ "$(sw_run_get tokens)" -gt "$_ro_l" ]; then
		printf 'max_run_tokens\n'
	fi
	return 0
}

# sw_run_ready: prints the next job that can start: spec numbers and slice
# numbers in order; the spec approved, the slice planned, its dependencies
# done in the working tree, and no job directory (so an abandoned job's slice
# is not started again).
sw_run_ready() {
	for _rr_dir in "$SOFTWARY_ROOT"/specs/*/; do
		[ -f "${_rr_dir}spec.md" ] || continue
		_rr_dir=${_rr_dir%/}
		_rr_dn=${_rr_dir##*/}
		sw_fm_read "$_rr_dir/spec.md"
		[ "$(sw_fm_get status)" = approved ] || continue
		for _rr_n in $(find "$_rr_dir/slices" -type f -name 'S*.md' 2>/dev/null | sed -n 's|.*/S\([0-9][0-9]*\)\.md$|\1|p' | sort -n); do
			_rr_job=${_rr_dn%%-*}-S$_rr_n
			[ ! -e "$SOFTWARY_ROOT/$SW_JOBS_REL/$_rr_job" ] || continue
			sw_fm_read "$_rr_dir/slices/S$_rr_n.md"
			[ "$(sw_fm_get status)" = planned ] || continue
			[ -z "$(sw_job_unmet "$_rr_job" "$_rr_dir/slices/S$_rr_n.md")" ] || continue
			printf '%s\n' "$_rr_job"
			return 0
		done
	done
	return 1
}

# sw_run_next: prints what the orchestrator does next: stop, resume <job>
# <state>, start <job>, waiting: <jobs> or none.
sw_run_next() {
	sw_run_open || { printf 'run: no open run (./softwary run start)\n'; return 2; }
	sw_loop_load || { printf '%s' "$SW_LOOP_ERRORS"; return 2; }
	_rn_over=$(sw_run_over)
	if [ -n "$_rn_over" ]; then
		printf 'stop: run limit (%s)\n' "$_rn_over"
		return 1
	fi
	_rn_act=$(sw_job_active | head -n 1)
	if [ -n "$_rn_act" ]; then
		printf 'resume %s %s\n' "$_rn_act" "$(sw_job_get "$_rn_act" state)"
		return 0
	fi
	if _rn_job=$(sw_run_ready); then
		printf 'start %s\n' "$_rn_job"
		return 0
	fi
	_rn_wait=$(sw_job_waiting)
	if [ -n "$_rn_wait" ]; then
		printf 'waiting: %s\n' "$(printf '%s\n' "$_rn_wait" | paste -sd' ' -)"
	else
		printf 'none\n'
	fi
}

# sw_run_stop: closes the run.
sw_run_stop() {
	sw_run_open || { printf 'run: no open run\n'; return 2; }
	sw_kvf_put "$SOFTWARY_ROOT/$SW_RUN_REL" stopped "$(date +%s)" || return 2
	sw_event - run_stop - - "" || return 2
	printf 'run: stopped\n'
}

# sw_run start | next | stop
sw_run() {
	if [ $# -ne 1 ]; then
		printf 'usage: ./softwary run start|next|stop\n' >&2
		return 2
	fi
	case $1 in
	start) sw_run_start ;;
	next) sw_run_next ;;
	stop) sw_run_stop ;;
	*)
		printf 'usage: ./softwary run start|next|stop\n' >&2
		return 2
		;;
	esac
}
