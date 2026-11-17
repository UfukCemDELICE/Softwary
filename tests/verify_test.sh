#!/bin/sh
# Tests for ./softwary verify.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# AC-M0-02: a fresh install has every required key UNSET: exit 2, keys listed by name.
test_ac_m0_02_unset_keys_exit_2_and_listed() {
	setup_repo
	sw verify
	assert_eq "$RC" 2 "exit code"
	for k in $REQUIRED_KEYS; do
		assert_match "$OUT" "^UNSET +$k$"
	done
}

# AC-M0-02: only the UNSET keys are listed, and no command runs.
test_ac_m0_02_lists_only_unset_keys_and_runs_nothing() {
	setup_repo
	conf_all 'touch ran-%k'
	conf_set lint UNSET
	sw verify
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^UNSET +lint$"
	assert_no_match "$OUT" "^UNSET +(format_check|typecheck|test|build|security)$"
	[ -z "$(find "$REPO" -name 'ran-*')" ] || fail "a command ran despite UNSET key"
}

# AC-M0-02: a required key missing from the file counts as UNSET.
test_ac_m0_02_absent_key_counts_as_unset() {
	setup_repo
	conf_all true
	conf_del security
	sw verify
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^UNSET +security$"
}

# AC-M0-03: all pass: one PASS line per check with name and duration; exit 0.
test_ac_m0_03_all_pass_one_line_each() {
	setup_repo
	conf_all true
	sw verify
	assert_eq "$RC" 0 "exit code"
	for k in $REQUIRED_KEYS; do
		assert_match "$OUT" "^$k +PASS \([0-9]+s\)$"
		assert_eq "$(grep -c "^$k " "$OUT")" 1 "lines for $k"
	done
}

# AC-M0-03: the duration is measured.
test_ac_m0_03_duration_is_measured() {
	setup_repo
	conf_all true
	conf_set test 'sleep 1'
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^test +PASS \([12]s\)$"
}

# AC-M0-03: checks run from the repo root, in cheap-to-expensive order.
test_ac_m0_03_runs_in_order_from_repo_root() {
	setup_repo
	conf_all 'echo %k >>order.txt'
	mkdir "$REPO/sub"
	(cd "$REPO/sub" && ../softwary verify) >"$OUT" 2>&1 || fail "verify failed"
	assert_eq "$(tr '\n' ' ' <"$REPO/order.txt")" "format_check lint typecheck test build security " "order"
}

# AC-M0-04: a failing check prints FAIL and the tail of its output, logs the
# full output, keeps running the remaining checks and exits 1.
test_ac_m0_04_failure_reported_and_others_continue() {
	setup_repo
	conf_all 'touch ran-%k'
	# shellcheck disable=SC2016 # expanded by the checked command, not here
	conf_set lint 'i=1; while [ $i -le 30 ]; do echo line$i; i=$((i+1)); done; exit 1'
	sw verify
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^lint +FAIL \([0-9]+s\)$"
	assert_match "$OUT" "^ +line30$"
	assert_match "$OUT" "^ +line11$"
	assert_no_match "$OUT" "^ +line10$"
	assert_no_match "$OUT" "^ +line1$"
	assert_match "$OUT" "log: \.softwary/state/logs/verify-lint\.log"
	log=$REPO/.softwary/state/logs/verify-lint.log
	[ -f "$log" ] || fail "log file missing"
	assert_match "$log" "^line1$"
	assert_match "$log" "^line30$"
	for k in typecheck test build security; do
		[ -f "$REPO/ran-$k" ] || fail "$k did not run after lint failed"
		assert_match "$OUT" "^$k +PASS "
	done
}

# AC-M0-04: several failures are all reported; exit is still 1.
test_ac_m0_04_multiple_failures() {
	setup_repo
	conf_all true
	conf_set lint false
	conf_set build 'exit 3'
	sw verify
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^lint +FAIL "
	assert_match "$OUT" "^build +FAIL "
	[ -f "$REPO/.softwary/state/logs/verify-build.log" ] || fail "build log missing"
}

# AC-M0-05: NONE: <reason> is reported as SKIP (<reason>) and is not a failure.
test_ac_m0_05_none_is_skip_with_reason() {
	setup_repo
	conf_all true
	conf_set security 'NONE: no deps'
	conf_del lint
	printf 'lint =   NONE:  linter not chosen yet  \n' >>"$REPO/.softwary/config/commands.conf"
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^security +SKIP \(no deps\)$"
	assert_match "$OUT" "^lint +SKIP \(linter not chosen yet\)$"
}

# Decision 4: optional checks that are not configured are shown as skipped, not hidden.
test_optional_checks_shown_as_skipped() {
	setup_repo
	conf_all true
	printf 'contract_check = UNSET\n' >>"$REPO/.softwary/config/commands.conf"
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^contract_check +SKIP \(not configured\)$"
	assert_match "$OUT" "^arch_check +SKIP \(not configured\)$"
}

# Decision 4: configured optional checks run like any other check.
test_optional_checks_run_when_configured() {
	setup_repo
	conf_all true
	printf 'arch_check = false\nrun = touch ran-run\n' >>"$REPO/.softwary/config/commands.conf"
	sw verify
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^arch_check +FAIL "
	[ ! -f "$REPO/ran-run" ] || fail "verify must not execute run"
}

# AC-M0-06: --fast runs only format_check, lint and typecheck.
test_ac_m0_06_fast_runs_only_static_checks() {
	setup_repo
	conf_all 'touch ran-%k'
	printf 'contract_check = touch ran-contract_check\narch_check = touch ran-arch_check\n' \
		>>"$REPO/.softwary/config/commands.conf"
	sw verify --fast
	assert_eq "$RC" 0 "exit code"
	for k in format_check lint typecheck; do
		[ -f "$REPO/ran-$k" ] || fail "$k did not run"
		assert_match "$OUT" "^$k +PASS "
	done
	for k in test build security contract_check arch_check; do
		[ ! -f "$REPO/ran-$k" ] || fail "$k ran in --fast"
		assert_no_match "$OUT" "^$k "
	done
}

# AC-M0-06 / decision 6: --fast only requires the keys it runs.
test_ac_m0_06_fast_ignores_unset_slow_keys() {
	setup_repo
	conf_all true
	conf_set test UNSET
	sw verify --fast
	assert_eq "$RC" 0 "exit code with test UNSET"
	conf_set lint UNSET
	sw verify --fast
	assert_eq "$RC" 2 "exit code with lint UNSET"
	assert_match "$OUT" "^UNSET +lint$"
}

# Decision 2: an unknown key stops verify with exit 2 (a typo must not hide a check).
test_unknown_key_exits_2() {
	setup_repo
	conf_all true
	printf 'lnit = true\n' >>"$REPO/.softwary/config/commands.conf"
	sw verify
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^UNKNOWN +lnit \(line 11\)$"
}

# A missing commands.conf is a configuration error.
test_missing_conf_exits_2() {
	setup_repo
	rm "$REPO/.softwary/config/commands.conf"
	sw verify
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "commands.conf"
}

# Unknown commands and options are usage errors.
test_usage_errors_exit_2() {
	setup_repo
	conf_all true
	sw verify --slow
	assert_eq "$RC" 2 "exit code for unknown option"
	sw frobnicate
	assert_eq "$RC" 2 "exit code for unknown command"
}

# AC-M2-10: the package checks run first, in order sync, model, views, trace.
test_ac_m2_10_package_checks_in_order() {
	setup_repo
	conf_all true
	add_specs
	sw verify
	assert_eq "$RC" 0 "exit code"
	order=$(grep -E '^[a-z_]+ +(PASS|FAIL|SKIP)' "$OUT" | awk '{ print $1 }' | head -n 7 | tr '\n' ' ')
	assert_eq "$order" "sync model views trace adr changes format_check " "order"
}

# AC-M2-10: without a model verify stops with 2, names the template and runs nothing.
test_ac_m2_10_missing_model_exits_2() {
	setup_repo --no-model
	conf_all 'touch ran-%k'
	sw verify
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "architecture/model/system.calm.json not found"
	assert_contains "$OUT" ".softwary/templates/system.calm.json"
	[ -z "$(find "$REPO" -name 'ran-*')" ] || fail "a command ran without a model"
	sw verify --fast
	assert_eq "$RC" 0 "--fast does not need the model"
}

# AC-M2-10: an invalid model, a stale view and a trace problem each fail their check.
test_ac_m2_10_package_check_failures() {
	setup_repo
	conf_all true
	add_specs
	jq '.nodes[0].name = "Customer"' "$REPO/$MODEL_REL" >"$T/m" && mv "$T/m" "$REPO/$MODEL_REL"
	fm_set "$REPO/specs/001-login/slices/S2.md" depends_on S9
	sw verify
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^model +PASS "
	assert_match "$OUT" "^views +FAIL "
	assert_match "$OUT" "^trace +FAIL "
	assert_match "$OUT" "unknown slice 'S9'"
	printf '{"nodes": []}\n' >"$REPO/$MODEL_REL"
	sw verify
	assert_eq "$RC" 1 "exit code for an invalid model"
	assert_match "$OUT" "^model +FAIL "
}

# setup_branch: the sample specs and a src/ file committed on main (the
# integration branch), a feature branch checked out.
setup_branch() {
	setup_repo
	conf_all true
	add_specs
	printf 'v1\n' >"$REPO/src/app.txt"
	commit_all base
	git -C "$REPO" checkout -qb feature
}

# AC-V1-02: bare verify runs adr and changes right after trace, before the
# project's checks.
test_ac_v1_02_bare_verify_runs_adr_and_changes_after_trace() {
	setup_branch
	sw verify
	assert_eq "$RC" 0 "exit code"
	order=$(grep -E '^[a-z_]+ +(PASS|FAIL|SKIP)' "$OUT" | awk '{ print $1 }' | head -n 7 | tr '\n' ' ')
	assert_eq "$order" "sync model views trace adr changes format_check " "order"
}

# AC-V1-02: bare verify gates the change against the integration branch.
test_ac_v1_02_bare_verify_gates_against_integration_branch() {
	setup_branch
	printf 'v2\n' >"$REPO/src/app.txt"
	printf ' \n' >>"$REPO/$MODEL_REL"
	commit_all change
	sw verify
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^adr +FAIL "
	assert_match "$OUT" "^changes +FAIL "
	assert_match "$OUT" "src/app\.txt: no slice in this change covers it"
}

# AC-V1-02: before the first commit adr and changes are skipped, in verify
# and on their own.
test_ac_v1_02_no_commits_yet() {
	setup_repo
	conf_all true
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^adr +SKIP \(no commits yet\)$"
	assert_match "$OUT" "^changes +SKIP \(no commits yet\)$"
	for _c in adr changes; do
		sw "$_c"
		assert_eq "$RC" 0 "$_c exit code"
		assert_match "$OUT" "^$_c: no commits yet$"
	done
	conf_set test false
	sw verify
	assert_eq "$RC" 1 "exit code follows the project's checks"
}

# AC-V1-02: with commits, a missing integration branch stops verify with 2.
test_ac_v1_02_branch_missing_exits_2() {
	setup_branch
	conf_set integration_branch develop
	sw verify
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "base 'develop' not found"
}

# AC-V1-02: --fast runs neither, and needs no branch setting.
test_ac_v1_02_fast_skips_both() {
	setup_branch
	printf 'v2\n' >"$REPO/src/app.txt"
	sw verify --fast
	assert_eq "$RC" 0 "exit code"
	assert_no_match "$OUT" "^(adr|changes) "
	conf_del integration_branch
	sw verify --fast
	assert_eq "$RC" 0 "exit code without integration_branch"
}

# AC-V1-02: on the integration branch itself only uncommitted changes count.
test_ac_v1_02_on_integration_branch_itself() {
	setup_branch
	git -C "$REPO" checkout -q main
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^adr +PASS "
	assert_match "$OUT" "^changes +PASS "
	printf 'v3\n' >"$REPO/src/app.txt"
	sw verify
	assert_eq "$RC" 1 "exit code with an uncommitted source change"
	assert_match "$OUT" "^changes +FAIL "
}

run_tests "$0"
