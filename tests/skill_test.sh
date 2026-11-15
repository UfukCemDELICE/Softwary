#!/bin/sh
# Tests for the setup skill (M3).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

SKILL=$PKG_ROOT/src/skills/setup/SKILL.md

# AC-M3-07: sync distributes the setup skill to the three tools.
test_ac_m3_07_distributed_to_three_tools() {
	setup_repo
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	for d in .claude .cursor .agents; do
		[ -s "$REPO/$d/skills/softwary-setup/SKILL.md" ] || fail "$d/skills/softwary-setup/SKILL.md missing"
	done
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

# AC-M3-07: every ./softwary command in the skill is one the package recognises.
test_ac_m3_07_commands_are_recognised() {
	[ -f "$SKILL" ] || fail "src/skills/setup/SKILL.md missing"
	used=$(awk '{
		s = $0
		while ((i = index(s, "./softwary ")) > 0) {
			s = substr(s, i + 11)
			split(s, w, /[^a-z-]/)
			if (w[1] != "") print w[1]
		}
	}' "$SKILL" | sort -u)
	known=$(sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u)
	[ -n "$used" ] || fail "the skill uses no ./softwary command"
	[ -n "$known" ] || fail "could not read the command list from help"
	for c in $used; do
		printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "the skill uses unknown command: ./softwary $c"
	done
}

# AC-M3-07: the skill names doctor, the ADR template and the proposed status.
test_ac_m3_07_names_doctor_adr_template_and_proposed() {
	assert_contains "$SKILL" "./softwary doctor"
	assert_contains "$SKILL" ".softwary/templates/adr.md"
	assert_contains "$SKILL" "proposed"
}

SKILLS=$PKG_ROOT/src/skills
AGENTS=$PKG_ROOT/src/agents

# AC-V1-08: setup asks for both branches and for the CI install step.
test_ac_v1_08_setup_asks_branches_and_ci_toolchain() {
	assert_contains "$SKILL" "integration_branch"
	assert_contains "$SKILL" "production_branch"
	assert_contains "$SKILL" "Install tools"
	assert_contains "$SKILL" "branches: [UNSET]"
}

# AC-V1-08: branch protection requires the CI check, not a human review.
test_ac_v1_08_setup_branch_protection() {
	assert_contains "$SKILL" "require the \`softwary\` status check"
	assert_contains "$SKILL" "do not require a human review"
	! grep -F "Require review from Code Owners" "$SKILL" >/dev/null || fail "setup still asks for Code Owners review"
}

# AC-V1-08: an empty repository gets no model and is pointed at discover and
# architect; in an existing one the baseline ADR lists each component's paths.
test_ac_v1_08_setup_empty_and_existing_repo() {
	assert_contains "$SKILL" "empty repository"
	assert_contains "$SKILL" "do not draft a model"
	assert_contains "$SKILL" "\`discover\`"
	assert_contains "$SKILL" "\`architect\`"
	assert_contains "$SKILL" ".gitkeep"
	assert_contains "$SKILL" "the paths each component is drawn from"
}

# AC-V1-08: while iterating, implement runs verify --fast; before review the
# full verify. Review no longer assumes main as the base.
test_ac_v1_08_implement_fast_then_full_verify() {
	for f in "$SKILLS/implement/SKILL.md" "$AGENTS/implementer.md"; do
		assert_contains "$f" "./softwary verify --fast"
		assert_contains "$f" "before review"
	done
	for f in "$SKILLS/review/SKILL.md" "$AGENTS/reviewer.md" "$SKILLS/implement/SKILL.md"; do
		! grep -F -e "--base main" -e "(\`main\`" "$f" >/dev/null || fail "${f#"$PKG_ROOT"/} still assumes main"
	done
	assert_contains "$SKILLS/review/SKILL.md" "integration branch"
}

run_tests "$0"
