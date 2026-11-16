# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: the merge queue, its drainer and the red integration branch.
# Sourced by bin/softwary. POSIX sh.
#
# .softwary/state/queue lists the queued jobs, one per line, in the order they
# were added. Whoever holds the `merge` lock is the drainer: it merges the head
# of the queue (merge.sh), one job at a time, and gives the lock up in the
# same state-lock section in which it sees the queue empty. After every merge
# the integration branch must still be green; if it is not, the last merge is
# reverted by a PR and the run is halted (`halted=<reason>` in the run file).

SW_QUEUE_REL=.softwary/state/queue
SW_INTEGRATION_LOG=.softwary/state/logs/integration.log

sw_queue_file() {
	printf '%s/%s' "$SW_STATE_ROOT" "$SW_QUEUE_REL"
}

# sw_queue_list: the queued jobs, one per line.
sw_queue_list() {
	cat "$(sw_queue_file)" 2>/dev/null || :
}

# sw_queue_has JOB: true when JOB is in the queue.
sw_queue_has() {
	sw_queue_list | grep -Fqx -e "$1"
}

# sw_queue_pos JOB: the position of JOB in the queue (1 is the head).
sw_queue_pos() {
	sw_queue_list | grep -Fnx -e "$1" | head -n 1 | cut -d: -f1
}

# sw_queue_add JOB / sw_queue_del JOB: change the queue under the state lock.
sw_queue_add() {
	sw_state_locked sw_queue_write add "$1"
}

sw_queue_del() {
	sw_state_locked sw_queue_write del "$1"
}

sw_queue_write() {
	_qw_f=$(sw_queue_file)
	mkdir -p "$(dirname "$_qw_f")" || return 2
	{
		sw_queue_list | grep -vFx -e "$2" || :
		[ "$1" != add ] || printf '%s\n' "$2"
	} >"$_qw_f.tmp" && mv "$_qw_f.tmp" "$_qw_f"
}

# sw_queue_next: one state section of the drainer (the merge lock is held):
# SW_QUEUE_NEXT is `head` (SW_QUEUE_HEAD is the job to merge), `empty` or
# `halted`; for the last two the merge lock is released here, in the same
# section that saw the queue empty. Entries a crash left behind are mended: an
# `approving` job is queued, one in any other state is dropped.
sw_queue_next() {
	if sw_run_halted; then
		sw_lock_release merge
		SW_QUEUE_NEXT=halted
		return 0
	fi
	while :; do
		SW_QUEUE_HEAD=$(sw_queue_list | head -n 1)
		if [ -z "$SW_QUEUE_HEAD" ]; then
			sw_lock_release merge
			SW_QUEUE_NEXT=empty
			return 0
		fi
		case $(sw_job_get "$SW_QUEUE_HEAD" state) in
		queued) break ;;
		approving) sw_job_apply "$SW_QUEUE_HEAD" enqueue >/dev/null || sw_queue_del "$SW_QUEUE_HEAD" ;;
		*) sw_queue_del "$SW_QUEUE_HEAD" ;;
		esac
	done
	SW_QUEUE_NEXT="head"
}

# sw_queue_drain [JOB]: the merge lock is held; merges the queue head after
# head until the queue is empty or the run is halted, then the lock is gone.
# SW_DRAIN_ANY is 1 when a job was refused, SW_DRAIN_OWN when JOB was. 2 for
# an error (the lock is given up too).
sw_queue_drain() {
	_qd_own=${1-}
	SW_DRAIN_ANY=0
	SW_DRAIN_OWN=0
	while :; do
		sw_state_locked sw_queue_next || { sw_lock_release merge; return 2; }
		[ "$SW_QUEUE_NEXT" = head ] || return 0
		_qd_job=$SW_QUEUE_HEAD
		_qd_rc=0
		sw_merge_one "$_qd_job" || _qd_rc=$?
		case $_qd_rc in
		0) ;;
		1)
			SW_DRAIN_ANY=1
			[ "$_qd_job" != "$_qd_own" ] || SW_DRAIN_OWN=1
			;;
		*)
			sw_lock_release merge
			return 2
			;;
		esac
	done
}

# sw_queue_start: the first section of `queue drain`: takes the merge lock
# (breaking a dead drainer's) unless the run is halted or someone drains.
# SW_QUEUE_START is halted, busy, empty or drainer.
sw_queue_start() {
	if sw_run_halted; then
		printf 'queue: run is halted: %s\n' "$(sw_run_get halted)"
		SW_QUEUE_START=halted
		return 0
	fi
	_qs_rc=0
	sw_lock_try merge || _qs_rc=$?
	case $_qs_rc in
	0) ;;
	1)
		sw_lock_probe merge
		printf 'queue: draining by pid %s\n' "$(sw_lock_field "$SW_LOCK_OWNER" pid)"
		SW_QUEUE_START=busy
		return 0
		;;
	*) return 2 ;;
	esac
	if [ -z "$(sw_queue_list)" ]; then
		sw_lock_release merge
		printf 'queue: empty\n'
		SW_QUEUE_START=empty
		return 0
	fi
	SW_QUEUE_START=drainer
}

# sw_queue_show: the queue and the drainer.
sw_queue_show() {
	_qh_q=$(sw_queue_list | paste -sd' ' -)
	printf 'queue: %s\n' "${_qh_q:-empty}"
	sw_lock_probe merge
	case $SW_LOCK_STATUS in
	live | foreign)
		printf 'drainer: pid %s on %s since %s\n' "$(sw_lock_field "$SW_LOCK_OWNER" pid)" "$(sw_lock_field "$SW_LOCK_OWNER" host)" \
			"$(sw_run_time "$(sw_lock_field "$SW_LOCK_OWNER" time)")"
		;;
	young) printf 'drainer: starting\n' ;;
	*) printf 'drainer: none\n' ;;
	esac
}

sw_queue_usage() {
	printf 'usage: ./softwary queue [drain]\n' >&2
}

# sw_queue [drain]
sw_queue() {
	case ${1:-} in
	'')
		sw_queue_show
		;;
	drain)
		[ $# -eq 1 ] || { sw_queue_usage; return 2; }
		_qc_rc=0
		sw_state_locked sw_queue_start || return 2
		case $SW_QUEUE_START in
		halted) return 1 ;;
		busy | empty) return 0 ;;
		esac
		sw_queue_drain || return $?
		[ "$SW_DRAIN_ANY" -eq 0 ] || _qc_rc=1
		return "$_qc_rc"
		;;
	*)
		sw_queue_usage
		return 2
		;;
	esac
}

# --- the integration branch after a merge -------------------------------------

# sw_queue_verify BASE: the tip of the integration branch is checked in the
# worktree .softwary/worktrees/_integration with the main checkout's scripts:
# bootstrap, then the full verify. The output is in integration.log. 0 green.
sw_queue_verify() {
	_qv_log=$SW_STATE_ROOT/$SW_INTEGRATION_LOG
	mkdir -p "$(dirname "$_qv_log")" || return 2
	: >"$_qv_log"
	sw_wt_integration "$1" || { printf 'could not set up the integration worktree\n' >>"$_qv_log"; return 2; }
	_qv_cmd=$(sw_wt_bootstrap_cmd) || { printf '%s\n' "$_qv_cmd" >>"$_qv_log"; return 2; }
	if [ -n "$_qv_cmd" ]; then
		(cd "$(sw_wt_path _integration)" && sh -c "$_qv_cmd") >>"$_qv_log" 2>&1 || return 1
	fi
	sw_wt_softwary _integration verify --base HEAD >>"$_qv_log" 2>&1
}

# sw_queue_halt JOB REASON: the run is halted (the run file and the log).
sw_queue_halt() {
	sw_state_locked sw_queue_halt_locked "$1" "$2"
}

sw_queue_halt_locked() {
	sw_kvf_put "$SW_STATE_ROOT/$SW_RUN_REL" halted "$2"
	sw_event "$1" integration_red - - "$2"
}

# sw_queue_revert JOB BASE: opens softwary/revert-<job>, which reverts the tip
# of the integration branch, and its PR. Prints the PR number, or nothing.
sw_queue_revert() {
	_qr_wt=$(sw_wt_path _integration)
	_qr_br=softwary/revert-$1
	git -C "$_qr_wt" checkout -q -B "$_qr_br" "origin/$2" >/dev/null 2>&1 || return 1
	git -C "$_qr_wt" revert --no-edit "origin/$2" >/dev/null 2>&1 || { git -C "$_qr_wt" revert --abort >/dev/null 2>&1; return 1; }
	git -C "$_qr_wt" push -q --no-verify -f origin "$_qr_br" >/dev/null 2>&1 || return 1
	_qr_out=$(gh pr create --base "$2" --head "$_qr_br" --title "Revert $1: $2 is red" \
		--body "The integration branch failed verify after $1 was merged (see $SW_INTEGRATION_LOG). This reverts its tip." 2>&1) || return 1
	_qr_n=$(printf '%s\n' "$_qr_out" | tail -n 1)
	_qr_n=${_qr_n##*/}
	sw_positive_int "$_qr_n" || return 1
	printf '%s\n' "$_qr_n"
}

# sw_queue_integration JOB SHA: after the merge of SHA. When the tip of the
# integration branch has the tree of SHA, nothing more is checked; otherwise
# the tip goes through the full verify, and a red tip is reverted and halts
# the run. 0 (also when the run was halted), 2 when the check cannot run.
sw_queue_integration() {
	_qi_job=$1
	_qi_sha=$2
	[ -n "$_qi_sha" ] || return 0
	_qi_base=$(sw_job_integration) || return 2
	if sw_wt_origin; then
		git -C "$SW_STATE_ROOT" fetch -q origin "$_qi_base" >/dev/null 2>&1 || { printf 'merge: could not fetch origin/%s to check it\n' "$_qi_base"; return 0; }
	fi
	_qi_ref=$(sw_wt_start_ref "$_qi_base")
	_qi_tip=$(git -C "$SW_STATE_ROOT" rev-parse "$_qi_ref^{tree}" 2>/dev/null) || return 2
	_qi_mine=$(git -C "$SW_STATE_ROOT" rev-parse "$_qi_sha^{tree}" 2>/dev/null) || _qi_mine=
	[ "$_qi_tip" != "$_qi_mine" ] || return 0
	sw_run_halted && return 0
	_qi_rc=0
	sw_queue_verify "$_qi_base" || _qi_rc=$?
	[ "$_qi_rc" -ne 0 ] || return 0
	[ "$_qi_rc" -eq 1 ] || return 2
	_qi_n=$(sw_queue_revert "$_qi_job" "$_qi_base") || _qi_n=
	if [ -n "$_qi_n" ]; then
		sw_queue_halt "$_qi_job" "integration red after $_qi_job (revert PR #$_qi_n)"
	else
		sw_queue_halt "$_qi_job" "integration red after $_qi_job (no revert PR could be opened)"
	fi
	printf 'merge: %s is red after %s; the run is halted (%s)\n' "$_qi_base" "$_qi_job" "$(sw_run_get halted)"
}
