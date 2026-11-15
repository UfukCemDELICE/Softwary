#!/bin/sh
# Tests for the branch settings and the default base (V1).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# setup_trunk: the integration branch is called trunk; the sample model and
# specs are committed on it and a feature branch is checked out. No main.
setup_trunk() {
	setup_repo
	conf_all true
	conf_set integration_branch trunk
	add_specs
	git -C "$REPO" symbolic-ref HEAD refs/heads/trunk
	commit_all base
	git -C "$REPO" checkout -qb feature
}

# AC-V1-01: doctor reports each missing branch setting on its own line.
test_ac_v1_01_doctor_reports_each_missing_branch() {
	setup_repo
	conf_all true
	conf_del integration_branch
	conf_del production_branch
	sw doctor
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^integration_branch +FAIL \(not set in \.softwary/config/commands\.conf\)$"
	assert_match "$OUT" "^production_branch +FAIL \(not set in \.softwary/config/commands\.conf\)$"
	conf_set production_branch UNSET
	conf_set integration_branch main
	sw doctor
	assert_match "$OUT" "^integration_branch +PASS$"
	assert_match "$OUT" "^production_branch +FAIL \(not set in"
	conf_set production_branch master
	sw doctor
	assert_eq "$RC" 0 "exit code when both are set"
	assert_match "$OUT" "^production_branch +PASS$"
}

# AC-V1-01: a branch setting must be a valid branch name.
test_ac_v1_01_invalid_branch_name() {
	setup_repo
	conf_all true
	conf_set integration_branch 'a..b'
	_ln=$(grep -n '^integration_branch' "$REPO/.softwary/config/commands.conf" | cut -d: -f1)
	sw verify
	assert_eq "$RC" 2 "verify exit code"
	assert_match "$OUT" "^\.softwary/config/commands\.conf:$_ln: invalid branch name 'a\.\.b' for 'integration_branch'$"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "^commands\.conf +FAIL \(\.softwary/config/commands\.conf:$_ln: invalid branch name"
}

# AC-V1-01: without --base, adr, changes and risk use integration_branch;
# --base still wins.
test_ac_v1_01_default_base_is_integration_branch() {
	setup_trunk
	printf ' \n' >>"$REPO/architecture/model/system.calm.json"
	printf 'x\n' >"$REPO/src/app.txt"
	commit_all change
	sw adr
	assert_eq "$RC" 1 "adr exit code"
	assert_match "$OUT" "^architecture/model/system\.calm\.json: no accepted ADR"
	sw changes
	assert_eq "$RC" 1 "changes exit code"
	assert_match "$OUT" "^src/app\.txt: no slice in this change covers it$"
	sw risk 001
	assert_eq "$RC" 0 "risk exit code"
	assert_match "$OUT" "^paths +R1 \(architecture/model/system\.calm\.json: default\)$"
	sw adr --base feature
	assert_eq "$RC" 0 "adr --base exit code"
	sw changes --base feature
	assert_eq "$RC" 0 "changes --base exit code"
}

# AC-V1-01: without --base and without integration_branch: 2, naming the setting.
test_ac_v1_01_unset_branch_exits_2() {
	setup_trunk
	conf_set integration_branch UNSET
	for _c in adr changes "risk 001" verify; do
		# shellcheck disable=SC2086 # split the command and its argument
		sw $_c
		assert_eq "$RC" 2 "$_c exit code"
		assert_match "$OUT" "integration_branch is not set in \.softwary/config/commands\.conf"
	done
	sw adr --base trunk
	assert_eq "$RC" 0 "adr --base exit code"
	sw changes --base trunk
	assert_eq "$RC" 0 "changes --base exit code"
	sw risk 001 --base trunk
	assert_eq "$RC" 0 "risk --base exit code"
}

# AC-V1-01: with commits, doctor reports an integration branch that does not exist.
test_ac_v1_01_doctor_branch_ref_missing() {
	setup_trunk
	conf_set integration_branch develop
	sw doctor
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^integration_branch +FAIL \(branch 'develop' not found\)$"
}

run_tests "$0"
