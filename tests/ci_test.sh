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
	# V1: CODEOWNERS is optional (AC-V1-06).
	assert_match "$OUT" "^CODEOWNERS +SKIP \(optional\)$"
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
	# V1: the branches are UNSET until setup fills them in (AC-V1-07).
	assert_match "$f" "branches: \[UNSET\]"
	assert_contains "$f" "fetch-depth: 0"
	# shellcheck disable=SC2016 # literal workflow text, nothing to expand
	assert_contains "$f" 'BASE_REF: ${{ github.base_ref }}'
	# shellcheck disable=SC2016
	assert_contains "$f" './softwary verify --base "origin/$BASE_REF"'
	assert_contains "$f" "run: UNSET"
}

# AC-V1-06: without CODEOWNERS doctor says it is optional and still passes.
test_ac_v1_06_codeowners_optional() {
	setup_repo
	conf_all true
	rm "$REPO/$OWNERS"
	sw doctor
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^CODEOWNERS +SKIP \(optional\)$"
}

# AC-V1-06: a CODEOWNERS that exists is still checked for coverage and UNSET.
test_ac_v1_06_codeowners_checked_when_present() {
	setup_repo
	conf_all true
	printf '* UNSET\n' | write_owners
	sw doctor
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^CODEOWNERS +FAIL \(owner is UNSET \(line 1\)\)$"
	printf '/specs/ @a\n' | write_owners
	sw doctor
	assert_eq "$RC" 2 "exit code with partial coverage"
	assert_match "$OUT" "^CODEOWNERS +FAIL \(does not cover architecture/\)$"
}

# AC-V1-07: the template leaves both trigger branches UNSET; a pull request is
# verified against its base, a push with the plain verify.
test_ac_v1_07_template_branches_unset() {
	f=$PKG_ROOT/src/templates/github/softwary.yml
	# V7: the pull request branches carry the production branch too (AC-V7-10).
	assert_eq "$(awk '/^  pull_request:/ { getline; print; exit }' "$f")" "    branches: [UNSET, UNSET]" "pull_request branches"
	assert_eq "$(awk '/^  push:/ { getline; print; exit }' "$f")" "    branches: [UNSET]" "push branches"
	# shellcheck disable=SC2016 # literal workflow text, nothing to expand
	assert_contains "$f" 'run: ./softwary verify --base "origin/$BASE_REF"'
	assert_match "$f" "^        run: \./softwary verify$"
}

# AC-V1-07: doctor reports every UNSET line of the workflow on its own line.
test_ac_v1_07_doctor_reports_each_unset_line() {
	setup_repo
	conf_all true
	cp "$REPO/.softwary/templates/softwary.yml" "$REPO/$WORKFLOW"
	sw doctor
	assert_eq "$RC" 2 "exit code"
	_n=$(grep -cE "^workflow +FAIL \($WORKFLOW still contains UNSET \(line [0-9]+\)\)$" "$OUT")
	assert_eq "$_n" 3 "UNSET lines reported"
	sed 's/branches: \[UNSET, UNSET\]/branches: [main, master]/; s/branches: \[UNSET\]/branches: [main]/' "$REPO/.softwary/templates/softwary.yml" >"$REPO/$WORKFLOW"
	sw doctor
	assert_eq "$(grep -cE "^workflow +FAIL" "$OUT")" 1 "only the install step left"
}

# AC-V7-10: a pull request to the production branch runs the workflow too: the
# template's pull_request trigger has two branches to fill in, the integration
# and the production branch, and a pull request is verified against its base
# whichever it is.
test_ac_v7_10_pull_request_branches_carry_production() {
	f=$PKG_ROOT/src/templates/github/softwary.yml
	assert_eq "$(awk '/^  pull_request:/ { getline; print; exit }' "$f")" "    branches: [UNSET, UNSET]" "pull_request branches"
	assert_eq "$(awk '/^  push:/ { getline; print; exit }' "$f")" "    branches: [UNSET]" "push branches"
	# shellcheck disable=SC2016 # literal workflow text, nothing to expand
	assert_contains "$f" 'run: ./softwary verify --base "origin/$BASE_REF"'
	setup_repo
	conf_all true
	sed 's/branches: \[UNSET, UNSET\]/branches: [main, UNSET]/; s/branches: \[UNSET\]/branches: [main]/; s/^\( *run: \)UNSET.*$/\1true/' "$REPO/.softwary/templates/softwary.yml" >"$REPO/$WORKFLOW"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code with the production branch UNSET"
	assert_match "$OUT" "^workflow +FAIL \($WORKFLOW still contains UNSET \(line [0-9]+\)\)$"
	sed 's/branches: \[main, UNSET\]/branches: [main, master]/' "$REPO/$WORKFLOW" >"$T/w" && cp "$T/w" "$REPO/$WORKFLOW"
	sw doctor
	assert_eq "$RC" 0 "doctor exit code with both branches"
	assert_match "$OUT" "^workflow +PASS"
	assert_contains "$PKG_ROOT/src/skills/setup/SKILL.md" "branches: [UNSET, UNSET]"
	assert_contains "$PKG_ROOT/src/skills/setup/SKILL.md" "the integration branch and the production branch"
}

# make_pkg DIR VERSION: a copy of the package with the given version.
make_pkg() {
	mkdir -p "$1"
	cp -R "$PKG_ROOT/install.sh" "$PKG_ROOT/VERSION" "$PKG_ROOT/src" "$1/"
	printf '%s\n' "$2" >"$1/VERSION"
}

# AC-V7-10: the workflow of an installed project is the project's own and an
# upgrade does not change it; it says so when the workflow does not name the
# production branch, and says nothing when it does.
test_ac_v7_10_upgrade_says_the_workflow_is_the_projects() {
	setup_repo
	conf_all true
	sed 's/branches: \[main, master\]/branches: [main]/' "$REPO/$WORKFLOW" >"$T/w" && cp "$T/w" "$REPO/$WORKFLOW"
	make_pkg "$T/pkg" "$PKG_VERSION"
	sw upgrade "$T/pkg"
	assert_eq "$RC" 0 "exit code"
	assert_contains "$OUT" "upgrade: $WORKFLOW is the project's file and is not changed: add master to the branches of its pull_request trigger"
	assert_contains "$REPO/$WORKFLOW" "branches: [main]"
	sed 's/branches: \[main\]$/branches: [main, master]/' "$REPO/$WORKFLOW" >"$T/w" && cp "$T/w" "$REPO/$WORKFLOW"
	make_pkg "$T/pkg2" "$NEXT_VERSION"
	sw upgrade "$T/pkg2"
	assert_eq "$RC" 0 "exit code the second time"
	assert_no_match "$OUT" "is the project's file"
}

run_tests "$0"
