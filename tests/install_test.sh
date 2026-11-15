#!/bin/sh
# Tests for install.sh.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

TEMPLATES="spec.md slice.md review.md adr.md CONTEXT.md system.calm.json"
TEMPLATE_FILES=$(for t in $TEMPLATES; do printf '.softwary/templates/%s ' "$t"; done)
EXPECTED_FILES="softwary .softwary/VERSION .softwary/.gitignore .softwary/bin/softwary
.softwary/lib/config.sh .softwary/lib/verify.sh .softwary/lib/doctor.sh .softwary/config/commands.conf
.softwary/lib/sync.sh .softwary/lib/target.sh .softwary/rules/core.md .softwary/targets/claude-code.sh
.softwary/targets/codex.sh .softwary/targets/cursor.sh .softwary/config/tools.conf
.softwary/config/risk.conf .softwary/hooks/pre-commit .softwary/hooks/pre-push
.softwary/templates/softwary.yml .softwary/templates/CODEOWNERS $TEMPLATE_FILES"

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

# AC-M1-01: rules, targets and a tools.conf with every tool UNSET are installed.
test_ac_m1_01_installs_rules_targets_tools_conf() {
	mkdir "$T/repo"
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || fail "install failed"
	[ -s "$T/repo/.softwary/rules/core.md" ] || fail "core.md missing"
	for t in $TOOLS; do
		[ -f "$T/repo/.softwary/targets/$t.sh" ] || fail "target $t missing"
		assert_match "$T/repo/.softwary/config/tools.conf" "^$t = UNSET$"
	done
}

# AC-M1-01: an existing (project-owned) tools.conf is never overwritten.
test_ac_m1_01_keeps_existing_tools_conf() {
	mkdir "$T/repo"
	sh "$PKG_ROOT/install.sh" "$T/repo" >/dev/null 2>&1 || fail "first install failed"
	printf 'cursor = on\n' >"$T/repo/.softwary/config/tools.conf"
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || fail "second install failed"
	assert_eq "$(cat "$T/repo/.softwary/config/tools.conf")" "cursor = on" "tools.conf"
	assert_match "$OUT" "^  \.softwary/config/tools\.conf \(exists, kept\)$"
}

# AC-M2-01: templates and a risk.conf with an UNSET default are installed;
# no project artifact is created.
test_ac_m2_01_installs_templates_and_risk_conf() {
	mkdir "$T/repo"
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || fail "install failed"
	for t in $TEMPLATES; do
		[ -s "$T/repo/.softwary/templates/$t" ] || fail "template $t missing"
	done
	assert_match "$T/repo/.softwary/config/risk.conf" "^default = UNSET$"
	for p in architecture specs CONTEXT.md; do
		[ ! -e "$T/repo/$p" ] || fail "install created project artifact $p"
	done
}

# AC-M2-01: an existing (project-owned) risk.conf is never overwritten.
test_ac_m2_01_keeps_existing_risk_conf() {
	mkdir "$T/repo"
	sh "$PKG_ROOT/install.sh" "$T/repo" >/dev/null 2>&1 || fail "first install failed"
	printf 'default = R2\n' >"$T/repo/.softwary/config/risk.conf"
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || fail "second install failed"
	assert_eq "$(cat "$T/repo/.softwary/config/risk.conf")" "default = R2" "risk.conf"
	assert_match "$OUT" "^  \.softwary/config/risk\.conf \(exists, kept\)$"
}

# AC-M2-01: the model template fails until it is filled in, then passes.
test_ac_m2_01_model_template() {
	setup_repo --no-model
	mkdir -p "$REPO/architecture/model"
	cp "$REPO/.softwary/templates/system.calm.json" "$REPO/$MODEL_REL"
	sw model validate
	assert_eq "$RC" 1 "exit code for the unfilled template"
	assert_match "$OUT" "is UNSET$"
	jq 'walk(if . == "UNSET" then "x" else . end) | .nodes[0].metadata.risk = "R2"' \
		"$REPO/$MODEL_REL" >"$T/m" && mv "$T/m" "$REPO/$MODEL_REL"
	sw model validate
	assert_eq "$RC" 0 "exit code for the filled template"
}

# AC-M2-01: the spec and slice templates fail until filled in, then pass trace.
test_ac_m2_01_spec_and_slice_templates() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	mkdir -p "$REPO/specs/001-login/slices" "$REPO/tests"
	cp "$REPO/.softwary/templates/spec.md" "$REPO/specs/001-login/spec.md"
	cp "$REPO/.softwary/templates/slice.md" "$REPO/specs/001-login/slices/S1.md"
	sw trace
	assert_eq "$RC" 1 "exit code for unfilled templates"
	sed -e 's/NNN/001/g' -e 's/^title: UNSET$/title: Login/' -e 's/^risk: UNSET$/risk: R1/' \
		-e 's/^status: draft$/status: approved/' -e '/^- <question/d' \
		"$REPO/.softwary/templates/spec.md" >"$REPO/specs/001-login/spec.md"
	sed -e 's/NNN/001/g' -e 's/^goal: UNSET$/goal: Sign in/' \
		"$REPO/.softwary/templates/slice.md" >"$REPO/specs/001-login/slices/S1.md"
	sw trace
	assert_eq "$RC" 0 "exit code for filled templates"
}

# AC-M2-01: the ADR template is read by status once filled in.
test_ac_m2_01_adr_template() {
	setup_repo
	mkdir -p "$REPO/architecture/decisions"
	sed -e 's/NNNN/0001/g' -e 's/^title: UNSET$/title: Use CALM/' \
		"$REPO/.softwary/templates/adr.md" >"$REPO/architecture/decisions/0001-use-calm.md"
	sw status
	assert_match "$OUT" "^ADR 0001 +proposed +Use CALM$"
}

run_tests "$0"
