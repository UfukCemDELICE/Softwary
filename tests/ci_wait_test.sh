#!/bin/sh
# Tests for how `job ci` and merge read CI: bounded polling, the three results
# (green, red, undecided) and max_ci_minutes (V10).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log
LOOP_RE='^loop\.conf +FAIL \(\.softwary/config/loop\.conf'
OLD_HEAD=0000000000000000000000000000000000000000

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

last_event() {
	tail -n 1 "$REPO/$EVENTS_REL"
}

# last_detail: the event and the detail of the job's last event.
last_detail() {
	last_event | jq -r '[.event, .detail] | join("|")'
}

# job_in STATE: moves the job file to STATE without the table.
job_in() {
	sed "s/^state=.*/state=$1/" "$REPO/$JOBS_REL/$JOB/job" >"$T/job.tmp" && mv "$T/job.tmp" "$REPO/$JOBS_REL/$JOB/job"
}

# ci_env: the polling of the tests: no pause between reads, two seconds for the
# checks to appear and to wait for pending ones (not one: a second that ticks
# over between two reads must not decide).
ci_env() {
	export SW_CI_POLL_SECONDS=0 SW_CI_APPEAR_SECONDS=2 SW_CI_TIMEOUT_SECONDS=2
}

# ci_repo: a job in the ci state, with its PR (fake gh, origin).
ci_repo() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	add_origin
	open_run
	fake_gh
	ci_env
	sw job start $JOB
	assert_eq "$RC" 0 "start"
	job_in pr
	sw job pr $JOB
	assert_eq "$RC" 0 "pr"
	assert_eq "$(job_get state)" ci "state before ci"
}

# checks_seq LINE...: the lines of $T/gh/checks-seq, one per call of
# `gh pr checks` (the last one is repeated).
checks_seq() {
	rm -f "$T/gh/checks-seq-n"
	printf '%s\n' "$@" >"$T/gh/checks-seq"
}

# ci_calls: how many times gh was asked for the checks.
ci_calls() {
	grep -c '^pr checks' "$T/gh.log"
}

# escalated WHY: the job went to the human with the question `CI could not be
# read: <WHY>`, the way `job escalate` sends it.
escalated() {
	assert_eq "$(job_get state)" escalated "state: $1"
	assert_eq "$(last_event | jq -r .event)" escalate "event: $1"
	assert_contains "$REPO/$JOBS_REL/$JOB/escalation" "CI could not be read: $1"
	assert_contains "$OUT" "ci -> escalated (CI could not be read: $1"
}

# AC-V10-01: the checks are read with --json name,bucket and never watched;
# every read is appended to ci.log, which is emptied first.
test_ac_v10_01_polls_without_watch_and_logs() {
	ci_repo
	checks_seq none none pass:ci
	echo stale >"$REPO/$JOBS_REL/$JOB/ci.log"
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" reviewing "state"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event"
	assert_eq "$(ci_calls)" 3 "calls of pr checks"
	assert_contains "$T/gh.log" "pr checks 1 --json name,bucket --jq"
	! grep -F -e '--watch' "$T/gh.log" >/dev/null || fail "gh was called with --watch"
	! grep -F stale "$REPO/$JOBS_REL/$JOB/ci.log" >/dev/null || fail "ci.log was not emptied"
	assert_contains "$REPO/$JOBS_REL/$JOB/ci.log" "pass ci"
	assert_contains "$REPO/$JOBS_REL/$JOB/ci.log" "no checks reported"
}

# AC-V10-02: checks that never appear are no verdict on the work: the job goes
# to the human with a question, not to a new round.
test_ac_v10_02_no_checks_escalates() {
	ci_repo
	checks_seq none
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	escalated "no CI checks were reported for $(git -C "$(job_wt $JOB)" rev-parse HEAD | cut -c1-7) within 2s"
	assert_eq "$(job_get round)" 1 "round (no new round was spent)"
	[ "$(ci_calls)" -gt 1 ] || fail "the checks were read once"
}

# AC-V10-02: a gh that fails is waited out inside the window; one that keeps
# failing sends the job to the human with gh's first line.
test_ac_v10_02_gh_error() {
	ci_repo
	checks_seq "error boom" pass:ci
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event after a failed read"
	job_in ci
	checks_seq "error boom"
	sw job ci $JOB
	escalated "gh pr checks failed: boom"
}

# AC-V10-02: a PR head that still is the old commit is waited out; one that
# stays old after the window is a red CI of this commit.
test_ac_v10_02_head_catches_up() {
	ci_repo
	printf '%s\n' "$OLD_HEAD" tip >"$T/gh/head-seq"
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event once the head is the tip"
	job_in ci
	rm -f "$T/gh/head-seq-n"
	printf '%s\n' "$OLD_HEAD" >"$T/gh/head-seq"
	sw job ci $JOB
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(last_detail)" "ci_fail|PR head is not HEAD" "event for a head that stays old"
}

# AC-V10-01, AC-V10-03: a warning gh writes to stderr next to a good answer is
# neither the PR's head nor a check: green stays green, red stays red.
test_ac_v10_01_gh_warnings_are_not_answers() {
	ci_repo
	echo "a new release of gh is available" >"$T/gh/noise"
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event with a warning"
	job_in ci
	checks_seq fail:ci
	sw job ci $JOB
	assert_eq "$(last_detail)" "ci_fail|CI checks are not green: ci" "event of red checks with a warning"
}

# AC-V10-03: checks that are pending are waited for, then read again.
test_ac_v10_03_pending_then_pass() {
	ci_repo
	checks_seq pending:ci pass:ci
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event"
	assert_eq "$(ci_calls)" 2 "calls of pr checks"
}

# AC-V10-03: the first failing check is named, the others are counted, and the
# pending ones are not waited for.
test_ac_v10_03_red_names_the_first() {
	ci_repo
	checks_seq "pending:p pass:a fail:b fail:c"
	sw job ci $JOB
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(last_detail)" "ci_fail|CI checks are not green: b (+1 more)" "event"
	assert_eq "$(ci_calls)" 1 "calls of pr checks"
	assert_eq "$(job_get round)" 2 "round"
}

# AC-V10-03: a cancelled check is red.
test_ac_v10_03_cancel_is_red() {
	ci_repo
	checks_seq cancel:ci
	sw job ci $JOB
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(last_detail)" "ci_fail|CI checks are not green: ci" "event"
}

# AC-V10-03: a skipped check is green.
test_ac_v10_03_skipping_is_green() {
	ci_repo
	checks_seq "skipping:a pass:b"
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" reviewing "state"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event"
}

# AC-V10-04: checks that stay pending past the limit go to the human; the
# number in the question is max_ci_minutes (30 when the key is missing).
test_ac_v10_04_pending_times_out() {
	ci_repo
	checks_seq pending:ci
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	escalated "CI checks still pending after 30 minutes"
	[ "$(ci_calls)" -gt 1 ] || fail "the checks were read once"
}

# AC-V10-04: pending checks are waited for by the limit of max_ci_minutes, not
# by the window for checks to appear: with no window at all, checks that are
# pending still get their time, and checks that are not there get none.
test_ac_v10_04_pending_is_not_the_window() {
	ci_repo
	export SW_CI_APPEAR_SECONDS=0 SW_CI_TIMEOUT_SECONDS=5
	checks_seq pending:ci pending:ci pass:ci
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event"
	assert_eq "$(ci_calls)" 3 "calls of pr checks"
	job_in ci
	: >"$T/gh.log"
	checks_seq none pass:ci
	sw job ci $JOB
	escalated "no CI checks were reported for $(git -C "$(job_wt $JOB)" rev-parse HEAD | cut -c1-7) within 0s"
	assert_eq "$(ci_calls)" 1 "calls of pr checks with no window"
}

# AC-V10-02, AC-V10-04: once checks have been seen, a gh failure or a read with
# no checks is waited out like a pending check, up to the limit and not the
# window for checks to appear: one blip in a long CI wait escalates nothing.
test_ac_v10_04_blips_after_checks_are_waited_out() {
	ci_repo
	export SW_CI_APPEAR_SECONDS=0 SW_CI_TIMEOUT_SECONDS=5
	checks_seq pending:ci "error boom" pass:ci
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code after a gh failure"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event after a gh failure"
	assert_eq "$(ci_calls)" 3 "calls of pr checks"
	job_in ci
	checks_seq pending:ci none pass:ci
	sw job ci $JOB
	assert_eq "$(last_event | jq -r .event)" ci_pass "event after a read with no checks"
	job_in ci
	checks_seq pending:ci "error boom"
	export SW_CI_TIMEOUT_SECONDS=2
	sw job ci $JOB
	escalated "gh pr checks failed: boom"
}

# AC-V10-02: a PR head that cannot be read is a gh failure, not another head:
# waited out inside the window, then handed to the human with gh's message.
test_ac_v10_02_unreadable_head_is_a_gh_failure() {
	ci_repo
	printf '%s\n' "error nope" tip >"$T/gh/head-seq"
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event once the head can be read"
	assert_contains "$REPO/$JOBS_REL/$JOB/ci.log" "gh pr view failed: nope"
	job_in ci
	rm -f "$T/gh/head-seq-n"
	printf '%s\n' "error nope" >"$T/gh/head-seq"
	sw job ci $JOB
	escalated "gh pr view failed: nope"
	assert_eq "$(job_get round)" 1 "round (no new round was spent)"
}

# AC-V10-04: max_ci_minutes of loop.conf is the number in the question.
test_ac_v10_04_pending_uses_max_ci_minutes() {
	ci_repo
	loop_set max_ci_minutes 2
	checks_seq pending:ci
	sw job ci $JOB
	escalated "CI checks still pending after 2 minutes"
}

# AC-V10-04: the limit in seconds is max_ci_minutes * 60, 1800 when the key is
# missing (or has no usable value; doctor reports that).
test_ac_v10_04_timeout_seconds() {
	setup_repo
	conf_all true
	seconds() {
		SOFTWARY_ROOT=$REPO sh -c '. "$1/config.sh" && . "$1/loopconf.sh" && sw_ci_timeout_seconds' sh "$PKG_ROOT/src/lib"
	}
	unset SW_CI_TIMEOUT_SECONDS
	assert_eq "$(seconds)" 1800 "seconds without the key"
	loop_set max_ci_minutes 2
	assert_eq "$(seconds)" 120 "seconds with max_ci_minutes = 2"
	loop_set max_ci_minutes 0
	assert_eq "$(seconds)" 1800 "seconds with an invalid value"
	loop_set max_ci_minutes 2
	export SW_CI_TIMEOUT_SECONDS=7
	assert_eq "$(seconds)" 7 "seconds with the test override"
}

# AC-V10-05: max_ci_minutes is optional: an old loop.conf without it passes,
# and so does a valid value (the key is no unknown key).
test_ac_v10_05_key_is_optional() {
	setup_repo
	conf_all true
	sw doctor
	assert_eq "$RC" 0 "doctor exit code without the key"
	assert_match "$OUT" "^loop\.conf +PASS"
	loop_set max_ci_minutes 45
	sw doctor
	assert_eq "$RC" 0 "doctor exit code with the key"
	assert_match "$OUT" "^loop\.conf +PASS"
}

# AC-V10-05: a value that is no positive integer is a problem with its line
# number; `run start` stops on it.
test_ac_v10_05_key_is_validated() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	add_origin
	for bad in 0 abc -3 UNSET 2.5; do
		loop_set max_ci_minutes "$bad"
		sw doctor
		assert_eq "$RC" 2 "doctor exit code for $bad"
		assert_match "$OUT" "$LOOP_RE:8: max_ci_minutes: '$bad' is not a positive integer\)$"
	done
	loop_set max_ci_minutes abc
	commit_all "bad max_ci_minutes"
	sw run start
	assert_eq "$RC" 2 "run start exit code"
	assert_contains "$OUT" "max_ci_minutes: 'abc' is not a positive integer"
	[ ! -e "$REPO/.softwary/state/run" ] || fail "a run was opened"
}

# AC-V10-05: the template carries the key with its explanation and with the
# value the code uses when the key is missing.
test_ac_v10_05_template_has_the_key() {
	assert_match "$PKG_ROOT/src/templates/loop.conf" '^max_ci_minutes = 30$'
	assert_match "$PKG_ROOT/src/templates/loop.conf" '^#   max_ci_minutes  '
	setup_repo
	conf_all true
	cp "$PKG_ROOT/src/templates/loop.conf" "$REPO/.softwary/config/loop.conf"
	sw doctor
	assert_no_match "$OUT" "max_ci_minutes"
}

# AC-V10-06: CI that could not be read is the human's question, as if the
# agent had run `job escalate`; the human's answer resumes the job.
test_ac_v10_06_ci_unread_is_a_question() {
	ci_repo
	checks_seq none
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(last_event | jq -r '[.event, .from, .to] | join(">")')" "escalate>ci>escalated" "event"
	assert_match "$REPO/$JOBS_REL/$JOB/escalation" "^CI could not be read: no CI checks were reported for [0-9a-f]{7} within 2s$"
	sw job resume $JOB "checks are enabled now"
	assert_eq "$RC" 0 "resume"
}

# merge_repo: a job in `approving` on its pushed branch, with a PR, a green
# CI, an approving review and a decision to merge.
merge_repo() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	conf_set test_paths tests
	risk_set 'src/pay/*' R3
	add_eval
	mkdir -p "$REPO/tests"
	printf '# covers AC-001-01\n' >"$REPO/tests/test_login.py"
	add_origin
	open_run
	fake_gh
	ci_env
	sw job start $JOB
	sw job event $JOB implemented
	sw job gate $JOB
	sw job pr $JOB
	sw job ci $JOB
	review_job $JOB
	sw job review $JOB
	assert_eq "$(job_get state)" approving "state before merge"
	write_decision $JOB merge
	: >"$T/gh.log"
}

# AC-V10-07: merge reads the CI of the commit it merges; CI that could not be
# read refuses the merge with the reason, and gh does not merge.
test_ac_v10_07_merge_refuses_unread_ci() {
	merge_repo
	checks_seq none
	sw merge $JOB
	assert_eq "$RC" 1 "exit code"
	assert_eq "$(job_get state)" escalated "state"
	assert_contains "$OUT" "merge $JOB: refused: no CI checks were reported"
	assert_contains "$REPO/$JOBS_REL/$JOB/escalation" "merge refused: no CI checks were reported"
	assert_eq "$(last_event | jq -r .event)" escalate "event"
	! grep -F "pr merge" "$T/gh.log" >/dev/null || fail "gh pr merge was called"
}

# AC-V10-07: red CI refuses the merge, with the first failing check.
test_ac_v10_07_merge_refuses_red_ci() {
	merge_repo
	checks_seq pending:ci fail:ci
	sw merge $JOB
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "refused: CI checks are not green: ci"
	assert_eq "$(job_get state)" escalated "state"
	! grep -F "pr merge" "$T/gh.log" >/dev/null || fail "gh pr merge was called"
}

# AC-V10-07: checks that appear late are waited for; then the merge goes on.
test_ac_v10_07_merge_waits_for_checks() {
	merge_repo
	checks_seq none none pass:ci
	sw merge $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" merged "state"
	assert_contains "$T/gh.log" "pr merge 1 --squash --match-head-commit"
}

run_tests "$0"
