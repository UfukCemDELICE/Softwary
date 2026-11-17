#!/bin/sh
# Tests for the scoped checks of V6: `<key>_files` in commands.conf and the
# line `<key> (changed files)` that verify writes after a waived failure.
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

WAIVERS_REL=.softwary/config/waivers.conf

# waived_repo: a repo on main whose lint is red and waived, with a scoped lint
# (check.sh fails on a file that holds XXX) and one commit. Changes are made
# after it: they are the change that verify --base main looks at.
waived_repo() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	conf_set lint false
	conf_set lint_files 'sh check.sh {files}'
	printf 'lint = 2999-12-31: legacy debt\n' >"$REPO/$WAIVERS_REL"
	mkdir -p "$REPO/tests"
	: >"$REPO/tests/.gitkeep"
	cat >"$REPO/check.sh" <<'CHECK'
#!/bin/sh
# prints each argument on a line of args.txt; fails when a file holds XXX
: >args.txt
bad=0
for f in "$@"; do
	printf '%s\n' "$f" >>args.txt
	if grep -q XXX "$f"; then
		echo "XXX in $f"
		bad=1
	fi
done
exit $bad
CHECK
	commit_all base
}

# AC-V6-01: a scoped command without {files} is a configuration error: doctor
# fails on it and verify exits 2 (also with --fast).
test_ac_v6_01_files_placeholder_required() {
	waived_repo
	conf_set lint_files 'sh check.sh'
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "^commands\.conf +FAIL \(.*commands\.conf:[0-9]+: lint_files must contain \{files\}"
	sw verify --base main
	assert_eq "$RC" 2 "verify exit code"
	assert_match "$OUT" "commands\.conf:[0-9]+: lint_files must contain \{files\}"
	sw verify --fast
	assert_eq "$RC" 2 "verify --fast exit code"
	assert_match "$OUT" "commands\.conf:[0-9]+: lint_files must contain \{files\}"
}

# AC-V6-01: NONE: <reason> and UNSET are valid values; the key is known (it is
# not an unknown-key error); a bare NONE is malformed like any other key.
test_ac_v6_01_none_allowed() {
	waived_repo
	conf_set lint_files 'NONE: generated code, nothing to scope'
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_no_match "$OUT" "unknown key"
	sw verify --base main
	assert_eq "$RC" 0 "verify exit code"
	conf_set lint_files UNSET
	sw verify --base main
	assert_eq "$RC" 0 "verify exit code with UNSET"
	conf_set lint_files NONE
	sw verify --base main
	assert_eq "$RC" 2 "verify exit code with a bare NONE"
	assert_match "$OUT" "lint_files' needs a reason"
}

# AC-V6-01: the template explains the keys as comments, one per waivable check.
test_ac_v6_01_template_describes_files_keys() {
	t=$PKG_ROOT/src/templates/commands.conf
	assert_contains "$t" "{files}"
	for k in format_check lint typecheck test build security contract_check arch_check model_check; do
		assert_match "$t" "^# ${k}_files = "
	done
	assert_no_match "$t" "^[a-z_]*_files"
}

# AC-V6-02: a waived and red check runs its scoped command on the changed
# files; the command passes: PASS, and the exit code stays 0.
test_ac_v6_02_scoped_pass() {
	waived_repo
	printf 'clean\n' >"$REPO/tests/new_test.sh"
	sw verify --base main
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^lint +WAIVED \(legacy debt, until 2999-12-31\)$"
	assert_match "$OUT" "^lint \(changed files\) +PASS \([0-9]+s\)$"
	assert_eq "$(cat "$REPO/args.txt")" "tests/new_test.sh" "files given to the command"
	wl=$(grep -n '^lint ' "$OUT" | head -n 1 | cut -d: -f1)
	cl=$(grep -n '^lint (changed files)' "$OUT" | cut -d: -f1)
	assert_eq "$cl" $((wl + 2)) "the scoped line follows the WAIVED line and its log line"
}

# AC-V6-02: the scoped command fails on the changed file: FAIL, red, the end of
# its output and its log.
test_ac_v6_02_scoped_fail() {
	waived_repo
	printf 'XXX\n' >"$REPO/tests/new_test.sh"
	sw verify --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^lint +WAIVED "
	assert_match "$OUT" "^lint \(changed files\) +FAIL \([0-9]+s\)$"
	assert_match "$OUT" "^ +XXX in tests/new_test\.sh$"
	assert_match "$OUT" "log: \.softwary/state/logs/verify-lint-files\.log \(exit 1\)"
	assert_match "$REPO/.softwary/state/logs/verify-lint-files.log" "^XXX in tests/new_test\.sh$"
	assert_match "$OUT" "^verify: .*1 failed"
}

# AC-V6-02: a file that was already there and is changed counts, one that is
# not under src_paths or test_paths does not, a deleted one is not listed.
test_ac_v6_02_changed_set() {
	waived_repo
	mkdir -p "$REPO/src"
	printf 'old\n' >"$REPO/tests/old_test.sh"
	printf 'old\n' >"$REPO/tests/gone_test.sh"
	printf 'old\n' >"$REPO/src/lib.sh"
	commit_all "more"
	printf 'XXX\n' >"$REPO/tests/old_test.sh"
	rm "$REPO/tests/gone_test.sh"
	printf 'XXX\n' >"$REPO/notes.txt"
	sw verify --base main
	assert_match "$OUT" "^lint \(changed files\) +FAIL "
	assert_match "$OUT" "^ +XXX in tests/old_test\.sh$"
	assert_eq "$(cat "$REPO/args.txt")" "tests/old_test.sh" "only the changed file that is there, under the paths"
	assert_no_match "$OUT" "tests/gone_test.sh"
	printf 'XXX\n' >"$REPO/src/lib.sh"
	sw verify --base main
	assert_eq "$(cat "$REPO/args.txt")" "src/lib.sh
tests/old_test.sh" "src and test paths, sorted"
}

# AC-V6-02: no changed file under the paths: SKIP (no changed files), green.
test_ac_v6_02_no_changed_files() {
	waived_repo
	printf 'XXX\n' >"$REPO/notes.txt"
	sw verify --base main
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^lint \(changed files\) +SKIP \(no changed files\)$"
	[ ! -f "$REPO/args.txt" ] || fail "the command ran with nothing to check"
}

# AC-V6-02: NONE: <reason> skips with the reason.
test_ac_v6_02_none_is_skip() {
	waived_repo
	conf_set lint_files 'NONE: the tool only checks a whole project'
	printf 'XXX\n' >"$REPO/tests/new_test.sh"
	sw verify --base main
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^lint \(changed files\) +SKIP \(the tool only checks a whole project\)$"
}

# AC-V6-02: a check that passes (its waiver is no longer needed) and one whose
# waiver has expired do not run the scoped command.
test_ac_v6_02_no_scoped_line_without_a_live_waiver() {
	waived_repo
	printf 'XXX\n' >"$REPO/tests/new_test.sh"
	conf_set lint true
	sw verify --base main
	assert_match "$OUT" "^lint +PASS \([0-9]+s, waiver no longer needed\)$"
	assert_no_match "$OUT" "changed files"
	conf_set lint false
	printf 'lint = 2000-01-01: legacy debt\n' >"$REPO/$WAIVERS_REL"
	sw verify --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^lint +FAIL \([0-9]+s, waiver expired 2000-01-01\)$"
	assert_no_match "$OUT" "changed files"
	[ ! -f "$REPO/args.txt" ] || fail "the scoped command ran"
	# a check with no waiver at all
	: >"$REPO/$WAIVERS_REL"
	sw verify --base main
	assert_no_match "$OUT" "changed files"
}

# AC-V6-02, review focus 1: names with a space, quotes, a dollar sign, a
# semicolon, a backtick or a leading dash reach the command as one argument
# each and run nothing.
test_ac_v6_02_odd_file_names() {
	waived_repo
	: >"$REPO/tests/a b.sh"
	: >"$REPO/tests/it's.sh"
	: >"$REPO/tests/\$(touch pwned).sh"
	: >"$REPO/tests/x;touch pwned2;.sh"
	: >"$REPO/tests/\`touch pwned3\`.sh"
	: >"$REPO/tests/say \"hi\".sh"
	: >"$REPO/tests/-rf.sh"
	mkdir -p "$REPO/tests/-dir"
	: >"$REPO/tests/-dir/t.sh"
	: >"$REPO/-top.sh"
	conf_set src_paths "src -top.sh"
	[ -e "$REPO/src" ] || mkdir "$REPO/src"
	sw verify --base main
	assert_match "$OUT" "^lint \(changed files\) +PASS "
	[ ! -e "$REPO/pwned" ] && [ ! -e "$REPO/pwned2" ] && [ ! -e "$REPO/pwned3" ] || fail "a file name ran a command"
	[ ! -e "$REPO/tests/pwned" ] || fail "a file name ran a command"
	n=$(wc -l <"$REPO/args.txt" | tr -d ' ')
	assert_eq "$n" 9 "one argument per file"
	assert_contains "$REPO/args.txt" "tests/a b.sh"
	assert_contains "$REPO/args.txt" "tests/it's.sh"
	assert_contains "$REPO/args.txt" 'tests/$(touch pwned).sh'
	assert_contains "$REPO/args.txt" 'tests/say "hi".sh'
	# a name that starts with a dash is not an option: it is given as ./name
	assert_contains "$REPO/args.txt" "./-top.sh"
	assert_no_match "$REPO/args.txt" "^-"
}

# AC-V6-02: a command with {files} twice gets the list twice; the command
# runs from the repo root.
test_ac_v6_02_placeholder_twice_and_root() {
	waived_repo
	conf_set lint_files 'echo {files} {files} >twice.txt; pwd >cwd.txt'
	printf 'x\n' >"$REPO/tests/t.sh"
	mkdir -p "$REPO/sub"
	(cd "$REPO/sub" && ../softwary verify --base main) >"$OUT" 2>&1 || fail "verify failed"
	assert_eq "$(cat "$REPO/twice.txt")" "tests/t.sh tests/t.sh" "both placeholders"
	assert_eq "$(cat "$REPO/cwd.txt")" "$(cd "$REPO" && pwd -P)" "the command's directory"
}

# AC-V6-02: a waived check with no scoped key says so; the check is not run.
test_ac_v6_02_unset_files_key_skips() {
	waived_repo
	conf_del lint_files
	printf 'XXX\n' >"$REPO/tests/new_test.sh"
	sw verify --base main
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^lint \(changed files\) +SKIP \(lint_files is not set\)$"
}

# AC-V6-03: --fast does the same against the integration branch, for format,
# lint and type checks; without a branch to compare with it is SKIP (no base).
test_ac_v6_03_fast_uses_integration_branch() {
	waived_repo
	printf 'XXX\n' >"$REPO/tests/new_test.sh"
	sw verify --fast
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^lint +WAIVED "
	assert_match "$OUT" "^lint \(changed files\) +FAIL "
	assert_match "$OUT" "^ +XXX in tests/new_test\.sh$"
	# only the three static checks have a scoped line in --fast
	conf_set test false
	conf_set test_files 'sh check.sh {files}'
	printf 'lint = 2999-12-31: legacy debt\ntest = 2999-12-31: slow suite\n' >"$REPO/$WAIVERS_REL"
	sw verify --fast
	assert_no_match "$OUT" "^test "
	conf_set integration_branch UNSET
	sw verify --fast
	assert_eq "$RC" 0 "exit code without an integration branch"
	assert_match "$OUT" "^lint \(changed files\) +SKIP \(no base\)$"
	conf_set integration_branch nosuchbranch
	sw verify --fast
	assert_match "$OUT" "^lint \(changed files\) +SKIP \(no base\)$"
}

# AC-V6-03: verify without a flag does not run the scoped command and says so.
test_ac_v6_03_plain_verify_skips() {
	waived_repo
	printf 'XXX\n' >"$REPO/tests/new_test.sh"
	sw verify
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^lint +WAIVED "
	assert_match "$OUT" "^lint \(changed files\) +SKIP \(no base\)$"
	[ ! -f "$REPO/args.txt" ] || fail "the scoped command ran without --base"
}

# AC-V6-03: the scoped check counts in the summary like any other.
test_ac_v6_03_summary_counts() {
	waived_repo
	printf 'XXX\n' >"$REPO/tests/new_test.sh"
	sw verify --base main
	assert_match "$OUT" "^verify: [0-9]+ passed, 1 failed, [0-9]+ skipped, 1 waived$"
}

run_tests "$0"
