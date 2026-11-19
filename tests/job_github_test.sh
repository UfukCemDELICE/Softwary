#!/bin/sh
# Tests for `job pr`, `job ci`, `job review` and the human-facing job commands (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log
REVIEW_REL=specs/001-login/reviews/S1.md
SLICE_REL=specs/001-login/slices/S1.md

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

last_event() {
	tail -n 1 "$REPO/$EVENTS_REL"
}

# job_in STATE: moves the job file to STATE without the table (the state
# machine itself is tested in transitions_test.sh).
job_in() {
	sed "s/^state=.*/state=$1/" "$REPO/$JOBS_REL/$JOB/job" >"$T/job.tmp" && mv "$T/job.tmp" "$REPO/$JOBS_REL/$JOB/job"
}

# write_review DECISION [SLICE]: the reviewer's record for slice S1.
write_review() {
	mkdir -p "$(job_wt $JOB)/specs/001-login/reviews"
	printf -- '---\nslice: %s\ndecision: %s\n---\n\n# Review of S1\n' "${2:-S1}" "$1" >"$(job_wt $JOB)/$REVIEW_REL"
}

# job_repo STATE: the job started on its branch with a fake gh and an origin,
# then moved to STATE (implementing, gating, pr, ci, reviewing).
job_repo() {
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
	sw job start $JOB
	assert_eq "$RC" 0 "start"
	job_in "$1"
}

origin_tip() {
	git --git-dir="$T/origin.git" rev-parse "refs/heads/softwary/$JOB"
}

# AC-V2-09: job pr pushes the branch, opens the PR once and records its number.
test_ac_v2_09_pr_pushes_and_records() {
	job_repo pr
	sw job pr $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(origin_tip)" "$(git -C "$REPO" rev-parse HEAD)" "origin's branch"
	assert_contains "$T/gh.log" "pr create --base main --head softwary/$JOB --title $JOB: Sign in with a correct password"
	assert_eq "$(job_get pr)" 1 "recorded PR"
	assert_eq "$(job_get state)" ci "state"
	assert_eq "$(last_event | jq -r .event)" pr_opened "event"
	job_in pr
	sw job pr $JOB
	assert_eq "$RC" 0 "second exit code"
	assert_eq "$(grep -c 'pr create' "$T/gh.log")" 1 "PR creations"
	assert_eq "$(job_get state)" ci "state again"
}

# AC-V2-09: job pr wants the pr state and the job's branch.
test_ac_v2_09_pr_preconditions() {
	job_repo gating
	sw job pr $JOB
	assert_eq "$RC" 1 "exit code in the wrong state"
	job_in pr
	git -C "$(job_wt $JOB)" checkout -q -b other
	sw job pr $JOB
	assert_eq "$RC" 2 "exit code on the wrong branch"
	[ ! -s "$T/gh.log" ] || fail "gh was called"
}

# AC-V2-09: ci passes when the PR's head is HEAD and the checks pass; it fails
# for a different head and for red checks.
test_ac_v2_09_ci_pass_fail_head_mismatch() {
	job_repo pr
	sw job pr $JOB
	sw job ci $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" reviewing "state after green checks"
	assert_eq "$(last_event | jq -r .event)" ci_pass "event"
	assert_contains "$T/gh.log" "pr checks 1 --json name,bucket"
	job_in ci
	echo 1 >"$T/gh/checks"
	sw job ci $JOB
	assert_eq "$(job_get state)" implementing "state after red checks"
	assert_eq "$(last_event | jq -r .event)" ci_fail "event"
	assert_eq "$(job_get round)" 2 "round"
	job_in ci
	echo 0 >"$T/gh/checks"
	echo 0000000000000000000000000000000000000000 >"$T/gh/head"
	sw job ci $JOB
	assert_eq "$(last_event | jq -r '[.event, .detail] | join("|")')" "ci_fail|PR head is not HEAD" "event for another head"
	job_in pr
	sw job ci $JOB
	assert_eq "$RC" 1 "exit code in the wrong state"
}

# AC-V2-10: no record, an unreadable record or one for another slice is no transition.
test_ac_v2_10_review_missing_invalid() {
	job_repo reviewing
	sw job review $JOB
	assert_eq "$RC" 1 "exit code without a record"
	assert_contains "$OUT" "no review record"
	write_review maybe
	sw job review $JOB
	assert_eq "$RC" 1 "exit code with a bad decision"
	write_review approve S2
	sw job review $JOB
	assert_eq "$RC" 1 "exit code with another slice"
	printf 'no front matter\n' >"$(job_wt $JOB)/$REVIEW_REL"
	sw job review $JOB
	assert_eq "$RC" 1 "exit code with no front matter"
	assert_eq "$(job_get state)" reviewing "state"
	assert_eq "$(git -C "$(job_wt $JOB)" log -1 --format=%s)" "base" "no commit was made"
}

# AC-V2-10: approve marks the slice done, commits the record and the slice, pushes.
test_ac_v2_10_review_approve_commits_done() {
	job_repo reviewing
	write_review approve
	sw job review $JOB
	assert_eq "$RC" 0 "exit code"
	wt=$(job_wt $JOB)
	assert_eq "$(sed -n 's/^status: //p' "$wt/$SLICE_REL")" "done" "slice status"
	assert_eq "$(git -C "$wt" log -1 --format=%s)" "$JOB: review approved" "commit"
	assert_eq "$(git -C "$wt" show --name-only --format= HEAD | sort | paste -sd' ' -)" "$REVIEW_REL $SLICE_REL" "committed files"
	assert_eq "$(origin_tip)" "$(git -C "$wt" rev-parse HEAD)" "origin's branch"
	assert_eq "$(job_get state)" approving "state"
	[ -z "$(git -C "$wt" status --porcelain)" ] || fail "the tree is not clean"
	assert_eq "$(sed -n 's/^status: //p' "$REPO/$SLICE_REL")" planned "slice status in the main checkout"
}

# AC-V2-10: changes commits the record and starts the next round.
test_ac_v2_10_review_changes_new_round() {
	job_repo reviewing
	write_review changes
	sw job review $JOB
	assert_eq "$RC" 0 "exit code"
	wt=$(job_wt $JOB)
	assert_eq "$(sed -n 's/^status: //p' "$wt/$SLICE_REL")" planned "slice status"
	assert_eq "$(git -C "$wt" log -1 --format=%s)" "$JOB: review requested changes" "commit"
	assert_eq "$(origin_tip)" "$(git -C "$wt" rev-parse HEAD)" "origin's branch"
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(job_get round)" 2 "round"
}

# AC-V2-08: escalate, resume and abandon record their text and change the state.
test_ac_v2_08_escalate_resume_abandon() {
	job_repo implementing
	sw job escalate $JOB "Which hash should passwords use?"
	assert_eq "$RC" 0 "escalate exit code"
	assert_eq "$(job_get state)" escalated "state"
	assert_eq "$(cat "$REPO/$JOBS_REL/$JOB/escalation")" "Which hash should passwords use?" "escalation"
	sw job escalate $JOB
	assert_eq "$RC" 2 "escalate without a question"
	sw job resume $JOB "Use argon2."
	assert_eq "$RC" 0 "resume exit code"
	assert_eq "$(job_get state)" implementing "state after resume"
	assert_eq "$(cat "$REPO/$JOBS_REL/$JOB/answer")" "Use argon2." "answer"
	sw job escalate $JOB "again"
	sw job abandon $JOB "not needed"
	assert_eq "$(job_get state)" abandoned "state after abandon"
	assert_eq "$(last_event | jq -r '[.event, .detail] | join("|")')" "abandon|not needed" "event"
	sw job resume $JOB "too late"
	assert_eq "$RC" 1 "resume of an abandoned job"
}

# AC-V2-08: job merged records a human's merge only when the PR is MERGED.
test_ac_v2_08_human_merged() {
	job_repo pr
	sw job pr $JOB
	sw job escalate $JOB "R3: a human merges"
	sw job merged $JOB
	assert_eq "$RC" 1 "exit code with an open PR"
	assert_eq "$(job_get state)" escalated "state"
	echo MERGED >"$T/gh/state"
	sw job merged $JOB
	assert_eq "$RC" 0 "exit code with a merged PR"
	assert_eq "$(job_get state)" merged "state"
	[ ! -e "$(job_wt $JOB)" ] || fail "the worktree of a merged job is still there"
	! git -C "$REPO" rev-parse -q --verify "refs/heads/softwary/$JOB" >/dev/null || fail "the local branch of a merged job is still there"
	assert_eq "$(last_event | jq -r .event)" human_merged "event"
	assert_contains "$T/gh.log" "pr view 1 --json state"
}

# AC-V2-08: job show prints the job file, the question and the last events.
test_ac_v2_08_show() {
	job_repo implementing
	sw job escalate $JOB "Which database?"
	sw job show $JOB
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^state=escalated$"
	assert_match "$OUT" "^question: Which database\?$"
	assert_match "$OUT" "\"event\":\"escalate\""
	sw job show 009-S9
	assert_eq "$RC" 2 "unknown job"
}

run_tests "$0"
