#!/bin/sh
# Tests for commands.conf parsing (shared by verify and doctor).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# Writes a valid conf whose 8th line is $1 (line 1 is a comment, 2-7 the keys).
conf_with_bad_line_8() {
	{
		printf '# project commands\n'
		for k in $REQUIRED_KEYS; do
			printf '%s = touch ran-%s\n' "$k" "$k"
		done
		printf '%s\n' "$1"
	} | write_conf
}

# expect_malformed LINE: verify and doctor both exit 2 and name line 8; nothing runs.
expect_malformed() {
	conf_with_bad_line_8 "$1"
	for cmd in verify doctor; do
		sw "$cmd"
		assert_eq "$RC" 2 "$cmd exit code for [$1]"
		assert_match "$OUT" "commands\.conf:8: "
	done
	[ -z "$(find "$REPO" -name 'ran-*')" ] || fail "a command ran despite malformed conf"
}

# AC-M0-08: a line without '=' is malformed.
test_ac_m0_08_line_without_equals() {
	setup_repo
	expect_malformed 'lint true'
}

# AC-M0-08: an empty key is malformed.
test_ac_m0_08_empty_key() {
	setup_repo
	expect_malformed ' = true'
}

# AC-M0-08: a key with invalid characters is malformed.
test_ac_m0_08_invalid_key() {
	setup_repo
	expect_malformed 'Run-It = true'
}

# AC-M0-08: an empty value is malformed (decision 1: use UNSET or NONE).
test_ac_m0_08_empty_value() {
	setup_repo
	expect_malformed 'run ='
}

# AC-M0-08: NONE without a reason is malformed.
test_ac_m0_08_none_without_reason() {
	setup_repo
	expect_malformed 'run = NONE:'
	expect_malformed 'run = NONE'
}

# AC-M0-08: a duplicate key is malformed.
test_ac_m0_08_duplicate_key() {
	setup_repo
	expect_malformed 'lint = true'
}

# AC-M0-08: every malformed line is reported, not only the first.
test_ac_m0_08_all_bad_lines_reported() {
	setup_repo
	conf_with_bad_line_8 'oops'
	printf 'again\n' >>"$REPO/.softwary/config/commands.conf"
	sw verify
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "commands\.conf:8: "
	assert_match "$OUT" "commands\.conf:9: "
}

# AC-M0-08: comments, blank lines, indentation and missing spaces are accepted;
# a value may contain '=' and '#'.
test_ac_m0_08_valid_variations_accepted() {
	setup_repo
	{
		printf '# comment\n\n   # indented comment\n'
		printf 'format_check=true\n'
		printf '  lint   =   true  \n'
		# shellcheck disable=SC2016 # $A is expanded by the checked command
		printf 'typecheck = A=1 sh -c '"'"'[ "$A" = 1 ]'"'"' # trailing text\n'
		printf 'test = true\nbuild = true\nsecurity = true\n'
	} | write_conf
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^typecheck +PASS "
}

run_tests "$0"
