#!/bin/sh
# Tests for `job start`, `job gate`, `job tokens` and the limits (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log

# put_job STATE ROUND [STARTED]: writes the job file of $JOB.
put_job() {
	mkdir -p "$REPO/$JOBS_REL/$JOB"
	printf 'state=%s\nround=%s\nstarted=%s\ntokens=0\nbranch=softwary/%s\n' "$1" "$2" "${3:-$(date +%s)}" "$JOB" \
		>"$REPO/$JOBS_REL/$JOB/job"
}

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

# ago MINUTES: a time that many minutes in the past, as `date +%s` prints it.
ago() {
	echo $(($(date +%s) - $1 * 60))
}

last_event() {
	tail -n 1 "$REPO/$EVENTS_REL"
}

# loop_repo: approved product, blueprint and plan, an origin, an open run.
loop_repo() {
	setup_repo
	conf_all true
	[ -z "${1-}" ] || conf_set test "$1"
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_plan
	add_origin
	open_run
}

# refuse_start JOB TEXT: `job start` refuses with TEXT and leaves no trace.
refuse_start() {
	sw job start "$1"
	assert_eq "$RC" 1 "exit code: $2"
	assert_contains "$OUT" "$2"
	! git -C "$REPO" rev-parse -q --verify "refs/heads/softwary/$1" >/dev/null || fail "branch opened despite: $2"
	[ ! -e "$REPO/$JOBS_REL/$1" ] || fail "job directory made despite: $2"
}

# AC-V2-08: every start condition has its own refusal; none opens a branch.
test_ac_v2_08_start_refusals() {
	loop_repo
	rm "$REPO/.softwary/state/run"
	refuse_start $JOB "no open run"
	open_run
	mkdir -p "$REPO/$JOBS_REL/002-S1"
	printf 'state=ci\nround=1\n' >"$REPO/$JOBS_REL/002-S1/job"
	refuse_start $JOB "another job is active: 002-S1"
	rm -r "$REPO/$JOBS_REL/002-S1"
	git -C "$REPO" checkout -q -b other
	refuse_start $JOB "not on the integration branch main"
	git -C "$REPO" checkout -q main
	touch "$REPO/junk"
	refuse_start $JOB "working tree is not clean"
	rm "$REPO/junk"
	fm_set "$REPO/specs/001-login/slices/S1.md" status in-progress
	commit_all "slice started"
	refuse_start $JOB "slice is not planned"
	git -C "$REPO" reset -q --hard HEAD~1
	refuse_start 002-S1 "spec 002 is not approved"
	refuse_start 001-S2 "dependency 001-S1 is not done"
	printf '\n' >>"$REPO/product/PRODUCT.md"
	commit_all "product edited"
	refuse_start $JOB "product approval is stale"
	git -C "$REPO" reset -q --hard HEAD~1
	sw job start 009-S9
	assert_eq "$RC" 2 "exit code for an unknown slice"
	[ ! -e "$REPO/$EVENTS_REL" ] || [ "$(grep -c . "$REPO/$EVENTS_REL")" -eq 2 ] || fail "start refusals logged events"
}

# AC-V2-08: start opens the branch, takes the job into round 1, brings in the
# latest integration branch; a job waiting for a human does not block it.
test_ac_v2_08_start_opens_branch() {
	loop_repo
	git clone -q "$T/origin.git" "$T/other"
	git -C "$T/other" config user.name o
	git -C "$T/other" config user.email o@example.com
	printf 'x\n' >"$T/other/news.txt"
	git -C "$T/other" add news.txt
	git -C "$T/other" commit -q -m news
	git -C "$T/other" push -q --no-verify origin main
	mkdir -p "$REPO/$JOBS_REL/002-S1"
	printf 'state=escalated\nround=2\n' >"$REPO/$JOBS_REL/002-S1/job"
	sw job start $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(git -C "$REPO" branch --show-current)" softwary/$JOB "branch"
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(job_get round)" 1 "round"
	assert_eq "$(job_get branch)" softwary/$JOB "branch in the job file"
	[ -f "$REPO/news.txt" ] || fail "origin's news were not pulled"
	assert_eq "$(last_event | jq -r '[.job, .event, .from, .to] | join(" ")')" "$JOB start ready implementing" "event"
	sw job start $JOB
	assert_eq "$RC" 1 "second start"
}

# gate_repo TESTCMD: a repo with the job in `gating`, on its branch.
gate_repo() {
	loop_repo "$1"
	sw job start $JOB
	assert_eq "$RC" 0 "start"
	sw job event $JOB implemented
	assert_eq "$(job_get state)" gating "state before the gate"
}

# AC-V2-08: a passing gate is gate_pass and keeps its log.
test_ac_v2_08_gate_pass() {
	gate_repo true
	sw job gate $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" pr "state"
	[ -s "$REPO/$JOBS_REL/$JOB/gate-1.log" ] || fail "gate log missing"
	assert_eq "$(last_event | jq -r .event)" gate_pass "event"
}

# AC-V2-08: a gate that fails twice is gate_fail and opens round 2.
test_ac_v2_08_gate_fail() {
	gate_repo false
	sw job gate $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(job_get round)" 2 "round"
	assert_eq "$(last_event | jq -r .event)" gate_fail "event"
	assert_contains "$REPO/$JOBS_REL/$JOB/gate-1.log" "FAIL"
}

# AC-V2-08: a gate that fails once and passes on retry is flaky: the human decides.
test_ac_v2_08_gate_flaky() {
	# shellcheck disable=SC2016 # the script is written as is, to expand when it runs
	printf 'c=%s/count\nn=$(cat "$c" 2>/dev/null || echo 0)\necho $((n + 1)) >"$c"\n[ "$n" -ge 1 ]\n' "$T" >"$T/flaky.sh"
	gate_repo "sh $T/flaky.sh"
	sw job gate $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" escalated "state"
	assert_contains "$REPO/$JOBS_REL/$JOB/escalation" "flaky"
	assert_eq "$(last_event | jq -r .event)" escalate "event"
}

# AC-V2-08: the gate wants the job's branch, a clean tree and the gating state.
test_ac_v2_08_gate_preconditions() {
	gate_repo true
	touch "$REPO/junk"
	sw job gate $JOB
	assert_eq "$RC" 2 "exit code with a dirty tree"
	assert_eq "$(job_get state)" gating "state"
	rm "$REPO/junk"
	git -C "$REPO" checkout -q main
	sw job gate $JOB
	assert_eq "$RC" 2 "exit code on the wrong branch"
	git -C "$REPO" checkout -q softwary/$JOB
	sw job event $JOB escalate why
	sw job gate $JOB
	assert_eq "$RC" 1 "exit code in the wrong state"
	assert_contains "$OUT" "not gating"
}

# AC-V2-11: the round after max_rounds is an escalation, not a round.
test_ac_v2_11_round_limit() {
	setup_repo
	put_job gating 2
	sw job event $JOB gate_fail
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" implementing "state in round 3"
	assert_eq "$(job_get round)" 3 "round"
	sw job event $JOB implemented
	sw job event $JOB gate_fail
	assert_eq "$(job_get state)" escalated "state after the third failure"
	assert_eq "$(last_event | jq -r '[.event, .from, .to, .detail] | join("|")')" "escalate|gating|escalated|round limit 3" "event"
	assert_eq "$(cat "$REPO/$JOBS_REL/$JOB/escalation")" "round limit 3" "escalation"
}

# AC-V2-11: job and run minutes and tokens; each one escalates and names its key.
test_ac_v2_11_time_and_token_limits() {
	setup_repo
	open_run
	put_job implementing 1 "$(ago 46)"
	sw job event $JOB implemented
	assert_eq "$(job_get state)" escalated "state after the job minutes"
	assert_eq "$(last_event | jq -r .detail)" "budget: max_job_minutes 45" "job minutes detail"
	put_job implementing 1
	printf 'started=%s\ntokens=0\n' "$(ago 241)" >"$REPO/.softwary/state/run"
	sw job event $JOB implemented
	assert_eq "$(last_event | jq -r .detail)" "budget: max_run_minutes 240" "run minutes detail"
	open_run
	loop_set max_job_tokens 100
	put_job implementing 1
	sw job tokens $JOB 100
	assert_eq "$RC" 0 "tokens exit code"
	assert_eq "$(last_event | jq -r '[.event, .from, .to, .detail] | join("|")')" "tokens|implementing|implementing|100" "tokens event"
	sw job event $JOB implemented
	assert_eq "$(job_get state)" gating "state at the limit"
	sw job tokens $JOB 1
	sw job event $JOB gate_pass
	assert_eq "$(job_get state)" escalated "state over the job tokens"
	assert_eq "$(last_event | jq -r .detail)" "budget: max_job_tokens 100" "job tokens detail"
	loop_conf
	loop_set max_run_tokens 150
	open_run
	put_job implementing 1
	sw job tokens $JOB 100
	sw job tokens $JOB 51
	assert_eq "$(sed -n 's/^tokens=//p' "$REPO/.softwary/state/run")" 151 "run tokens"
	sw job event $JOB implemented
	assert_eq "$(last_event | jq -r .detail)" "budget: max_run_tokens 150" "run tokens detail"
}

# AC-V2-11: escalate, resume, abandon and human_merged work over the limits.
test_ac_v2_11_escalate_resume_unaffected_by_budget() {
	setup_repo
	open_run
	put_job implementing 1 "$(ago 500)"
	sw job event $JOB escalate "stuck"
	assert_eq "$(job_get state)" escalated "state"
	assert_eq "$(last_event | jq -r .detail)" "stuck" "the question, not a budget"
	sw job event $JOB resume
	assert_eq "$(job_get state)" implementing "state after resume over the limit"
	assert_eq "$(job_get round)" 1 "round after resume"
	[ "$(job_get started)" -gt "$(ago 1)" ] || fail "resume did not restart the job clock"
	sw job event $JOB implemented
	assert_eq "$(job_get state)" gating "the resumed job runs"
	put_job escalated 3 "$(ago 500)"
	sw job event $JOB abandon
	assert_eq "$(job_get state)" abandoned "abandon over the limit"
}

# AC-V2-11: an unusable loop.conf stops job events with 2.
test_ac_v2_11_bad_loop_conf_exits_2() {
	setup_repo
	put_job implementing 1
	loop_set max_rounds 0
	sw job event $JOB implemented
	assert_eq "$RC" 2 "exit code"
	assert_eq "$(job_get state)" implementing "state"
}

run_tests "$0"
