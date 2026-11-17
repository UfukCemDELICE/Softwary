#!/bin/sh
# Tests for the state root and the locks (V4).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log
RUN_REL=.softwary/state/run
LOCKS=.softwary/state/locks

# put_job STATE: the job file of $JOB in the repo's state.
put_job() {
	mkdir -p "$REPO/$JOBS_REL/$JOB"
	printf 'state=%s\nround=1\nstarted=%s\ntokens=0\nbranch=softwary/%s\n' "$1" "$(date +%s)" "$JOB" \
		>"$REPO/$JOBS_REL/$JOB/job"
}

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

# sw_in DIR ARGS...: ./softwary in DIR (a worktree, say).
sw_in() {
	_dir=$1
	shift
	RC=0
	(cd "$_dir" && ./softwary "$@") >"$OUT" 2>&1 || RC=$?
}

# dead_pid: the pid of a process that has exited.
dead_pid() {
	sh -c 'exit 0' &
	_dp=$!
	wait "$_dp"
	printf '%s\n' "$_dp"
}

# hold_lock NAME: a lock owned by a live process (sleep); sets HOLDER to its pid.
hold_lock() {
	sleep 60 &
	HOLDER=$!
	mkdir -p "$REPO/$LOCKS/$1"
	printf 'pid=%s host=%s time=%s\n' "$HOLDER" "$(uname -n)" "$(date +%s)" >"$REPO/$LOCKS/$1/owner"
}

# age_dir DIR: makes DIR two minutes old.
age_dir() {
	touch -d '2 minutes ago' "$1" 2>/dev/null || touch -t "$(date -v-2M +%Y%m%d%H%M.%S)" "$1"
}

# no_locks: no lock directory is left.
no_locks() {
	[ -z "$(ls "$REPO/$LOCKS" 2>/dev/null)" ] || fail "a lock was left behind: $(ls "$REPO/$LOCKS")"
}

# AC-V4-01: from a linked worktree the state is the main checkout's: it is
# read from there and written there; the worktree gets no state of its own.
test_ac_v4_01_state_root_from_worktree() {
	setup_repo
	conf_all true
	add_origin
	git -C "$REPO" worktree add -q -b wt "$T/wt" || fail "git worktree add failed"
	put_job gating
	open_run
	sw_in "$T/wt" job show $JOB
	assert_eq "$RC" 0 "job show from the worktree"
	assert_match "$OUT" "^state=gating$"
	sw_in "$T/wt" job tokens $JOB 5
	assert_eq "$RC" 0 "job tokens from the worktree"
	assert_eq "$(job_get tokens)" 5 "tokens in the main checkout"
	assert_eq "$(sed -n 's/^tokens=//p' "$REPO/$RUN_REL")" 5 "run tokens in the main checkout"
	sw_in "$T/wt" status
	assert_match "$OUT" "^job $JOB +gating"
	[ ! -e "$T/wt/.softwary/state/jobs" ] || fail "the worktree got a jobs directory"
	[ ! -e "$T/wt/.softwary/state/events.log" ] || fail "the worktree got an event log"
	[ ! -e "$T/wt/.softwary/state/run" ] || fail "the worktree got a run file"
	assert_eq "$(jq -r .event "$REPO/$EVENTS_REL" | paste -sd' ' -)" tokens "events in the main checkout"
}

# AC-V4-01: N commands at the same time lose nothing: the totals are exact and
# the event log has N whole lines.
test_ac_v4_01_parallel_tokens() {
	setup_repo
	conf_all true
	put_job implementing
	open_run
	_i=0
	while [ "$_i" -lt 20 ]; do
		(cd "$REPO" && ./softwary job tokens $JOB 1 >/dev/null 2>&1) &
		_i=$((_i + 1))
	done
	wait
	assert_eq "$(job_get tokens)" 20 "job tokens"
	assert_eq "$(sed -n 's/^tokens=//p' "$REPO/$RUN_REL")" 20 "run tokens"
	assert_eq "$(grep -c . "$REPO/$EVENTS_REL")" 20 "event lines"
	jq -e . "$REPO/$EVENTS_REL" >/dev/null || fail "an event line is not JSON"
	no_locks
}

# AC-V4-01: a state file is written only while the state lock is held: with
# the lock held by another process, every command that writes one gives up
# with 2, names the owner and changes nothing.
test_ac_v4_01_writes_under_lock() {
	setup_repo
	conf_all true
	put_job implementing
	open_run
	hold_lock state
	trap 'kill "$HOLDER" 2>/dev/null' EXIT
	export SW_LOCK_TIMEOUT=1
	snapshot >"$T/before"
	for cmd in "job tokens $JOB 1" "job event $JOB implemented" "job escalate $JOB why" "run stop"; do
		# shellcheck disable=SC2086 # the command is a list of words
		sw $cmd
		assert_eq "$RC" 2 "exit code of: $cmd"
		assert_contains "$OUT" "state is locked by pid $HOLDER on $(uname -n)"
	done
	snapshot >"$T/after"
	cmp -s "$T/before" "$T/after" || fail "a command wrote state without the lock: $(changed_paths "$T/before" "$T/after")"
}

# AC-V4-01: every line of the package that writes a state file (a job file,
# the run file, the event log, the queue, a file in a job's directory) is in a
# function that only runs under the state lock: each of those is called only
# as `sw_state_locked <function>`. The job's logs (ci.log, merge-gh.log) are
# written by the one process that owns that step of the job; they are listed.
test_ac_v4_01_state_writers_are_locked() {
	found=$(cd "$PKG_ROOT/src/lib" && awk '
		/^sw_[a-z0-9_]*\(\) \{/ { fn = $1; sub(/\(\)$/, "", fn) }
		/>>?[ ]*"?\$SW_STATE_ROOT\/\$SW_(JOBS|RUN|EVENTS)_REL/ { print FILENAME ":" fn }
	' ./*.sh | sed 's|^\./||' | sort -u)
	want="events.sh:sw_event_write
job.sh:sw_job_apply_locked
job.sh:sw_job_pr_green
job.sh:sw_job_text_locked
merge.sh:sw_merge_one
merge.sh:sw_merge_record_locked"
	assert_eq "$found" "$want" "functions that write under the state directory"
	for fn in sw_event_write sw_job_apply_locked sw_job_text_locked sw_merge_record_locked sw_kvf_put_raw sw_kvf_del_raw sw_queue_write; do
		bad=$(cat "$PKG_ROOT"/src/lib/*.sh | grep -E "(^|[^a-z_])$fn( |\$)" | grep -vE "^$fn\(\)|^#|sw_state_locked $fn")
		[ -z "$bad" ] || fail "$fn is called outside the state lock: $bad"
	done
}

# AC-V4-02: a lock is a directory with an owner; one whose owner is dead is
# broken by the first process that wants it and `lock_broken` is logged; one
# that never got an owner is broken after a minute; a live process's lock and
# another machine's lock are kept, and the command gives up with 2.
test_ac_v4_02_stale_lock_broken() {
	setup_repo
	conf_all true
	put_job implementing
	open_run
	lock=$REPO/$LOCKS/state
	mkdir -p "$lock"
	printf 'pid=%s host=%s time=%s\n' "$(dead_pid)" "$(uname -n)" "$(date +%s)" >"$lock/owner"
	sw job tokens $JOB 1
	assert_eq "$RC" 0 "exit code over a dead owner's lock"
	assert_match "$REPO/$EVENTS_REL" '"event":"lock_broken"'
	assert_match "$REPO/$EVENTS_REL" 'state \(was: pid=[0-9]+ host='
	no_locks

	mkdir -p "$lock"
	age_dir "$lock"
	sw job tokens $JOB 1
	assert_eq "$RC" 0 "exit code over an old lock with no owner"
	assert_eq "$(grep -c lock_broken "$REPO/$EVENTS_REL")" 2 "lock_broken events"
	no_locks

	export SW_LOCK_TIMEOUT=1
	mkdir -p "$lock"
	sw job tokens $JOB 1
	assert_eq "$RC" 2 "exit code over a young lock with no owner"
	assert_contains "$OUT" "state is locked (no owner recorded yet)"
	[ -d "$lock" ] || fail "a young lock without an owner was broken"
	rm -rf "$lock"

	hold_lock state
	trap 'kill "$HOLDER" 2>/dev/null' EXIT
	sw job tokens $JOB 1
	assert_eq "$RC" 2 "exit code over a live owner's lock"
	assert_contains "$OUT" "state is locked by pid $HOLDER on $(uname -n) since "
	[ -d "$lock" ] || fail "a live process's lock was broken"
	kill "$HOLDER"
	rm -rf "$lock"

	mkdir -p "$lock"
	printf 'pid=%s host=%s time=%s\n' "$(dead_pid)" some-other-machine "$(date +%s)" >"$lock/owner"
	sw job tokens $JOB 1
	assert_eq "$RC" 2 "exit code over another machine's lock"
	assert_contains "$OUT" "on some-other-machine"
	assert_contains "$OUT" "not broken"
	[ -d "$lock" ] || fail "another machine's lock was broken"
	assert_eq "$(grep -c lock_broken "$REPO/$EVENTS_REL")" 2 "no further lock_broken"
}

# AC-V4-02: the owner file says pid, host and time; the lock is released on
# success, on a refusal and on a usage error.
test_ac_v4_02_owner_and_release() {
	setup_repo
	conf_all true
	put_job implementing
	open_run
	sw job tokens $JOB 1
	assert_eq "$RC" 0 "exit code"
	no_locks
	sw job event $JOB gate_pass
	assert_eq "$RC" 1 "exit code with no such transition"
	no_locks
	sw job tokens 009-S9 1
	assert_eq "$RC" 2 "exit code for an unknown job"
	no_locks
	sw job tokens $JOB x
	assert_eq "$RC" 2 "exit code for a bad count"
	no_locks
	cat >"$T/own.sh" <<'EOF'
SOFTWARY_ROOT=$1 SW_STATE_ROOT=$1 SOFTWARY_HOME=$2
. "$2/lib/lock.sh"
sw_lock_acquire state 5 || exit 2
cat "$1/.softwary/state/locks/state/owner"
sw_lock_release state
EOF
	sh "$T/own.sh" "$REPO" "$REPO/.softwary" >"$OUT" 2>&1
	assert_match "$OUT" "^pid=[0-9]+ host=.+ time=[0-9]+$"
	no_locks
}

# AC-V4-02: a signal releases the lock the process holds (the exit trap).
test_ac_v4_02_signal_releases_the_lock() {
	setup_repo
	conf_all true
	cat >"$T/hold.sh" <<'EOF'
SOFTWARY_ROOT=$1 SW_STATE_ROOT=$1 SOFTWARY_HOME=$2
. "$2/lib/lock.sh"
. "$2/lib/events.sh"
sw_lock_install_traps
CHILDFILE=$3
hold() {
	sleep 30 &
	echo $! >"$CHILDFILE"
	wait $!
}
sw_state_locked hold
EOF
	sh "$T/hold.sh" "$REPO" "$REPO/.softwary" "$T/child" &
	holder=$!
	_i=0
	while [ ! -f "$REPO/$LOCKS/state/owner" ] && [ "$_i" -lt 100 ]; do
		sleep 0.1
		_i=$((_i + 1))
	done
	[ -f "$REPO/$LOCKS/state/owner" ] || fail "the lock was never taken"
	kill -TERM "$holder"
	wait "$holder" || :
	kill "$(cat "$T/child")" 2>/dev/null || :
	no_locks
}

run_tests "$0"
