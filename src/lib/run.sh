# shellcheck shell=sh
# softwary: `run`. Sourced by bin/softwary. POSIX sh.
#
# The run (.softwary/state/run) bounds the jobs together: it is opened by
# `run start`, tells the orchestrator what to do next (`run next`: one line per
# thing to do) and is closed by `run stop`. The merge is in merge.sh and
# queue.sh; a job's admission is in admit.sh.

# sw_run_time EPOCH: a UTC time for an epoch (the epoch itself when `date`
# cannot format one).
sw_run_time() {
	date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '%s' "$1"
}

# sw_run_start: opens the run when everything it needs is in order; an open
# run is resumed with its clock as it was, after dead owners' locks are broken
# and stale worktree records pruned. A halted run goes on only when the tip of
# the integration branch passes the full verify again.
sw_run_start() {
	_rs_b=$(sw_wt_bootstrap_cmd) || { printf '%s\n' "$_rs_b"; return 2; }
	# A waived check is checked on the files of every change: no waiver
	# without its scoped command (the substitution above loaded the
	# configuration in a subshell only).
	sw_conf_load "$SW_STATE_ROOT/$SW_CONF_REL"
	_rs_sp=$(sw_scoped_problems)
	_rs_sm=$(sw_scoped_missing)
	if [ -n "$_rs_sp" ] || [ -n "$_rs_sm" ]; then
		[ -z "$_rs_sp" ] || printf '%s\n' "$_rs_sp"
		for _rs_k in $_rs_sm; do
			printf 'run start: %s_files is not set in %s (required: %s has a waiver)\n' "$_rs_k" "$SW_CONF_REL" "$_rs_k"
		done
		return 2
	fi
	if sw_run_open; then
		sw_state_locked sw_run_housekeeping
		if sw_run_halted; then
			sw_run_unhalt || return $?
		fi
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
	sw_state_locked sw_run_open_locked
}

sw_run_open_locked() {
	rm -f "$SW_STATE_ROOT/$SW_RUN_REL"
	sw_kvf_put "$SW_STATE_ROOT/$SW_RUN_REL" started "$(date +%s)" || return 2
	sw_kvf_put "$SW_STATE_ROOT/$SW_RUN_REL" tokens 0
	sw_event - run_start - - "" || return 2
	printf 'run: started\n'
}

sw_run_housekeeping() {
	git -C "$SW_STATE_ROOT" worktree prune >/dev/null 2>&1
	sw_lock_sweep
}

# sw_run_unhalt: the integration branch's tip is verified again; when it
# passes, the halt is lifted. 1 when it is still red, 2 when it cannot be
# checked.
sw_run_unhalt() {
	_ru_base=$(sw_job_integration) || { printf 'run start: integration_branch is not set in %s\n' "$SW_CONF_REL"; return 2; }
	if sw_wt_origin; then
		git -C "$SW_STATE_ROOT" fetch -q origin "$_ru_base" >/dev/null 2>&1 || :
	fi
	_ru_rc=0
	sw_queue_verify "$_ru_base" || _ru_rc=$?
	case $_ru_rc in
	0) ;;
	1)
		printf 'run start: integration is still red (see %s)\n' "$SW_INTEGRATION_LOG"
		return 1
		;;
	*)
		printf 'run start: the integration branch could not be checked (see %s)\n' "$SW_INTEGRATION_LOG"
		return 2
		;;
	esac
	sw_state_locked sw_run_unhalt_locked
}

sw_run_unhalt_locked() {
	sw_kvf_del "$SW_STATE_ROOT/$SW_RUN_REL" halted
	sw_event - integration_green - - ""
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

# sw_run_ready: prints the jobs that can start, one per line: spec numbers and
# slice numbers in order; the spec approved, the slice planned, its
# dependencies done in the working tree, and no job directory (so an
# abandoned job's slice is not started again).
sw_run_ready() {
	for _rr_dir in "$SOFTWARY_ROOT"/specs/*/; do
		[ -f "${_rr_dir}spec.md" ] || continue
		_rr_dir=${_rr_dir%/}
		_rr_dn=${_rr_dir##*/}
		sw_fm_read "$_rr_dir/spec.md"
		[ "$(sw_fm_get status)" = approved ] || continue
		for _rr_n in $(find "$_rr_dir/slices" -type f -name 'S*.md' 2>/dev/null | sed -n 's|.*/S\([0-9][0-9]*\)\.md$|\1|p' | sort -n); do
			_rr_job=${_rr_dn%%-*}-S$_rr_n
			[ ! -e "$SW_STATE_ROOT/$SW_JOBS_REL/$_rr_job" ] || continue
			sw_fm_read "$_rr_dir/slices/S$_rr_n.md"
			[ "$(sw_fm_get status)" = planned ] || continue
			[ -z "$(sw_job_unmet "$_rr_job" "$_rr_dir/slices/S$_rr_n.md")" ] || continue
			printf '%s\n' "$_rr_job"
		done
	done
	return 0
}

# sw_run_next: prints what the orchestrator does next, one line per thing:
# `resume <job> <state>` for every active job that is not queued, `start <job>`
# for as many ready slices as there is room for (crossing neither a job that is
# not final nor one another), `drain` (the queue is not empty and nobody
# drains it) or `merging: <jobs>`, `waiting: <jobs>`, or `none`. A halted run
# or an exceeded limit prints `stop: <why>` alone and returns 1.
sw_run_next() {
	sw_run_open || { printf 'run: no open run (./softwary run start)\n'; return 2; }
	sw_loop_load || { printf '%s' "$SW_LOOP_ERRORS"; return 2; }
	if sw_run_halted; then
		printf 'stop: %s\n' "$(sw_run_get halted)"
		return 1
	fi
	_rn_over=$(sw_run_over)
	if [ -n "$_rn_over" ]; then
		printf 'stop: run limit (%s)\n' "$_rn_over"
		return 1
	fi
	_rn_out=
	_rn_act=$(sw_job_active)
	for _rn_j in $_rn_act; do
		_rn_s=$(sw_job_get "$_rn_j" state)
		[ "$_rn_s" != queued ] || continue
		_rn_out="${_rn_out}resume $_rn_j $_rn_s
"
	done
	_rn_room=$(($(sw_loop_get concurrency) - $(printf '%s' "$_rn_act" | grep -c .)))
	_rn_sel=
	for _rn_j in $(sw_run_ready); do
		[ "$_rn_room" -gt 0 ] || break
		# shellcheck disable=SC2086 # the selected jobs are a list of words
		[ -z "$(sw_admit_overlap "$_rn_j" $_rn_sel)" ] || continue
		_rn_out="${_rn_out}start $_rn_j
"
		_rn_sel="$_rn_sel $_rn_j"
		_rn_room=$((_rn_room - 1))
	done
	_rn_q=$(sw_queue_list | paste -sd' ' -)
	if [ -n "$_rn_q" ]; then
		if sw_lock_stale merge; then
			_rn_out="${_rn_out}drain
"
		else
			_rn_out="${_rn_out}merging: $_rn_q
"
		fi
	fi
	_rn_wait=$(sw_job_waiting)
	if [ -n "$_rn_wait" ]; then
		_rn_out="${_rn_out}waiting: $(printf '%s\n' "$_rn_wait" | paste -sd' ' -)
"
	fi
	if [ -n "$_rn_out" ]; then
		printf '%s' "$_rn_out"
	else
		printf 'none\n'
	fi
}

# sw_run_stop: closes the run.
sw_run_stop() {
	sw_run_open || { printf 'run: no open run\n'; return 2; }
	sw_state_locked sw_run_stop_locked
}

sw_run_stop_locked() {
	sw_kvf_put "$SW_STATE_ROOT/$SW_RUN_REL" stopped "$(date +%s)" || return 2
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
