#!/bin/sh
# Tests for install.sh.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck disable=SC2329 # test functions are called by run_tests

EXPECTED_FILES="softwary .softwary/VERSION .softwary/.gitignore .softwary/bin/softwary
.softwary/lib/config.sh .softwary/lib/verify.sh .softwary/lib/doctor.sh .softwary/config/commands.conf"

# AC-M0-01: the files to be written are listed before any of them is written.
# Writing is made to fail on purpose; the full list must still be printed.
test_ac_m0_01_lists_files_before_writing() {
	mkdir -p "$T/repo/.softwary"
	: >"$T/repo/.softwary/bin" # a file where a directory must go: writing fails
	RC=0
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || RC=$?
	[ "$RC" -ne 0 ] || fail "install should fail when it cannot write"
	for f in $EXPECTED_FILES; do
		assert_match "$OUT" "^  $f( |$)"
	done
	[ ! -e "$T/repo/softwary" ] || [ ! -e "$T/repo/.softwary/config/commands.conf" ] ||
		fail "install wrote everything despite the error"
}

# AC-M0-01: the list appears before the writing step in a normal run.
test_ac_m0_01_list_precedes_writing_message() {
	mkdir "$T/repo"
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || fail "install failed"
	list_line=$(grep -n '^  softwary$' "$OUT" | cut -d: -f1)
	write_line=$(grep -n '^Writing' "$OUT" | cut -d: -f1)
	[ -n "$list_line" ] && [ -n "$write_line" ] || fail "list or writing message missing"
	[ "$list_line" -lt "$write_line" ] || fail "files listed after writing started"
}

# AC-M0-01: nothing outside the target repo is written (relative target, other cwd).
test_ac_m0_01_writes_only_inside_target() {
	mkdir "$T/repo" "$T/elsewhere" "$T/home" "$T/tmp" "$T/lists"
	: >"$T/lists/marker"
	find "$T" -path "$T/repo" -prune -o -path "$T/lists" -prune -o -print | sort >"$T/lists/before"
	(cd "$T/elsewhere" && HOME="$T/home" TMPDIR="$T/tmp" sh "$PKG_ROOT/install.sh" ../repo) >"$T/lists/out" 2>&1 ||
		fail "install failed: $(cat "$T/lists/out")"
	find "$T" -path "$T/repo" -prune -o -path "$T/lists" -prune -o -print | sort >"$T/lists/after"
	cmp -s "$T/lists/before" "$T/lists/after" || fail "files changed outside target: $(diff "$T/lists/before" "$T/lists/after")"
	changed=$(find "$PKG_ROOT" -path "$PKG_ROOT/.git" -prune -o -newer "$T/lists/marker" -print)
	[ -z "$changed" ] || fail "package files changed: $changed"
	[ -f "$T/repo/softwary" ] || fail "nothing installed into target"
}

# AC-M0-01: .softwary/, the wrapper and commands.conf with every required key UNSET.
test_ac_m0_01_creates_layout_with_unset_keys() {
	mkdir "$T/repo"
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || fail "install failed"
	for f in $EXPECTED_FILES; do
		[ -f "$T/repo/$f" ] || fail "missing $f"
	done
	[ -x "$T/repo/softwary" ] || fail "wrapper not executable"
	conf=$T/repo/.softwary/config/commands.conf
	for k in $REQUIRED_KEYS; do
		assert_match "$conf" "^$k = UNSET$"
	done
	assert_contains "$T/repo/.softwary/.gitignore" "/state/"
	(cd "$T/repo" && ./softwary --help) >/dev/null 2>&1 || fail "wrapper does not run"
}

# AC-M0-01: an existing (project-owned) commands.conf is never overwritten.
test_ac_m0_01_keeps_existing_commands_conf() {
	mkdir "$T/repo"
	sh "$PKG_ROOT/install.sh" "$T/repo" >/dev/null 2>&1 || fail "first install failed"
	printf 'lint = true\n' >"$T/repo/.softwary/config/commands.conf"
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || fail "second install failed"
	assert_eq "$(cat "$T/repo/.softwary/config/commands.conf")" "lint = true" "commands.conf"
	assert_match "$OUT" "^  \.softwary/config/commands\.conf \(exists, kept\)$"
}

# AC-M0-01: a target that is not an existing directory is refused, nothing is created.
test_ac_m0_01_refuses_missing_target() {
	RC=0
	(cd "$T" && sh "$PKG_ROOT/install.sh" "$T/nope") >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code"
	[ ! -e "$T/nope" ] || fail "target was created"
	RC=0
	sh "$PKG_ROOT/install.sh" >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code without argument"
}

run_tests "$0"
