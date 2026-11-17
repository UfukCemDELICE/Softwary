#!/bin/sh
# Tests for the repro field of a slice, ./softwary repro and its place in the
# job's gate and in the merge (V7).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
S1=specs/001-login/slices/S1.md
TEST=tests/test_bug.sh

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

# ready: a repo with an approved product and blueprint and the sample plan.
ready() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	assert_eq "$RC" 0 "approve product"
	approve_blueprint
	assert_eq "$RC" 0 "approve blueprint"
	add_plan
	rm -r "$REPO/specs/002-tasks"
}

# repro_repo [PATHS]: the plan with a slice that has a repro, the bug on main
# and the job's branch checked out, as guard's tests have it.
repro_repo() {
	ready
	add_repro_slice "$@"
	git -C "$REPO" checkout -q -b "softwary/$JOB"
}

# worktrees: how many worktrees the repository has.
worktrees() {
	git -C "$REPO" worktree list | wc -l | tr -d ' '
}

# no_worktree_left: repro left no worktree and no directory behind.
no_worktree_left() {
	assert_eq "$(worktrees)" 1 "worktrees"
	[ ! -e "$REPO/.softwary/state/repro/$JOB" ] || fail "the worktree directory of repro is still there"
}

# nothing_left: and no change in the working tree or in the branch checked out.
nothing_left() {
	no_worktree_left
	assert_eq "$(git -C "$REPO" status --porcelain)" "" "the working tree"
	assert_eq "$(git -C "$REPO" branch --show-current)" "softwary/$JOB" "the branch checked out"
}

# AC-V7-05: the slice may carry a repro; trace knows the field, an empty one
# is fine and an UNSET one is a problem.
test_ac_v7_05_trace_knows_the_field() {
	ready
	add_repro_slice
	sw trace
	assert_eq "$RC" 0 "trace exit code"
	fm_set "$REPO/$S1" repro UNSET
	sw trace
	assert_eq "$RC" 1 "trace exit code with repro UNSET"
	assert_match "$OUT" "^$S1: repro: is UNSET$"
	fm_set "$REPO/$S1" repro ""
	sw trace
	assert_eq "$RC" 0 "trace exit code with an empty repro"
	fm_del "$REPO/$S1" repro
	sw trace
	assert_eq "$RC" 0 "trace exit code with no repro"
	fm_set "$REPO/$S1" fix "tests/test_bug.sh"
	sw trace
	assert_match "$OUT" "^$S1: unknown field 'fix'$"
}

# AC-V7-05: each repro path must be under test_paths and in the slice's touches.
test_ac_v7_05_paths_under_test_paths_and_touches() {
	ready
	add_repro_slice
	sw plan check
	assert_eq "$RC" 0 "plan check exit code"
	fm_set "$REPO/$S1" repro "tests/test_bug.sh docs/repro.sh"
	sw plan check
	assert_eq "$RC" 1 "plan check exit code with a path outside test_paths"
	assert_match "$OUT" "^$S1: repro: 'docs/repro\.sh' is not under test_paths \(tests\)$"
	assert_no_match "$OUT" "tests/test_bug.sh"
	fm_set "$REPO/$S1" repro "tests/test_bug.sh"
	fm_set "$REPO/$S1" touches "src/api, tests/other"
	sw plan check
	assert_eq "$RC" 1 "plan check exit code with a path outside touches"
	assert_match "$OUT" "^$S1: repro: 'tests/test_bug\.sh' is not in touches$"
	fm_set "$REPO/$S1" touches "src/api, tests/test_bug.sh"
	sw plan check
	assert_eq "$RC" 0 "plan check exit code with the path in touches"
	# a spec that is done is not checked any more
	fm_set "$REPO/$S1" repro "docs/repro.sh"
	fm_set "$REPO/specs/001-login/spec.md" status "done"
	sw plan check
	assert_no_match "$OUT" "repro"
}

# AC-V7-05: with a slice that has a repro, test_files must be a command: UNSET
# and NONE are problems, in plan check and in doctor, each on its own line.
test_ac_v7_05_test_files_must_be_a_command() {
	ready
	add_repro_slice
	sw doctor
	assert_no_match "$OUT" "test_files"
	conf_set test_files UNSET
	sw plan check
	assert_eq "$RC" 1 "plan check exit code with test_files UNSET"
	assert_match "$OUT" "^$S1: repro: test_files must be a command that takes \{files\} in $(printf '%s' ".softwary/config/commands.conf" | sed 's/\./\\./g') \(it is UNSET\)$"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code with test_files UNSET"
	assert_match "$OUT" "^test_files +FAIL \(required: a slice has repro, $S1\)$"
	conf_set test_files 'NONE: no tests that take files'
	sw plan check
	assert_match "$OUT" "^$S1: repro: test_files must be a command that takes \{files\} in .* \(it is NONE\)$"
	sw doctor
	assert_match "$OUT" "^test_files +FAIL \(required: a slice has repro, $S1\)$"
	conf_del test_files
	sw plan check
	assert_match "$OUT" "\(it is UNSET\)$"
	# without a repro nobody asks for it
	conf_set test_files UNSET
	fm_del "$REPO/$S1" repro
	sw plan check
	assert_eq "$RC" 0 "plan check exit code without a repro"
	sw doctor
	assert_no_match "$OUT" "test_files"
}

# AC-V7-06: the test fails on the base and passes on the job: both lines, exit
# 0, a log for each run.
test_ac_v7_06_fails_on_the_base_and_passes_on_the_job() {
	repro_repo
	repro_commit "$REPO"
	sw repro $JOB --base main
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^repro: $TEST fails on the base$"
	assert_match "$OUT" "^repro: $TEST passes on the job$"
	assert_match "$OUT" "^repro: no problems$"
	[ -f "$REPO/.softwary/state/logs/repro-$JOB-base.log" ] || fail "no log of the base run"
	[ -f "$REPO/.softwary/state/logs/repro-$JOB-job.log" ] || fail "no log of the job run"
	nothing_left
}

# AC-V7-06: the base is the integration branch when --base is not given.
test_ac_v7_06_default_base_is_the_integration_branch() {
	repro_repo
	repro_commit "$REPO"
	sw repro $JOB
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^repro: $TEST fails on the base$"
	sw repro $JOB --base nowhere
	assert_eq "$RC" 2 "exit code for a base that is not there"
	assert_match "$OUT" "^repro: base 'nowhere' not found"
}

# AC-V7-06: a test that passes on the base does not reproduce the bug.
test_ac_v7_06_passes_on_the_base() {
	repro_repo
	git -C "$REPO" checkout -q main
	printf 'add() { echo $(($1 + $2)); }\n' >"$REPO/src/api/calc.sh"
	commit_all "no bug on the base"
	git -C "$REPO" checkout -q "softwary/$JOB"
	git -C "$REPO" merge -q --no-edit main
	repro_commit "$REPO" nofix
	sw repro $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^repro: $TEST passes on the base \(it does not reproduce the bug\)$"
	assert_match "$OUT" "^repro: $TEST passes on the job$"
	assert_match "$OUT" "^repro: 1 problem\(s\)$"
	nothing_left
}

# AC-V7-06: a test that still fails on the job is a problem.
test_ac_v7_06_fails_on_the_job() {
	repro_repo
	repro_commit "$REPO" nofix
	sw repro $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^repro: $TEST fails on the base$"
	assert_match "$OUT" "^repro: $TEST fails on the job$"
	nothing_left
}

# AC-V7-06: a repro file the job did not change is not a proof, and neither is
# one that is not there.
test_ac_v7_06_not_changed_by_the_job() {
	repro_repo "tests/test_bug.sh tests/test_gone.sh"
	git -C "$REPO" checkout -q main
	mkdir -p "$REPO/tests"
	printf '#!/bin/sh\nexit 1\n' >"$REPO/$TEST"
	commit_all "a test that was there"
	git -C "$REPO" checkout -q "softwary/$JOB"
	git -C "$REPO" merge -q --no-edit main
	printf 'add() { echo $(($1 + $2)); }\n' >"$REPO/src/api/calc.sh"
	commit_all "a fix without the test"
	sw repro $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^repro: $TEST is not changed by the job$"
	assert_match "$OUT" "^repro: tests/test_gone\.sh is missing in the job$"
	assert_match "$OUT" "^repro: 2 problem\(s\)$"
	assert_no_match "$OUT" "on the base"
	nothing_left
}

# AC-V7-06: every path has its own verdict.
test_ac_v7_06_a_verdict_for_each_path() {
	repro_repo "tests/test_a.sh tests/test_b.sh"
	mkdir -p "$REPO/tests"
	printf '#!/bin/sh\n# covers AC-001-01\n. "$(dirname "$0")/../src/api/calc.sh"\n[ "$(add 2 3)" = 5 ]\n' >"$REPO/tests/test_a.sh"
	printf '#!/bin/sh\n# AC-001-01 again\nexit 0\n' >"$REPO/tests/test_b.sh"
	printf 'add() { echo $(($1 + $2)); }\n' >"$REPO/src/api/calc.sh"
	commit_all "two tests and the fix"
	sw repro $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^repro: tests/test_a\\.sh fails on the base$"
	assert_match "$OUT" "^repro: tests/test_a\\.sh passes on the job$"
	assert_match "$OUT" "^repro: tests/test_b\\.sh passes on the base \\(it does not reproduce the bug\\)$"
	assert_match "$OUT" "^repro: tests/test_b\\.sh passes on the job$"
	assert_match "$OUT" "^repro: 1 problem\\(s\\)$"
}

# AC-V7-06: a slice without a repro has nothing to prove: `repro: none`, exit 0.
test_ac_v7_06_none() {
	repro_repo
	git -C "$REPO" checkout -q main
	fm_del "$REPO/$S1" repro
	commit_all "no repro"
	git -C "$REPO" checkout -q "softwary/$JOB"
	git -C "$REPO" merge -q --no-edit main
	sw repro $JOB --base main
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(cat "$OUT")" "repro: none" "output"
	sw repro 001-S2 --base main
	assert_eq "$RC" 0 "exit code for a slice that never had one"
	assert_eq "$(cat "$OUT")" "repro: none" "output"
	nothing_left
}

# AC-V7-06: the slice is read as the base had it: a job that takes its own
# repro out of the slice, or adds a test to it, is held to the plan's.
test_ac_v7_06_the_slice_is_the_bases() {
	repro_repo
	fm_del "$REPO/$S1" repro
	fm_set "$REPO/$S1" repro "tests/test_extra.sh"
	repro_commit "$REPO"
	sw repro $JOB --base main
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^repro: $TEST fails on the base$"
	assert_no_match "$OUT" "none|test_extra"
	nothing_left
	# without the test the job cannot say the slice has none
	git -C "$REPO" reset -q --hard main
	fm_del "$REPO/$S1" repro
	commit_all "the job drops its repro"
	sw repro $JOB --base main
	assert_eq "$RC" 1 "exit code when the job drops the repro and the test"
	assert_match "$OUT" "^repro: $TEST is missing in the job$"
}

# AC-V7-06: the base is made ready with bootstrap, in the temporary worktree
# and nowhere else; the worktree is gone afterwards, and also when bootstrap fails.
test_ac_v7_06_bootstrap_on_the_base() {
	repro_repo
	conf_set bootstrap "pwd >>$T/boots.log"
	commit_all "bootstrap"
	repro_commit "$REPO"
	sw repro $JOB --base main
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(cat "$T/boots.log")" "$(cd "$REPO" && pwd -P)/.softwary/state/repro/$JOB" "where bootstrap ran"
	nothing_left
	conf_set bootstrap "false"
	commit_all "a bootstrap that fails"
	sw repro $JOB --base main
	assert_eq "$RC" 2 "exit code when bootstrap fails"
	assert_match "$OUT" "^repro: bootstrap failed on the base \(see \.softwary/state/logs/repro-$JOB-base\.log\)$"
	nothing_left
	conf_set bootstrap "UNSET"
	commit_all "no bootstrap"
	sw repro $JOB --base main
	assert_eq "$RC" 2 "exit code when bootstrap is UNSET"
	assert_match "$OUT" "bootstrap is UNSET"
	nothing_left
}

# AC-V7-06: a worktree that an earlier, killed run left is taken away first.
test_ac_v7_06_a_stale_worktree_is_removed() {
	repro_repo
	repro_commit "$REPO"
	git -C "$REPO" worktree add -q --detach "$REPO/.softwary/state/repro/$JOB" main
	echo stale >"$REPO/.softwary/state/repro/$JOB/stale.txt"
	sw repro $JOB --base main
	assert_eq "$RC" 0 "exit code"
	nothing_left
}

# AC-V7-06: usage and configuration errors are 2: no job, a name that is not a
# job, no slice, an option nobody knows, test_files that is not a command and a
# command without {files}.
test_ac_v7_06_usage_and_configuration() {
	repro_repo
	repro_commit "$REPO"
	sw repro
	assert_eq "$RC" 2 "exit code without a job"
	assert_contains "$OUT" "usage: ./softwary repro <job> [--base <ref>]"
	sw repro login
	assert_eq "$RC" 2 "exit code for a name that is not a job"
	assert_contains "$OUT" "repro: login is not a job (NNN-S<n>)"
	sw repro 009-S9
	assert_eq "$RC" 2 "exit code for a job without a slice"
	assert_contains "$OUT" "repro: no slice 009-S9"
	sw repro $JOB --fast
	assert_eq "$RC" 2 "exit code for an option nobody knows"
	sw repro $JOB --base
	assert_eq "$RC" 2 "exit code for --base without a ref"
	conf_set test_files UNSET
	sw repro $JOB --base main
	assert_eq "$RC" 2 "exit code with test_files UNSET"
	assert_match "$OUT" "^repro: test_files is UNSET in \.softwary/config/commands\.conf"
	conf_set test_files "NONE: no tests that take files"
	sw repro $JOB --base main
	assert_eq "$RC" 2 "exit code with test_files NONE"
	conf_set test_files "sh tests/run.sh"
	sw repro $JOB --base main
	assert_eq "$RC" 2 "exit code with a command without {files}"
	assert_match "$OUT" "test_files must contain \{files\}"
	no_worktree_left
}

# AC-V7-06: repro is documented in help.
test_ac_v7_06_help() {
	setup_repo
	sw help
	assert_match "$OUT" "^  repro <job> \[--base <ref>\]"
}

# loop_repo: the approved plan with the bug and the repro slice, an origin, a
# fake gh, an evaluation and an open run.
loop_repo() {
	ready
	add_repro_slice
	add_eval
	add_origin
	open_run
	fake_gh
}

# gate_job [nofix]: the job started and its commit made, at the gate.
gate_job() {
	sw job start $JOB
	assert_eq "$RC" 0 "job start"
	repro_commit "$(job_wt $JOB)" "$@"
	sw job event $JOB implemented
	assert_eq "$RC" 0 "implemented"
}

# AC-V7-07: the gate runs repro after guard: the test fails on the base and
# passes on the job, the gate passes and keeps repro's lines in the job's directory.
test_ac_v7_07_gate_passes() {
	loop_repo
	gate_job
	sw job gate $JOB
	assert_eq "$RC" 0 "gate exit code"
	assert_eq "$(job_get state)" pr "state"
	log=$REPO/$JOBS_REL/$JOB/repro-1.log
	assert_match "$log" "^repro: $TEST fails on the base$"
	assert_match "$log" "^repro: $TEST passes on the job$"
	assert_match "$REPO/$JOBS_REL/$JOB/gate-1.log" "^sync "
}

# AC-V7-07: a test that does not fail on the base fails the gate at once, with
# the line that says so and without the verify; the base the gate takes is
# origin's integration branch.
test_ac_v7_07_gate_fails_on_repro() {
	loop_repo
	git -C "$REPO" checkout -q main
	printf 'add() { echo $(($1 + $2)); }\n' >"$REPO/src/api/calc.sh"
	commit_all "no bug"
	git -C "$REPO" push -q --no-verify origin main
	sw job start $JOB
	repro_commit "$(job_wt $JOB)" nofix
	sw job event $JOB implemented
	sw job gate $JOB
	assert_eq "$RC" 0 "gate exit code (the gate records the failure and goes on)"
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(job_get round)" 2 "round"
	last=$(tail -n 1 "$REPO/.softwary/state/events.log")
	assert_eq "$(printf '%s' "$last" | jq -r .event)" gate_fail "event"
	assert_eq "$(printf '%s' "$last" | jq -r .detail)" "repro: $TEST passes on the base (it does not reproduce the bug)" "detail"
	assert_match "$REPO/$JOBS_REL/$JOB/repro-1.log" "passes on the base"
	assert_no_match "$REPO/$JOBS_REL/$JOB/gate-1.log" "^sync "
}

# AC-V7-07: a test that still fails on the job fails the gate too.
test_ac_v7_07_gate_fails_when_the_job_does_not_fix() {
	loop_repo
	gate_job nofix
	sw job gate $JOB
	assert_eq "$(job_get state)" implementing "state"
	last=$(tail -n 1 "$REPO/.softwary/state/events.log")
	assert_eq "$(printf '%s' "$last" | jq -r .detail)" "repro: $TEST fails on the job" "detail"
}

# AC-V7-07: when repro cannot run (bootstrap of the base fails) the gate says
# so and exits 2, with no transition.
test_ac_v7_07_gate_stops_when_repro_cannot_run() {
	loop_repo
	gate_job
	conf_set bootstrap false
	sw job gate $JOB
	assert_eq "$RC" 2 "gate exit code"
	assert_contains "$OUT" "repro: bootstrap failed on the base"
	assert_eq "$(job_get state)" gating "state"
	assert_eq "$(worktrees)" 2 "worktrees (the main checkout and the job's)"
}

# AC-V7-07: the merge works repro out again on the commit it merges: a job whose
# last commit breaks the fix is refused, and gh pr merge is not called.
test_ac_v7_07_merge_recomputes() {
	loop_repo
	gate_job
	for step in gate pr ci; do
		sw job $step $JOB
		assert_eq "$RC" 0 "job $step"
	done
	review_job $JOB
	sw job review $JOB
	assert_eq "$RC" 0 "job review"
	write_decision $JOB merge
	wt=$(job_wt $JOB)
	printf 'add() { echo $(($1 - $2)); }\n' >"$wt/src/api/calc.sh"
	commit_in "$wt" "break the fix after the gate"
	: >"$T/gh.log"
	sw merge $JOB
	assert_eq "$RC" 1 "merge exit code"
	assert_contains "$OUT" "merge $JOB: refused: repro: $TEST fails on the job"
	! grep -F "pr merge" "$T/gh.log" >/dev/null || fail "gh pr merge was called"
	assert_eq "$(job_get state)" escalated "state"
}

run_tests "$0"
