#!/bin/sh
# Tests for the worktree of a job: job start, the commands that run in it (V4).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log
REVIEW_REL=specs/001-login/reviews/S1.md

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

last_event() {
	tail -n 1 "$REPO/$EVENTS_REL"
}

# loop_repo [BOOTSTRAP]: approved product, blueprint and plan, an origin, an
# open run and a fake gh.
loop_repo() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	[ -z "${1-}" ] || conf_set bootstrap "$1"
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_plan
	add_origin
	open_run
	fake_gh
}

# to_state STATE: starts the job and moves it along the real path to STATE
# (gating, pr, ci, reviewing).
to_state() {
	sw job start $JOB
	assert_eq "$RC" 0 "start"
	sw job event $JOB implemented
	[ "$1" != gating ] || return 0
	sw job gate $JOB
	assert_eq "$RC" 0 "gate"
	[ "$1" != pr ] || return 0
	sw job pr $JOB
	assert_eq "$RC" 0 "pr"
	[ "$1" != ci ] || return 0
	sw job ci $JOB
	assert_eq "$RC" 0 "ci"
}

# AC-V4-03: job start opens softwary/<job> in .softwary/worktrees/<job> at the
# tip of the integration branch on origin, runs bootstrap there and leaves the
# main checkout on the integration branch, clean.
test_ac_v4_03_start_in_worktree() {
	loop_repo "touch BOOTED"
	git clone -q "$T/origin.git" "$T/other"
	git -C "$T/other" config user.name o
	git -C "$T/other" config user.email o@example.com
	printf 'x\n' >"$T/other/news.txt"
	git -C "$T/other" add news.txt
	git -C "$T/other" commit -q -m news
	git -C "$T/other" push -q --no-verify origin main
	sw job start $JOB
	assert_eq "$RC" 0 "exit code"
	wt=$(job_wt $JOB)
	assert_eq "$(git -C "$wt" rev-parse --abbrev-ref HEAD)" "softwary/$JOB" "branch of the worktree"
	assert_eq "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" main "branch of the main checkout"
	assert_eq "$(git -C "$REPO" status --porcelain)" "" "main checkout"
	[ -f "$wt/BOOTED" ] || fail "bootstrap did not run in the worktree"
	[ ! -e "$REPO/BOOTED" ] || fail "bootstrap ran in the main checkout"
	[ -f "$wt/news.txt" ] || fail "the branch does not start at origin's tip"
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(job_get round)" 1 "round"
	assert_eq "$(last_event | jq -r '[.job, .event, .from, .to] | join(" ")')" "$JOB start ready implementing" "event"
	assert_contains "$REPO/.softwary/.gitignore" "/worktrees/"
	[ ! -e "$wt/.softwary/state/jobs" ] || fail "the worktree got a state of its own"
}

# AC-V4-03: a failing bootstrap takes the worktree, the branch and the job
# record back and says where the log is; an UNSET bootstrap is exit 2 for both
# run start and job start.
test_ac_v4_03_bootstrap_fails() {
	loop_repo "echo boom; exit 3"
	sw job start $JOB
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "job $JOB: bootstrap failed (see .softwary/state/logs/bootstrap-$JOB.log)"
	assert_contains "$REPO/.softwary/state/logs/bootstrap-$JOB.log" boom
	[ ! -e "$(job_wt $JOB)" ] || fail "the worktree is still there"
	! git -C "$REPO" rev-parse -q --verify "refs/heads/softwary/$JOB" >/dev/null || fail "the branch is still there"
	[ ! -e "$REPO/$JOBS_REL/$JOB" ] || fail "the job record is still there"
	assert_eq "$(git -C "$REPO" worktree list | grep -c .)" 1 "worktrees"

	conf_set bootstrap UNSET
	commit_all "bootstrap unset"
	sw job start $JOB
	assert_eq "$RC" 2 "job start with bootstrap UNSET"
	assert_contains "$OUT" "bootstrap is UNSET in .softwary/config/commands.conf"
	rm "$REPO/.softwary/state/run"
	sw run start
	assert_eq "$RC" 2 "run start with bootstrap UNSET"
	assert_contains "$OUT" "bootstrap is UNSET"
	[ ! -e "$REPO/.softwary/state/run" ] || fail "a run was opened"
}

# AC-V4-04: gate, pr, ci and review work in the job's worktree whatever
# branch the main checkout is on.
test_ac_v4_04_commands_in_worktree() {
	loop_repo
	sw job start $JOB
	assert_eq "$RC" 0 "start"
	git -C "$REPO" checkout -q -b elsewhere
	sw job event $JOB implemented
	sw job gate $JOB
	assert_eq "$RC" 0 "gate"
	assert_eq "$(job_get state)" pr "state after the gate"
	sw job pr $JOB
	assert_eq "$RC" 0 "pr"
	wt=$(job_wt $JOB)
	assert_eq "$(git --git-dir="$T/origin.git" rev-parse "refs/heads/softwary/$JOB")" "$(git -C "$wt" rev-parse HEAD)" "pushed branch"
	sw job ci $JOB
	assert_eq "$RC" 0 "ci"
	mkdir -p "$wt/specs/001-login/reviews"
	printf -- '---\nslice: S1\ndecision: approve\n---\n\n# Review of S1\n' >"$wt/$REVIEW_REL"
	sw job review $JOB
	assert_eq "$RC" 0 "review"
	assert_eq "$(job_get state)" approving "state after the review"
	assert_eq "$(sed -n 's/^status: //p' "$wt/specs/001-login/slices/S1.md")" "done" "slice in the worktree"
	assert_eq "$(sed -n 's/^status: //p' "$REPO/specs/001-login/slices/S1.md")" planned "slice in the main checkout"
	assert_eq "$(git -C "$wt" log -1 --format=%s)" "$JOB: review approved" "commit in the worktree"
	assert_eq "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" elsewhere "main checkout's branch"
}

# AC-V4-04: the gate runs the main checkout's scripts on the job's tree: a job
# that breaks its own copy of the script gets a guard violation, not a pass.
test_ac_v4_04_gate_uses_main_scripts() {
	loop_repo
	sw job start $JOB
	wt=$(job_wt $JOB)
	printf 'exit 0\n' >"$wt/.softwary/bin/softwary"
	git -C "$wt" -c user.name=t -c user.email=t@example.com commit -q --no-verify -am "break the script"
	sw job event $JOB implemented
	sw job gate $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(last_event | jq -r .event)" gate_fail "event"
	assert_eq "$(last_event | jq -r .detail)" "guard: protected: .softwary/bin/softwary" "detail"
}

# AC-V4-04: guard <job> checks the job's branch, not the checkout's HEAD.
test_ac_v4_04_guard_uses_branch() {
	loop_repo
	sw job start $JOB
	wt=$(job_wt $JOB)
	mkdir -p "$wt/lib"
	printf 'x\n' >"$wt/lib/other.txt"
	git -C "$wt" add lib/other.txt
	git -C "$wt" -c user.name=t -c user.email=t@example.com commit -q --no-verify -m "outside"
	assert_eq "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" main "main checkout"
	sw guard $JOB
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "guard: outside touches: lib/other.txt"
}

# AC-V4-04: a worktree that is gone is built again from the local branch, then
# from origin/softwary/<job>; with neither, 2. abandon takes the worktree away
# and leaves the branch.
test_ac_v4_04_worktree_rebuilt_and_cleaned() {
	loop_repo
	to_state gating
	wt=$(job_wt $JOB)
	rm -rf "$wt"
	sw job gate $JOB
	assert_eq "$RC" 0 "gate with the worktree gone"
	[ -e "$wt/.git" ] || fail "the worktree was not rebuilt from the local branch"
	assert_eq "$(job_get state)" pr "state"
	sw job pr $JOB
	assert_eq "$RC" 0 "pr"
	git -C "$REPO" worktree remove --force "$wt"
	git -C "$REPO" branch -D "softwary/$JOB" >/dev/null
	sw job ci $JOB
	assert_eq "$RC" 0 "ci with no worktree and no local branch"
	assert_eq "$(git -C "$wt" rev-parse --abbrev-ref HEAD)" "softwary/$JOB" "branch rebuilt from origin"
	assert_eq "$(job_get state)" reviewing "state"
	git -C "$REPO" worktree remove --force "$wt"
	git -C "$REPO" branch -D "softwary/$JOB" >/dev/null
	git -C "$REPO" push -q origin ":softwary/$JOB" >/dev/null 2>&1
	git -C "$REPO" update-ref -d "refs/remotes/origin/softwary/$JOB"
	sw job review $JOB
	assert_eq "$RC" 2 "review with nothing to build the worktree from"
	assert_contains "$OUT" "no worktree and no branch softwary/$JOB"
	git -C "$REPO" branch -q --no-track "softwary/$JOB" origin/main
	sw job escalate $JOB "a question"
	sw job abandon $JOB "not needed"
	assert_eq "$RC" 0 "abandon"
	[ ! -e "$wt" ] || fail "abandon left the worktree"
	git -C "$REPO" rev-parse -q --verify "refs/heads/softwary/$JOB" >/dev/null || fail "abandon removed the branch"
}

# AC-V4-06: a job left in `ready` (the record is there, start was not applied)
# is resumed by run next and finished by job start.
test_ac_v4_06_resume_ready() {
	loop_repo
	mkdir -p "$REPO/$JOBS_REL/$JOB"
	printf 'state=ready\nround=0\nstarted=%s\ntokens=0\nbranch=softwary/%s\n' "$(date +%s)" "$JOB" >"$REPO/$JOBS_REL/$JOB/job"
	sw run next
	assert_eq "$RC" 0 "run next"
	assert_match "$OUT" "^resume $JOB ready$"
	sw job start $JOB
	assert_eq "$RC" 0 "job start on a ready job"
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(git -C "$(job_wt $JOB)" rev-parse --abbrev-ref HEAD)" "softwary/$JOB" "worktree"
	sw job start $JOB
	assert_eq "$RC" 1 "a second start"
}

run_tests "$0"
