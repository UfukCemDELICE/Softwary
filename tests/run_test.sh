#!/bin/sh
# Tests for ./softwary run start|next|stop (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

RUN_REL=.softwary/state/run
JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log

# plan_repo: approved product and blueprint, the sample plan, an origin.
plan_repo() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_plan
	add_origin
}

# put_job JOB STATE: a job file in STATE.
put_job() {
	mkdir -p "$REPO/$JOBS_REL/$1"
	printf 'state=%s\nround=1\nstarted=%s\ntokens=0\n' "$2" "$(date +%s)" >"$REPO/$JOBS_REL/$1/job"
}

# refuse_start CODE TEXT: `run start` exits CODE with TEXT and opens no run.
refuse_start() {
	sw run start
	assert_eq "$RC" "$1" "exit code: $2"
	assert_contains "$OUT" "$2"
	[ ! -e "$REPO/$RUN_REL" ] || fail "a run was opened despite: $2"
}

# AC-V2-13: every condition of `run start` has its own refusal.
test_ac_v2_13_start_refusals() {
	plan_repo
	printf '\n' >>"$REPO/product/PRODUCT.md"
	commit_all "product edited"
	refuse_start 1 "product: approval is stale"
	git -C "$REPO" reset -q --hard HEAD~1
	sed 's/ Covers EX-F1-01\.//' "$REPO/specs/001-login/spec.md" >"$T/s" && cp "$T/s" "$REPO/specs/001-login/spec.md"
	commit_all "unlinked criterion"
	refuse_start 1 "AC-001-01: no example link"
	git -C "$REPO" reset -q --hard HEAD~1
	loop_set max_rounds 0
	refuse_start 2 "loop.conf:1: max_rounds"
	loop_conf
	file_set "$REPO/.softwary/config/models.conf" reviewer sonnet
	refuse_start 2 "must not use the same model as implementer"
	git -C "$REPO" checkout -q -- .
	touch "$REPO/junk"
	refuse_start 2 "working tree is not clean"
	rm "$REPO/junk"
	git -C "$REPO" checkout -q -b other
	refuse_start 2 "not on the integration branch main"
}

# AC-V2-13: start opens the run; a second start resumes it without resetting the clock.
test_ac_v2_13_start_and_resume() {
	plan_repo
	sw run start
	assert_eq "$RC" 0 "exit code"
	assert_match "$REPO/$RUN_REL" "^started=[0-9]+$"
	assert_eq "$(tail -n 1 "$REPO/$EVENTS_REL" | jq -r .event)" run_start "event"
	sed 's/^started=.*/started=1000000000/' "$REPO/$RUN_REL" >"$T/r" && mv "$T/r" "$REPO/$RUN_REL"
	sw run start
	assert_eq "$RC" 0 "second exit code"
	assert_match "$OUT" "^run: resuming \(started "
	assert_eq "$(sed -n 's/^started=//p' "$REPO/$RUN_REL")" 1000000000 "started"
	assert_eq "$(grep -c run_start "$REPO/$EVENTS_REL")" 1 "run_start events"
}

# AC-V2-13: next picks the unfinished job, then the next ready slice in order,
# never a slice that has a job; it waits on escalated jobs and ends with none.
test_ac_v2_13_next_order() {
	plan_repo
	sw run start
	sw run next
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(cat "$OUT")" "start 001-S1" "first slice"
	put_job 001-S1 gating
	sw run next
	assert_eq "$(cat "$OUT")" "resume 001-S1 gating" "unfinished job"
	put_job 001-S1 escalated
	sw run next
	assert_eq "$(cat "$OUT")" "waiting: 001-S1" "escalated job"
	put_job 001-S1 merged
	fm_set "$REPO/specs/001-login/slices/S1.md" status "done"
	sw run next
	assert_eq "$(cat "$OUT")" "start 001-S2" "dependent slice"
	put_job 001-S2 abandoned
	sw run next
	assert_eq "$(cat "$OUT")" "none" "an abandoned slice is not restarted"
	fm_set "$REPO/specs/001-login/slices/S2.md" status "done"
	sw run next
	assert_eq "$(cat "$OUT")" "none" "a draft spec is not started"
	fm_set "$REPO/specs/002-tasks/spec.md" status approved
	sw run next
	assert_eq "$(cat "$OUT")" "start 002-S1" "slice of the next spec"
}

# AC-V4-08: run next writes one line for everything there is to do: a resume
# for every active job that is not queued, a start for as many ready slices as
# there is room for that cross neither a job that is not final nor each other,
# drain or merging for the queue, waiting for the escalated; none otherwise.
test_ac_v4_08_run_next_lines() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_parallel_plan
	loop_set concurrency 3
	add_origin
	sw run start
	sw run next
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(cat "$OUT")" "start 001-S1
start 001-S2" "two slices that cross nothing, not the one that crosses S1"
	put_job 001-S1 gating
	put_job 001-S2 implementing
	sw run next
	assert_eq "$(cat "$OUT")" "resume 001-S1 gating
resume 001-S2 implementing" "two resumes, S3 crosses S1 and there is one place"
	put_job 001-S1 merged
	sw run next
	assert_eq "$(cat "$OUT")" "resume 001-S2 implementing
start 001-S3" "room for S3 once S1 is final"
	put_job 001-S3 escalated
	sw run next
	assert_eq "$(cat "$OUT")" "resume 001-S2 implementing
waiting: 001-S3" "an escalated job waits"
	loop_set concurrency 1
	put_job 001-S3 abandoned
	sw run next
	assert_eq "$(cat "$OUT")" "resume 001-S2 implementing" "no room: no start"
	put_job 001-S2 merged
	sw run next
	assert_eq "$(cat "$OUT")" none "nothing left"
}

# AC-V4-08: a queue nobody drains is `drain`, one a live process drains is
# `merging: <jobs>`; queued jobs are not resumed.
test_ac_v4_08_run_next_queue() {
	plan_repo
	sw run start
	put_job 001-S1 queued
	mkdir -p "$REPO/.softwary/state"
	printf '001-S1\n' >"$REPO/.softwary/state/queue"
	sw run next
	assert_eq "$(cat "$OUT")" "drain" "no lock"
	mkdir -p "$REPO/.softwary/state/locks/merge"
	printf 'pid=%s host=%s time=%s\n' "$(sh -c 'echo $$')" "$(uname -n)" "$(date +%s)" >"$REPO/.softwary/state/locks/merge/owner"
	sw run next
	assert_eq "$(cat "$OUT")" "drain" "a lock of a dead owner"
	sleep 30 &
	holder=$!
	printf 'pid=%s host=%s time=%s\n' "$holder" "$(uname -n)" "$(date +%s)" >"$REPO/.softwary/state/locks/merge/owner"
	sw run next
	kill "$holder"
	assert_eq "$(cat "$OUT")" "merging: 001-S1" "a live drainer"
}

# AC-V4-08: a halted run or an exceeded limit gives `stop: <why>` alone and 1.
test_ac_v4_08_run_next_stop() {
	plan_repo
	sw run start
	printf 'halted=integration red after 001-S1 (revert PR #4)\n' >>"$REPO/$RUN_REL"
	put_job 001-S2 implementing
	sw run next
	assert_eq "$RC" 1 "exit code"
	assert_eq "$(cat "$OUT")" "stop: integration red after 001-S1 (revert PR #4)" "output"
}

# AC-V2-13: next stops the run when a run limit is exceeded; without a run it exits 2.
test_ac_v2_13_next_stop_on_run_limit() {
	plan_repo
	sw run next
	assert_eq "$RC" 2 "exit code without a run"
	sw run start
	printf 'started=%s\ntokens=0\n' "$(($(date +%s) - 241 * 60))" >"$REPO/$RUN_REL"
	sw run next
	assert_eq "$RC" 1 "exit code over the minutes"
	assert_eq "$(cat "$OUT")" "stop: run limit (max_run_minutes)" "output"
	loop_set max_run_tokens 100
	printf 'started=%s\ntokens=101\n' "$(date +%s)" >"$REPO/$RUN_REL"
	sw run next
	assert_eq "$RC" 1 "exit code over the tokens"
	assert_eq "$(cat "$OUT")" "stop: run limit (max_run_tokens)" "output"
}

# AC-V2-13: stop closes the run; a later start opens a new one.
test_ac_v2_13_stop() {
	plan_repo
	sw run stop
	assert_eq "$RC" 2 "stop without a run"
	sw run start
	sw run stop
	assert_eq "$RC" 0 "exit code"
	assert_match "$REPO/$RUN_REL" "^stopped=[0-9]+$"
	assert_eq "$(tail -n 1 "$REPO/$EVENTS_REL" | jq -r .event)" run_stop "event"
	sw run next
	assert_eq "$RC" 2 "next after stop"
	sed 's/^started=.*/started=1000000000/' "$REPO/$RUN_REL" >"$T/r" && mv "$T/r" "$REPO/$RUN_REL"
	sw run start
	assert_eq "$RC" 0 "start after stop"
	assert_no_match "$REPO/$RUN_REL" "^stopped="
	assert_no_match "$REPO/$RUN_REL" "^started=1000000000$"
}

# AC-V2-13: usage errors exit 2.
test_ac_v2_13_usage() {
	plan_repo
	sw run
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "usage: ./softwary run start|next|stop"
}

run_tests "$0"
