#!/bin/sh
# Tests for tools.conf handling in sync, verify and doctor (M1).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# write_tools LINES: replaces tools.conf with LINES (printf format, no args).
write_tools() {
	# shellcheck disable=SC2059 # the argument is the format on purpose
	printf "$1" >"$REPO/.softwary/config/tools.conf"
}

# expect_tools_error PATTERN: sync and verify both exit 2 and print PATTERN.
expect_tools_error() {
	for cmd in sync verify; do
		sw "$cmd"
		assert_eq "$RC" 2 "$cmd exit code"
		assert_match "$OUT" "$1"
	done
}

# AC-M1-09: a malformed tools.conf line is reported with its number.
test_ac_m1_09_malformed_line() {
	setup_repo
	conf_all true
	write_tools 'claude-code = off\ncodex = off\ncursor = off\ncursor on\n'
	expect_tools_error "tools\.conf:4: malformed line"
}

# AC-M1-09: an unknown tool is reported with its line number.
test_ac_m1_09_unknown_tool() {
	setup_repo
	conf_all true
	write_tools 'claude-code = off\ncodex = off\ncursor = off\nvim = on\n'
	expect_tools_error "tools\.conf:4: unknown tool 'vim'"
}

# AC-M1-09: an UNSET tool is reported with its line number.
test_ac_m1_09_unset_tool() {
	setup_repo
	conf_all true
	write_tools 'claude-code = off\ncodex = off\ncursor = UNSET\n'
	expect_tools_error "tools\.conf:3: 'cursor' is UNSET"
}

# AC-M1-09: a value other than on or off is reported with its line number.
test_ac_m1_09_invalid_value() {
	setup_repo
	conf_all true
	write_tools 'claude-code = off\ncodex = yes\ncursor = off\n'
	expect_tools_error "tools\.conf:2: invalid value 'yes' for 'codex'"
}

# AC-M1-09: a tool missing from tools.conf is reported.
test_ac_m1_09_missing_tool() {
	setup_repo
	conf_all true
	write_tools 'claude-code = off\ncodex = off\n'
	expect_tools_error "'cursor' is missing"
}

# AC-M1-09: a fresh install has every tool UNSET, so sync refuses to run.
test_ac_m1_09_fresh_install_is_unset() {
	setup_repo --no-sync
	sw sync
	assert_eq "$RC" 2 "exit code"
	for t in $TOOLS; do
		assert_match "$OUT" "'$t' is UNSET"
	done
}

# AC-M1-09: doctor reports each tools.conf problem on its own line.
test_ac_m1_09_doctor_reports_tools_problems() {
	setup_repo
	conf_all true
	write_tools 'claude-code = off\ncodex = off\ncursor = UNSET\nvim = on\n'
	sw doctor
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^tools\.conf +FAIL \(.*tools\.conf:3: 'cursor' is UNSET"
	assert_match "$OUT" "^tools\.conf +FAIL \(.*tools\.conf:4: unknown tool 'vim'"
}

# AC-M1-09: doctor reports each out-of-date generated file on its own line.
test_ac_m1_09_doctor_reports_stale_files() {
	setup_repo
	conf_all true
	sw doctor
	assert_eq "$RC" 0 "exit code when synced"
	assert_match "$OUT" "^generated +PASS"
	add_sources
	tools_set cursor on
	sw doctor
	assert_eq "$RC" 2 "exit code when out of date"
	assert_match "$OUT" "^generated +FAIL \(missing \.cursor/skills/softwary-hello/SKILL\.md\)$"
	assert_match "$OUT" "^generated +FAIL \(missing \.cursor/agents/helper\.md\)$"
}

run_tests "$0"
