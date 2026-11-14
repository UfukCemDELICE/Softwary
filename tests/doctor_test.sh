#!/bin/sh
# Tests for ./softwary doctor.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck disable=SC2329 # test functions are called by run_tests

# AC-M0-07: a complete setup reports no problem and exits 0.
test_ac_m0_07_clean_setup_passes() {
	setup_repo
	conf_all true
	sw doctor
	assert_eq "$RC" 0 "exit code"
	assert_no_match "$OUT" " FAIL"
	assert_match "$OUT" "^git +PASS"
	assert_match "$OUT" "^jq +PASS"
	assert_match "$OUT" "^git repository +PASS"
}

# AC-M0-07: missing git is reported on its own line.
test_ac_m0_07_missing_git() {
	setup_repo
	conf_all true
	bin=$(path_without git)
	RC=0
	(cd "$REPO" && PATH=$bin ./softwary doctor) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^git +FAIL \(not found in PATH\)$"
	assert_match "$OUT" "^jq +PASS"
}

# AC-M0-07: missing jq is reported on its own line.
test_ac_m0_07_missing_jq() {
	setup_repo
	conf_all true
	bin=$(path_without jq)
	RC=0
	(cd "$REPO" && PATH=$bin ./softwary doctor) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^jq +FAIL \(not found in PATH\)$"
	assert_match "$OUT" "^git +PASS"
}

# AC-M0-07: a directory that is not a git repository is reported.
test_ac_m0_07_not_a_git_repository() {
	setup_repo --no-git
	conf_all true
	sw doctor
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^git repository +FAIL \(not a git repository\)$"
}

# AC-M0-07: every UNSET required key is reported by name.
test_ac_m0_07_unset_keys() {
	setup_repo
	sw doctor
	assert_eq "$RC" 2 "exit code"
	for k in $REQUIRED_KEYS; do
		assert_match "$OUT" "^$k +FAIL \(UNSET\)$"
	done
}

# AC-M0-07: unrecognised keys are reported with their line.
test_ac_m0_07_unknown_keys() {
	setup_repo
	conf_all true
	printf 'lnit = true\nformat = true\n' >>"$REPO/.softwary/config/commands.conf"
	sw doctor
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^lnit +FAIL \(unknown key, line 7\)$"
	assert_match "$OUT" "^format +FAIL \(unknown key, line 8\)$"
}

# AC-M0-07: several problems at once are each reported separately.
test_ac_m0_07_problems_reported_separately() {
	setup_repo --no-git
	conf_set lint UNSET
	printf 'lnit = true\n' >>"$REPO/.softwary/config/commands.conf"
	bin=$(path_without jq)
	RC=0
	(cd "$REPO" && PATH=$bin ./softwary doctor) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^jq +FAIL \(not found in PATH\)$"
	assert_match "$OUT" "^git repository +FAIL \(not a git repository\)$"
	assert_match "$OUT" "^lint +FAIL \(UNSET\)$"
	assert_match "$OUT" "^lnit +FAIL \(unknown key, line [0-9]+\)$"
}

# Installation problems: a missing commands.conf is reported.
test_missing_conf_reported() {
	setup_repo
	rm "$REPO/.softwary/config/commands.conf"
	sw doctor
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^commands\.conf +FAIL "
}

run_tests "$0"
