#!/bin/sh
# Tests for the waiver's requirement (doctor, run start) and for the scoped
# checks in the loop: the job's gate and the merge (V6).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log
WAIVERS_REL=.softwary/config/waivers.conf

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

last_event() {
	tail -n 1 "$REPO/$EVENTS_REL"
}

# waived_loop_repo [--files-unset]: the parallel plan approved, an origin and
# a fake gh; lint is red and waived, and its scoped command (check.sh) fails
# on a file that holds XXX. With --files-unset there is no lint_files. The run
# is not started.
waived_loop_repo() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	conf_set lint false
	[ "${1-}" = --files-unset ] || conf_set lint_files 'sh check.sh {files}'
	printf 'lint = 2999-12-31: legacy debt\n' >"$REPO/$WAIVERS_REL"
	cat >"$REPO/check.sh" <<'CHECK'
#!/bin/sh
bad=0
for f in "$@"; do
	if grep -q XXX "$f"; then
		echo "XXX in $f"
		bad=1
	fi
done
exit $bad
CHECK
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_parallel_plan
	add_eval
	add_origin
	fake_gh
}

# AC-V6-04: a waiver without its scoped command is a problem of its own; UNSET
# is as good as absent; NONE with a reason and a command are not.
test_ac_v6_04_doctor_requires_files_key() {
	waived_loop_repo --files-unset
	sw doctor
	assert_eq "$RC" 2 "exit code without lint_files"
	assert_match "$OUT" "^lint_files +FAIL \(required: lint has a waiver\)$"
	assert_match "$OUT" "^waiver lint +WAIVED "
	assert_match "$OUT" "^doctor: 1 problem\(s\) found$"
	conf_set lint_files UNSET
	sw doctor
	assert_eq "$RC" 2 "exit code with lint_files UNSET"
	assert_match "$OUT" "^lint_files +FAIL \(required: lint has a waiver\)$"
	conf_set lint_files 'NONE: the tool cannot take files'
	sw doctor
	assert_eq "$RC" 0 "exit code with NONE and a reason"
	assert_no_match "$OUT" "lint_files"
	conf_set lint_files 'sh check.sh {files}'
	sw doctor
	assert_eq "$RC" 0 "exit code with a command"
	# a check without a waiver does not need it
	: >"$REPO/$WAIVERS_REL"
	conf_del lint_files
	sw doctor
	assert_eq "$RC" 0 "exit code without a waiver"
}

# AC-V6-04: run start does not open the run for a waiver without its scoped
# command: exit 2, the reason named; with it the run opens.
test_ac_v6_04_run_start_refuses() {
	waived_loop_repo --files-unset
	sw run start
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "run start: lint_files is not set in .softwary/config/commands.conf (required: lint has a waiver)"
	[ ! -e "$REPO/.softwary/state/run" ] || fail "the run was opened"
	conf_set lint_files UNSET
	sw run start
	assert_eq "$RC" 2 "exit code with lint_files UNSET"
	assert_contains "$OUT" "run start: lint_files is not set in .softwary/config/commands.conf (required: lint has a waiver)"
	conf_set lint_files 'sh check.sh'
	sw run start
	assert_eq "$RC" 2 "exit code with a command without {files}"
	assert_match "$OUT" "lint_files must contain \{files\}"
	conf_set lint_files 'sh check.sh {files}'
	commit_all "scoped lint"
	sw run start
	assert_eq "$RC" 0 "exit code with lint_files"
	assert_match "$OUT" "^run: started$"
}

# AC-V6-04: the loop cannot add a waiver or loosen the requirement: the
# configuration is a protected path.
test_ac_v6_04_loop_cannot_edit_the_waivers() {
	waived_loop_repo
	open_run
	sw job start $JOB
	assert_eq "$RC" 0 "job start"
	wt=$(job_wt $JOB)
	printf 'test = 2999-12-31: make it pass\n' >>"$wt/$WAIVERS_REL"
	sed 's/^lint_files = .*/lint_files = NONE: nothing to scope/' "$wt/.softwary/config/commands.conf" >"$T/c" && cp "$T/c" "$wt/.softwary/config/commands.conf"
	commit_in "$wt" "waive things"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "guard exit code"
	assert_match "$OUT" "^guard: protected: $WAIVERS_REL$"
	assert_match "$OUT" "^guard: protected: \.softwary/config/commands\.conf$"
}

# a job at the gate with an implemented slice; EXTRA is appended to its code.
gate_ready() {
	sw job start $JOB
	assert_eq "$RC" 0 "job start"
	implement_job $JOB
	if [ -n "${1-}" ]; then
		printf '%s\n' "$1" >>"$(job_wt $JOB)/src/a/code_S1.py"
		commit_in "$(job_wt $JOB)" "more code"
	fi
	sw job event $JOB implemented
	assert_eq "$RC" 0 "implemented"
}

# AC-V6-05: a job that breaks the scoped check on a file it changes fails the
# gate, although the full check is red and waived anyway.
test_ac_v6_05_gate_fails_on_changed_file() {
	waived_loop_repo
	open_run
	gate_ready XXX
	sw job gate $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" implementing "state"
	assert_eq "$(job_get round)" 2 "round"
	assert_eq "$(last_event | jq -r .event)" gate_fail "event"
	assert_match "$REPO/$JOBS_REL/$JOB/gate-1.log" "^lint +WAIVED "
	assert_match "$REPO/$JOBS_REL/$JOB/gate-1.log" "^lint \(changed files\) +FAIL "
	assert_match "$REPO/$JOBS_REL/$JOB/gate-1.log" "^ +XXX in src/a/code_S1\.py$"
}

# AC-V6-05: a clean change passes the gate, and the merge, although the full
# check stays red under its waiver; the merge's log shows the scoped check.
test_ac_v6_05_gate_passes_clean_change() {
	waived_loop_repo
	open_run
	approve_job $JOB
	assert_match "$REPO/$JOBS_REL/$JOB/gate-1.log" "^lint +WAIVED "
	assert_match "$REPO/$JOBS_REL/$JOB/gate-1.log" "^lint \(changed files\) +PASS "
	sw merge $JOB
	assert_eq "$RC" 0 "merge exit code"
	assert_match "$OUT" "^merged: $JOB [0-9a-f]{40}$"
	assert_match "$REPO/$JOBS_REL/$JOB/merge.log" "^lint \(changed files\) +PASS "
}

# AC-V6-05: the merge runs the scoped check again, on the commit it merges:
# a change that broke it after the gate is refused.
test_ac_v6_05_merge_recomputes() {
	waived_loop_repo
	open_run
	approve_job $JOB
	printf 'XXX\n' >>"$(job_wt $JOB)/src/a/code_S1.py"
	commit_in "$(job_wt $JOB)" "after the gate"
	sw merge $JOB
	assert_eq "$RC" 1 "merge exit code"
	assert_eq "$(job_get state)" escalated "state"
	assert_contains "$REPO/$JOBS_REL/$JOB/escalation" "merge refused: verify fails"
	assert_match "$REPO/$JOBS_REL/$JOB/merge.log" "^lint \(changed files\) +FAIL "
	! grep -F "pr merge" "$T/gh.log" >/dev/null || fail "gh pr merge was called"
}

# AC-V6-05, review focus 2: the scoped check looks at the job's worktree and
# its own change; what the main checkout has changed does not count.
test_ac_v6_05_main_checkout_changes_do_not_count() {
	waived_loop_repo
	open_run
	sw job start $JOB
	assert_eq "$RC" 0 "job start"
	mkdir -p "$REPO/tests"
	printf 'XXX\n' >"$REPO/tests/main_checkout_test.sh"
	implement_job $JOB
	sw job event $JOB implemented
	sw job gate $JOB
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(job_get state)" pr "state: the gate passed"
	assert_match "$REPO/$JOBS_REL/$JOB/gate-1.log" "^lint \(changed files\) +PASS "
}

run_tests "$0"
