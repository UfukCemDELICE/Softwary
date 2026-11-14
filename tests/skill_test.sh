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

run_tests "$0"
