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

V2_SKILLS="define blueprint plan run"
V2_AGENTS="approver advisor"

# commands_in FILE...: the ./softwary command words the files use.
commands_in() {
	awk '{
		s = $0
		while ((i = index(s, "./softwary ")) > 0) {
			s = substr(s, i + 11)
			split(s, w, /[^a-z-]/)
			if (w[1] != "") print w[1]
		}
	}' "$@" | sort -u
}

# AC-V2-15: the four skills and the two agents reach the three tools, stay
# within 80 lines and name only commands that help lists.
test_ac_v2_15_distributed_and_short() {
	setup_repo
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	known=$(sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u)
	for s in $V2_SKILLS; do
		for d in .claude .cursor .agents; do
			[ -s "$REPO/$d/skills/softwary-$s/SKILL.md" ] || fail "$d/skills/softwary-$s/SKILL.md missing"
		done
	done
	for a in $V2_AGENTS spec-analyst implementer reviewer; do
		for d in .claude .cursor; do
			[ -s "$REPO/$d/agents/$a.md" ] || fail "$d/agents/$a.md missing"
		done
		[ -s "$REPO/.codex/agents/$a.toml" ] || fail ".codex/agents/$a.toml missing"
	done
	files=
	for s in $V2_SKILLS; do files="$files $SKILLS/$s/SKILL.md"; done
	for a in $V2_AGENTS spec-analyst implementer reviewer; do files="$files $AGENTS/$a.md"; done
	for f in $files; do
		[ "$(wc -l <"$f" | tr -d ' ')" -le 80 ] || fail "${f#"$PKG_ROOT"/} is longer than 80 lines"
		for c in $(commands_in "$f"); do
			printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "${f#"$PKG_ROOT"/} uses unknown command: ./softwary $c"
		done
	done
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

# AC-V2-15: only a human approves; define and blueprint say so, and so does
# the core rule that every tool gets.
test_ac_v2_15_human_approves() {
	assert_contains "$SKILLS/define/SKILL.md" "Only a human approves the product"
	assert_contains "$SKILLS/define/SKILL.md" "./softwary approve product"
	assert_contains "$SKILLS/define/SKILL.md" "You never run \`./softwary approve\`"
	assert_contains "$SKILLS/blueprint/SKILL.md" "Only a human approves the"
	assert_contains "$SKILLS/blueprint/SKILL.md" "./softwary approve blueprint"
	assert_contains "$SKILLS/blueprint/SKILL.md" "You never run \`./softwary approve\`"
	assert_contains "$PKG_ROOT/src/rules/core.md" "Only a human runs \`./softwary approve\`"
	for f in "$SKILLS/plan/SKILL.md" "$SKILLS/run/SKILL.md"; do
		! grep -E -e './softwary approve( |$)' "$f" >/dev/null || fail "${f#"$PKG_ROOT"/} runs approve"
	done
}

# AC-V2-15: the run skill coordinates only: its own commands are run, job and
# status; it does not merge, writes no file, and calls the advisor itself.
test_ac_v2_15_run_contract() {
	f=$SKILLS/run/SKILL.md
	for c in $(commands_in "$f"); do
		case $c in run | job | status) ;; *) fail "run uses ./softwary $c" ;; esac
	done
	assert_contains "$f" "You write no artifact and no state file"
	assert_contains "$f" "**one line**"
	assert_contains "$f" "**you** call the \`advisor\`"
	assert_contains "$f" "call the \`approver\`"
	assert_contains "$f" "You never merge yourself"
	assert_contains "$f" "./softwary job tokens"
	assert_contains "$f" "./softwary run next"
}

# AC-V2-15: each agent writes only its own file and replies in one line.
test_ac_v2_15_agent_files() {
	f=$AGENTS/approver.md
	assert_contains "$f" ".softwary/state/jobs/<job>/decision.md"
	assert_contains "$f" "./softwary merge <job>"
	assert_contains "$f" "./softwary job escalate <job>"
	assert_contains "$f" "\`merged\` or \`escalated: <question>\`"
	for c in $(commands_in "$f"); do
		case $c in merge | job) ;; *) fail "approver uses ./softwary $c" ;; esac
	done
	! grep -F "./softwary job event" "$f" >/dev/null || fail "approver changes job state itself"
	f=$AGENTS/advisor.md
	assert_contains "$f" ".softwary/state/jobs/<job>/advice.md"
	assert_contains "$f" "\`advice written\`"
	assert_contains "$f" "Do not edit code"
	f=$AGENTS/spec-analyst.md
	assert_contains "$f" "specs/NNN-<name>/analysis.md"
	assert_contains "$f" "git hash-object"
	assert_contains "$f" "\`pass\` or \`fail\`"
	f=$AGENTS/implementer.md
	for t in "\`done\`" "\`blocked: <reason>\`" "\`advice: <question>\`" "Commit everything on the job branch" "status: in-progress"; do
		assert_contains "$f" "$t"
	done
	assert_contains "$AGENTS/reviewer.md" "\`approve\` or \`changes\`"
	assert_contains "$SKILL" "\`define\`"
	assert_contains "$SKILL" "max_job_tokens"
}

run_tests "$0"
