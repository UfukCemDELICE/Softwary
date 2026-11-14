#!/bin/sh
# AC-M0-10: one command runs every test, and every script passes shellcheck.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck disable=SC2329 # test functions are called by run_tests

# AC-M0-10: every shell script in the package is shellcheck-clean.
test_ac_m0_10_shellcheck_clean() {
	command -v shellcheck >/dev/null || fail "shellcheck is required (it is not optional)"
	(cd "$PKG_ROOT" && shellcheck -s sh -x install.sh src/bin/softwary src/lib/*.sh src/templates/softwary tests/*.sh) \
		>"$OUT" 2>&1 || fail "shellcheck reported problems"
}

# AC-M0-10: tests/run.sh runs every *_test.sh and fails if any of them fails.
test_ac_m0_10_runner_runs_all_and_reports_failure() {
	mkdir "$T/tests"
	cp "$PKG_ROOT/tests/run.sh" "$T/tests/"
	printf 'touch "%s/ran-a"\nexit 1\n' "$T" >"$T/tests/a_test.sh"
	printf 'touch "%s/ran-b"\n' "$T" >"$T/tests/b_test.sh"
	RC=0
	sh "$T/tests/run.sh" >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 1 "exit code with a failing file"
	[ -f "$T/ran-a" ] && [ -f "$T/ran-b" ] || fail "not every test file ran"
	printf 'exit 0\n' >"$T/tests/a_test.sh"
	RC=0
	sh "$T/tests/run.sh" >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code when all pass"
}

run_tests "$0"
