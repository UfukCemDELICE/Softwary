#!/bin/sh
# Tests for time-limited waivers in .softwary/config/waivers.conf (V1).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

WAIVERS_REL=.softwary/config/waivers.conf

# write_waivers: replaces the repo's waivers.conf with stdin.
write_waivers() {
	cat >"$REPO/$WAIVERS_REL"
}

# AC-V1-03: a failing check with a waiver that has not expired is WAIVED and
# does not change the exit code.
test_ac_v1_03_active_waiver_waives_failure() {
	setup_repo
	conf_all true
	conf_set security false
	printf 'security = 2999-12-31: CVE triage\n' | write_waivers
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^security +WAIVED \(CVE triage, until 2999-12-31\)$"
	assert_match "$OUT" "^verify: .*0 failed, .*1 waived$"
}

# AC-V1-03: an expired waiver leaves the FAIL and says so.
test_ac_v1_03_expired_waiver_keeps_fail() {
	setup_repo
	conf_all true
	conf_set security false
	printf 'security = 2000-01-01: CVE triage\n' | write_waivers
	sw verify
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^security +FAIL \(.*waiver expired 2000-01-01\)$"
}

# AC-V1-03: a passing check that still has a waiver says it is not needed.
test_ac_v1_03_passing_check_with_waiver() {
	setup_repo
	conf_all true
	printf 'security = 2999-12-31: CVE triage\n' | write_waivers
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^security +PASS \(.*waiver no longer needed\)$"
}

# AC-V1-03: waivers apply in --fast as well.
test_ac_v1_03_waiver_applies_in_fast() {
	setup_repo
	conf_all true
	conf_set lint false
	printf 'lint = 2999-12-31: new linter rules\n' | write_waivers
	sw verify --fast
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^lint +WAIVED \(new linter rules, until 2999-12-31\)$"
}

# AC-V1-04: every invalid line is reported with its number and verify exits 2,
# in --fast too. A leap day in a leap year and a ':' in the reason are valid.
test_ac_v1_04_invalid_waivers_exit_2_with_line() {
	setup_repo
	conf_all true
	write_waivers <<'EOF'
# comment
lint
test = 2026-02-29: not a leap year
build = 2026-13-01: month 13
security = 2026-1-01: short month
format_check = 2999-01-01:
typecheck = 2999-01-01: first
typecheck = 2999-01-01: again
deploy_check = 2999-01-01: unknown key
trace = 2999-01-01: package check
contract_check = 2999-01-01
EOF
	for _m in "" --fast; do
		# shellcheck disable=SC2086 # an empty mode is no argument
		sw verify $_m
		assert_eq "$RC" 2 "exit code ($_m)"
		assert_match "$OUT" "^$WAIVERS_REL:2: malformed line"
		assert_match "$OUT" "^$WAIVERS_REL:3: invalid date '2026-02-29'"
		assert_match "$OUT" "^$WAIVERS_REL:4: invalid date '2026-13-01'"
		assert_match "$OUT" "^$WAIVERS_REL:5: invalid date '2026-1-01'"
		assert_match "$OUT" "^$WAIVERS_REL:6: 'format_check' needs a reason"
		assert_match "$OUT" "^$WAIVERS_REL:8: malformed line: duplicate key 'typecheck' \(first on line 7\)$"
		assert_match "$OUT" "^$WAIVERS_REL:9: unknown key 'deploy_check'"
		assert_match "$OUT" "^$WAIVERS_REL:10: 'trace' is a package check and cannot be waived$"
		assert_match "$OUT" "^$WAIVERS_REL:11: malformed line"
	done
	write_waivers <<'EOF'
test = 2028-02-29: tool X: broken on CI
EOF
	conf_set test false
	sw verify
	assert_eq "$RC" 0 "exit code with a valid leap day"
	assert_match "$OUT" "^test +WAIVED \(tool X: broken on CI, until 2028-02-29\)$"
}

# AC-V1-04: doctor shows each waiver and each expired one on its own line;
# an expired waiver is a problem, a malformed file is reported by line.
test_ac_v1_04_doctor_lists_waivers() {
	setup_repo
	conf_all true
	sw doctor
	assert_eq "$RC" 0 "exit code without waivers"
	assert_match "$OUT" "^waivers +PASS \(none\)$"
	write_waivers <<'EOF'
security = 2999-12-31: CVE triage
lint = 2000-01-01: old rules
EOF
	sw doctor
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^waiver security +WAIVED \(CVE triage, until 2999-12-31\)$"
	assert_match "$OUT" "^waiver lint +FAIL \(expired 2000-01-01: old rules\)$"
	assert_match "$OUT" "^doctor: 1 problem\(s\) found$"
	printf 'lint\n' | write_waivers
	sw doctor
	assert_eq "$RC" 2 "exit code for a malformed file"
	assert_match "$OUT" "^waivers +FAIL \($WAIVERS_REL:1: malformed line"
}

# AC-V1-04: install.sh places an empty waivers.conf; install.sh and upgrade
# keep an existing one.
test_ac_v1_04_install_and_upgrade_keep_waivers() {
	setup_repo
	[ -f "$REPO/$WAIVERS_REL" ] || fail "install.sh did not place waivers.conf"
	assert_no_match "$REPO/$WAIVERS_REL" "^[^#]"
	printf 'security = 2999-12-31: kept\n' | write_waivers
	sh "$PKG_ROOT/install.sh" "$REPO" >"$T/install.out" 2>&1 || fail "install.sh failed"
	assert_contains "$REPO/$WAIVERS_REL" "kept"
	mkdir -p "$T/pkg"
	cp -R "$PKG_ROOT/install.sh" "$PKG_ROOT/VERSION" "$PKG_ROOT/src" "$T/pkg/"
	printf '9.9.9\n' >"$T/pkg/VERSION"
	sw upgrade "$T/pkg"
	assert_eq "$RC" 0 "upgrade exit code"
	assert_contains "$REPO/$WAIVERS_REL" "kept"
}

run_tests "$0"
