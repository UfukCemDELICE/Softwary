#!/bin/sh
# Tests for the CI workflow and CODEOWNERS templates and their doctor checks (M3).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

WORKFLOW=.github/workflows/softwary.yml
OWNERS=.github/CODEOWNERS

# write_owners: replaces .github/CODEOWNERS with stdin.
write_owners() {
	mkdir -p "$REPO/.github"
	cat >"$REPO/$OWNERS"
}

# AC-M3-05: install places both templates under .softwary/templates/ and never writes .github/.
test_ac_m3_05_install_places_templates_not_github() {
	mkdir "$T/repo"
	sh "$PKG_ROOT/install.sh" "$T/repo" >"$OUT" 2>&1 || fail "install failed"
	[ -s "$T/repo/.softwary/templates/softwary.yml" ] || fail "workflow template missing"
	[ -s "$T/repo/.softwary/templates/CODEOWNERS" ] || fail "CODEOWNERS template missing"
	[ ! -e "$T/repo/.github" ] || fail "install wrote .github/"
}

# AC-M3-05: doctor reports the missing workflow and CODEOWNERS on separate lines.
test_ac_m3_05_doctor_reports_missing_files() {
	setup_repo --no-sync
	sw doctor
	assert_match "$OUT" "^workflow +FAIL \($WORKFLOW not found; copy \.softwary/templates/softwary\.yml\)$"
	assert_match "$OUT" "^CODEOWNERS +FAIL \($OWNERS not found; copy \.softwary/templates/CODEOWNERS\)$"
}

# AC-M3-05: the templates as installed still contain UNSET and fail on separate lines.
test_ac_m3_05_unset_templates_fail() {
	setup_repo --no-sync
	mkdir -p "$REPO/.github/workflows"
	cp "$REPO/.softwary/templates/softwary.yml" "$REPO/$WORKFLOW"
	cp "$REPO/.softwary/templates/CODEOWNERS" "$REPO/$OWNERS"
	sw doctor
	assert_match "$OUT" "^workflow +FAIL \($WORKFLOW still contains UNSET \(line [0-9]+\)\)$"
	assert_match "$OUT" "^CODEOWNERS +FAIL \(owner is UNSET \(line [0-9]+\)\)$"
	assert_no_match "$OUT" "^CODEOWNERS +FAIL \(does not cover"
}

# AC-M3-05: filled-in templates pass.
test_ac_m3_05_filled_templates_pass() {
	setup_repo
	conf_all true
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_match "$OUT" "^workflow +PASS"
	assert_match "$OUT" "^CODEOWNERS +PASS"
}

# AC-M3-05: every protected path must be covered by an owned pattern; comments
# are ignored; ** and * forms cover; a pattern without an owner covers nothing.
test_ac_m3_05_codeowners_coverage() {
	setup_repo
	conf_all true
	printf '/specs/ @a\n/architecture/ @a\n' | write_owners
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "^CODEOWNERS +FAIL \(does not cover \.softwary/config/\)$"
	assert_match "$OUT" "^CODEOWNERS +FAIL \(does not cover \.github/\)$"
	assert_no_match "$OUT" "does not cover (specs|architecture)/"
	printf '# owner: UNSET\nspecs/** @a\narchitecture @a\n/.softwary/config/ @b @org/team\n/.github/ @a\n' | write_owners
	sw doctor
	assert_match "$OUT" "^CODEOWNERS +PASS"
	printf '* @a\n' | write_owners
	sw doctor
	assert_match "$OUT" "^CODEOWNERS +PASS"
	printf '/specs/\n/architecture/ @a\n/.softwary/config/ @a\n/.github/ @a\n' | write_owners
	sw doctor
	assert_match "$OUT" "^CODEOWNERS +FAIL \(does not cover specs/\)$"
}

# AC-M3-05: as on GitHub, the last matching line decides: a later pattern
# without an owner removes the owner a wider pattern gave.
test_ac_m3_05_codeowners_last_match_wins() {
	setup_repo
	conf_all true
	printf '* @a\n/specs/\n' | write_owners
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "^CODEOWNERS +FAIL \(does not cover specs/\)$"
	assert_no_match "$OUT" "does not cover (architecture|\.softwary/config|\.github)/"
	printf '/specs/\n* @a\n' | write_owners
	sw doctor
	assert_match "$OUT" "^CODEOWNERS +PASS"
	printf '/specs/ @a\n*\n/architecture/ @a\n/.softwary/config/ @a\n/.github/ @a\n' | write_owners
	sw doctor
	assert_match "$OUT" "^CODEOWNERS +FAIL \(does not cover specs/\)$"
}

# AC-M3-05: a comment mentioning UNSET in the workflow is not a problem.
test_ac_m3_05_workflow_comment_is_not_unset() {
	setup_repo
	conf_all true
	printf '# was UNSET\n' >>"$REPO/$WORKFLOW"
	sw doctor
	assert_match "$OUT" "^workflow +PASS"
}

# AC-M3-06: runs on pull requests and pushes to main, checks out the full
# history and verifies a pull request against its base.
test_ac_m3_06_workflow_triggers_and_checkout() {
	f=$PKG_ROOT/src/templates/github/softwary.yml
	assert_match "$f" "^  pull_request:"
	assert_match "$f" "^  push:"
	assert_match "$f" "branches: \[main\]"
	assert_contains "$f" "fetch-depth: 0"
	# shellcheck disable=SC2016 # literal workflow text, nothing to expand
	assert_contains "$f" 'BASE_REF: ${{ github.base_ref }}'
	# shellcheck disable=SC2016
	assert_contains "$f" './softwary verify --base "origin/$BASE_REF"'
	assert_contains "$f" "run: UNSET"
}

run_tests "$0"
