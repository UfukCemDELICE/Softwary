#!/bin/sh
# Tests for the setup skill (M3).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
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

# AC-V1-08: an empty repository gets no model and is pointed at define and
# blueprint. (V6: in an existing one the paths each component is drawn from
# are listed by blueprint's ADR, not by setup: see AC-V6-10 and AC-V6-12.)
test_ac_v1_08_setup_empty_and_existing_repo() {
	assert_contains "$SKILL" "empty repository"
	assert_contains "$SKILL" "do not draft a model"
	assert_contains "$SKILL" "\`define\`"
	assert_contains "$SKILL" "\`blueprint\`"
	assert_contains "$SKILL" ".gitkeep"
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

# AC-V2-15: the run skill coordinates only: its own commands are run, job,
# queue and status; it does not merge, writes no file, and calls the advisor itself.
test_ac_v2_15_run_contract() {
	f=$SKILLS/run/SKILL.md
	for c in $(commands_in "$f"); do
		case $c in run | job | queue | status) ;; *) fail "run uses ./softwary $c" ;; esac
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
	assert_contains "$f" "\`merged\` (the script printed"
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

V3_FILES="$SKILLS/implement/SKILL.md $SKILLS/run/SKILL.md $SKILLS/setup/SKILL.md $SKILLS/review/SKILL.md $SKILLS/evaluate/SKILL.md $AGENTS/implementer.md $AGENTS/reviewer.md"

# AC-V3-13: implement, implementer and run carry an excuse table: a heading
# and at least three rows of excuse and reply.
test_ac_v3_13_excuse_tables() {
	for f in "$SKILLS/implement/SKILL.md" "$AGENTS/implementer.md" "$SKILLS/run/SKILL.md"; do
		assert_contains "$f" "## Excuses"
		rows=$(grep -c '^| ' "$f")
		[ "$rows" -ge 5 ] || fail "${f#"$PKG_ROOT"/}: the excuse table has fewer than three rows ($((rows - 2)))"
	done
}

# AC-V3-13: a finding of the reviewer carries evidence; no evidence, no
# finding; the output of guard goes into the review.
test_ac_v3_13_evidence_only_findings() {
	for f in "$AGENTS/reviewer.md" "$PKG_ROOT/src/templates/artifacts/review.md"; do
		assert_contains "$f" "evidence:"
		assert_contains "$f" "no evidence"
	done
	assert_contains "$AGENTS/reviewer.md" "./softwary guard"
	assert_contains "$AGENTS/reviewer.md" "do not write it"
}

# AC-V3-13: the evaluate skill prepares the cases, has each one reviewed in a
# clean context, scores them and leaves the result to the human; it reaches
# the three tools.
test_ac_v3_13_evaluate_skill() {
	f=$SKILLS/evaluate/SKILL.md
	[ -f "$f" ] || fail "src/skills/evaluate/SKILL.md missing"
	assert_contains "$f" "./softwary eval prepare"
	assert_contains "$f" "./softwary eval score"
	assert_contains "$f" "clean context"
	assert_contains "$f" "reviewer"
	assert_contains "$f" "eval.conf"
	assert_contains "$f" "leave"
	setup_repo
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	for d in .claude .cursor .agents; do
		[ -s "$REPO/$d/skills/softwary-evaluate/SKILL.md" ] || fail "$d/skills/softwary-evaluate/SKILL.md missing"
	done
}

# AC-V3-13: setup asks for test-skip.conf and for min_catch_percent.
test_ac_v3_13_setup_asks() {
	assert_contains "$SKILL" "test-skip.conf"
	assert_contains "$SKILL" "min_catch_percent"
	assert_contains "$PKG_ROOT/src/rules/core.md" "protected paths"
}

# AC-V3-13: none of them is longer than 80 lines or names a command that help
# does not list.
test_ac_v3_13_short_and_known_commands() {
	known=$(sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u)
	for f in $V3_FILES; do
		[ -f "$f" ] || fail "${f#"$PKG_ROOT"/} missing"
		[ "$(wc -l <"$f" | tr -d ' ')" -le 80 ] || fail "${f#"$PKG_ROOT"/} is longer than 80 lines"
		for c in $(commands_in "$f"); do
			printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "${f#"$PKG_ROOT"/} uses unknown command: ./softwary $c"
		done
	done
	for c in $(commands_in "$SKILLS/run/SKILL.md"); do
		case $c in run | job | queue | status) ;; *) fail "run uses ./softwary $c" ;; esac
	done
}

# AC-V4-14: the run skill applies every line of run next, runs at most
# concurrency jobs and drains the queue; implementer, reviewer and approver
# know the worktree and the queue.
test_ac_v4_14_parallel_texts() {
	f=$SKILLS/run/SKILL.md
	for t in "one line for each thing to do" "\`concurrency\`" "./softwary queue drain" "\`merging: <jobs>\`" "\`waiting: <jobs>\`" "\`stop: <why>\`" \
		"already has an agent working on it" ".softwary/worktrees/<job>" "\`queued\`" "in the background"; do
		assert_contains "$f" "$t"
	done
	assert_contains "$AGENTS/implementer.md" ".softwary/worktrees/<job>"
	assert_contains "$AGENTS/implementer.md" "only there"
	assert_contains "$AGENTS/reviewer.md" "git diff origin/<integration>...softwary/<job>"
	assert_contains "$AGENTS/reviewer.md" ".softwary/worktrees/<job>/specs/NNN-<name>/reviews/S<n>.md"
	assert_contains "$AGENTS/approver.md" "\`merged\` (the script printed"
	assert_contains "$AGENTS/approver.md" "\`queued\`"
	assert_contains "$AGENTS/approver.md" "\`escalated: <question>\`"
	known=$(sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u)
	for f in $V3_FILES; do
		[ "$(wc -l <"$f" | tr -d ' ')" -le 80 ] || fail "${f#"$PKG_ROOT"/} is longer than 80 lines"
		for c in $(commands_in "$f"); do
			printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "${f#"$PKG_ROOT"/} uses unknown command: ./softwary $c"
		done
	done
	for c in $(commands_in "$AGENTS/approver.md"); do
		case $c in merge | job) ;; *) fail "approver uses ./softwary $c" ;; esac
	done
}

# AC-V5-12: discover, architect, specify and slice are gone from the package;
# the surviving and the new skills and agents reach the three tools.
test_ac_v5_12_package_skills() {
	for s in discover architect specify slice; do
		[ ! -e "$SKILLS/$s" ] || fail "src/skills/$s is still in the package"
	done
	for s in define blueprint plan implement review run setup evaluate handoff; do
		[ -f "$SKILLS/$s/SKILL.md" ] || fail "src/skills/$s/SKILL.md missing"
	done
	[ -f "$AGENTS/blueprint-critic.md" ] || fail "src/agents/blueprint-critic.md missing"
	setup_repo
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	for s in define blueprint plan implement review handoff; do
		for d in .claude .cursor .agents; do
			[ -s "$REPO/$d/skills/softwary-$s/SKILL.md" ] || fail "$d/skills/softwary-$s/SKILL.md missing"
		done
	done
	for d in .claude .cursor; do
		[ -s "$REPO/$d/agents/blueprint-critic.md" ] || fail "$d/agents/blueprint-critic.md missing"
	done
	[ -s "$REPO/.codex/agents/blueprint-critic.toml" ] || fail ".codex/agents/blueprint-critic.toml missing"
	for s in discover architect specify slice; do
		for d in .claude .cursor .agents; do
			[ ! -e "$REPO/$d/skills/softwary-$s" ] || fail "$d/skills/softwary-$s was generated"
		done
	done
}

# AC-V5-12: define asks one question at a time with a recommended answer until
# every branch is closed, and writes decisions as they are made; it holds what
# discover did (stories, terms, open questions).
test_ac_v5_12_define_text() {
	f=$SKILLS/define/SKILL.md
	for t in "one question at a time" "recommended answer" "every branch" "CONTEXT.md" ".softwary/templates/adr.md" "status: proposed" \
		"user stories" "## Open questions" "./softwary product check"; do
		assert_contains "$f" "$t"
	done
}

# AC-V5-12: blueprint carries the architect stage and the V5 artifacts: flows,
# state machines, specifications and the critic.
test_ac_v5_12_blueprint_text() {
	f=$SKILLS/blueprint/SKILL.md
	for t in ".softwary/templates/adr.md" "status: proposed" "./softwary model validate" "./softwary views" "architecture/flows/" "architecture/states/" \
		"architecture/formal/" ".softwary/templates/flow.json" ".softwary/templates/states.json" ".softwary/templates/formal.md" \
		"./softwary formal check" "./softwary blueprint check" "blueprint-critic" "plain sentence" "variant" "only a human"; do
		assert_contains "$f" "$t"
	done
	assert_contains "$f" "Only a human approves the"
}

# AC-V5-12: plan carries the spec and slice stages: the spec's fields and
# limits, the analyst, a fresh session where a tool has no subagents, and the
# slice's touches and depends_on.
test_ac_v5_12_plan_text() {
	f=$SKILLS/plan/SKILL.md
	for t in ".softwary/templates/spec.md" ".softwary/templates/slice.md" "status: draft" "spec-analyst" "fresh session" "touches" "depends_on" \
		"exactly one slice" "one end-to-end" "risk" "./softwary plan approve" "./softwary trace"; do
		assert_contains "$f" "$t"
	done
}

# AC-V5-12: no skill, agent or rule names a stage that is gone, and every one
# of them stays within 80 lines and the commands that help lists.
test_ac_v5_12_short_known_commands_no_gone_stages() {
	known=$(sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u)
	for f in "$SKILLS"/*/SKILL.md "$AGENTS"/*.md; do
		[ "$(wc -l <"$f" | tr -d ' ')" -le 80 ] || fail "${f#"$PKG_ROOT"/} is longer than 80 lines"
		for c in $(commands_in "$f"); do
			printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "${f#"$PKG_ROOT"/} uses unknown command: ./softwary $c"
		done
	done
	for f in "$SKILLS"/*/SKILL.md "$AGENTS"/*.md "$PKG_ROOT/src/rules/core.md"; do
		! grep -E '`(discover|architect|specify|slice)`' "$f" >/dev/null || fail "${f#"$PKG_ROOT"/} names a stage that is gone"
	done
}

# AC-V6-10: in a repository with code setup draws no model and writes no
# baseline ADR; it runs verify and asks, for every project check that fails,
# whether to fix it or to waive it (a date, a reason and the scoped command),
# never inventing them, and names define and blueprint as the next steps.
test_ac_v6_10_setup_existing_repo_text() {
	for t in "./softwary verify" "./softwary verify --fast" "stops at \`model\`" "waive" ".softwary/config/waivers.conf" "<YYYY-MM-DD>: <reason>" "<key>_files" "{files}" "NONE: <reason>" \
		"never invent them" "do not draw the model" "do not write a baseline" "\`blueprint\` does both" "\`define\` (what the product does today)"; do
		assert_contains "$SKILL" "$t"
	done
	! grep -F -e "baseline-model" -e "draft the model from the code" -e "Start from \`.softwary/templates/system.calm.json\`" "$SKILL" >/dev/null ||
		fail "setup still draws the model of existing code"
	! grep -F "accept the baseline ADR" "$SKILL" >/dev/null || fail "setup still hands over a baseline ADR"
}

# AC-V6-11: define starts from the behaviour that exists: it reads the code,
# the documents and the tests, puts every feature and example to the human one
# at a time with a recommended answer, and keeps what is new apart.
test_ac_v6_11_define_from_code() {
	f=$SKILLS/define/SKILL.md
	for t in "Code already exists" "the README" "the tests" "one feature at a time" "recommended answer" "describe today's behaviour" \
		"separate feature" "Never infer"; do
		assert_contains "$f" "$t"
	done
}

# AC-V6-12: blueprint draws the model from the code: active components, real
# coverage, an ADR that lists the paths each component is drawn from, and a
# finding (a table with a date and a reason that the human gives) where the
# code breaks an invariant, never a weakened invariant.
test_ac_v6_12_blueprint_from_code() {
	f=$SKILLS/blueprint/SKILL.md
	for t in "Code already exists" "draw it from the code" "\`status: active\`" "not \`planned\`" "0001-model-from-code.md" "\`status: proposed\`" \
		"the paths each component is drawn from" "that is a finding" "do not weaken the invariant or the model" "Ask the human for the date" \
		"## Findings" "| Invariant | Until | Reason |" "FINDING"; do
		assert_contains "$f" "$t"
	done
}

# only_commands FILE WORDS: the ./softwary commands the file uses are among WORDS.
only_commands() {
	_oc_f=$1
	shift
	for _oc_c in $(commands_in "$_oc_f"); do
		case " $* " in *" $_oc_c "*) ;; *) fail "${_oc_f#"$PKG_ROOT"/} uses ./softwary $_oc_c" ;; esac
	done
}

# AC-V7-11: ship, diagnose and maintain reach the three tools, are within 80
# lines and name only commands that help lists.
test_ac_v7_11_distributed_short_and_known_commands() {
	setup_repo
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	known=$(sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u)
	for s in ship diagnose maintain; do
		f=$SKILLS/$s/SKILL.md
		[ -f "$f" ] || fail "src/skills/$s/SKILL.md missing"
		for d in .claude .cursor .agents; do
			[ -s "$REPO/$d/skills/softwary-$s/SKILL.md" ] || fail "$d/skills/softwary-$s/SKILL.md missing"
		done
		[ "$(wc -l <"$f" | tr -d ' ')" -le 80 ] || fail "${f#"$PKG_ROOT"/} is longer than 80 lines"
		for c in $(commands_in "$f"); do
			printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "${f#"$PKG_ROOT"/} uses unknown command: ./softwary $c"
		done
	done
	for c in ship repro drift; do
		printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "help does not list $c"
	done
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

# AC-V7-11: ship prepares, has the person's sections written, checks and opens
# the pull request; the merge and the deploy are left to the human.
test_ac_v7_11_ship_text() {
	f=$SKILLS/ship/SKILL.md
	for t in "./softwary ship prepare" "./softwary ship check" "./softwary ship pr" "./softwary next" "\`Observability\`" "\`Rollout\`" "\`Rollback\`" \
		"You never merge it and you never run" "merging it and deploying are" "drift has undecided or expired items" "\`maintain\`" "never invent it" "## Excuses"; do
		assert_contains "$f" "$t"
	done
	only_commands "$f" next ship
	! grep -F -e "./softwary deploy" -e "pr merge" "$f" >/dev/null || fail "ship merges or deploys"
	rows=$(grep -c '^| ' "$f")
	[ "$rows" -ge 5 ] || fail "the excuse table has fewer than three rows"
}

# AC-V7-11: diagnose writes the test that reproduces the bug first and sees it
# red, finds the cause with evidence, binds the fix to the example the bug
# breaks, sends behaviour no example describes to the human and fixes no code.
test_ac_v7_11_diagnose_text() {
	f=$SKILLS/diagnose/SKILL.md
	for t in "Reproduce first" "you must see it red" "Find the root cause with evidence" "A guess does not go into a spec" "\`EX-F<n>-NN\`" \
		"send them to \`define\`" "\`repro: <test file>\`" "./softwary plan check" "./softwary plan approve" "./softwary repro <job>" \
		"A red test must not reach the" "You write no code that fixes it" "never edit the code that is wrong" "## Excuses"; do
		assert_contains "$f" "$t"
	done
	only_commands "$f" plan repro doctor formal
}

# AC-V7-11: maintain runs drift and asks the human to decide each item, one at
# a time, writing the answer with a date and a reason; it decides nothing.
test_ac_v7_11_maintain_text() {
	f=$SKILLS/maintain/SKILL.md
	for t in "./softwary drift" "architecture/drift.md" "one at a time" "\`accept\`" "\`blueprint\`" "\`fix <spec number>\`" "never invent them" "stale decision" \
		"Only the human decides" ".softwary/templates/drift.md" "Every decision is the human's" "## Excuses"; do
		assert_contains "$f" "$t"
	done
	only_commands "$f" drift states formal
}

# AC-V7-11: run reports that ship is the human's step and never opens it; plan
# knows the repro field.
test_ac_v7_11_run_and_plan_texts() {
	assert_contains "$SKILLS/run/SKILL.md" "with the \`ship\` skill"
	assert_contains "$SKILLS/run/SKILL.md" "theirs, never yours"
	for c in $(commands_in "$SKILLS/run/SKILL.md"); do
		case $c in run | job | queue | status) ;; *) fail "run uses ./softwary $c" ;; esac
	done
	assert_contains "$SKILLS/plan/SKILL.md" "repro: <test files>"
	assert_contains "$SKILLS/plan/SKILL.md" "\`diagnose\`"
	assert_contains "$PKG_ROOT/src/templates/artifacts/slice.md" "repro (optional"
}

# AC-V8-11: implement and implementer check the model again when the code a
# specification covers changed, record the verdict with the record's commit,
# hand bug and blocked to the human and never change what binds one.
test_ac_v8_11_implement_records_the_verdict() {
	for f in "$SKILLS/implement/SKILL.md" "$AGENTS/implementer.md"; do
		for t in "./softwary formal check" "./softwary formal verified <spec>" "compatible" "updated" "(\`bug\`)" "\`blocked\`" \
			"./softwary job escalate <job> <question>" "./softwary formal trace <spec> <invariant>" "an invariant's sentence, a finding" "bind a human"; do
			assert_contains "$f" "$t"
		done
	done
	assert_contains "$SKILLS/implement/SKILL.md" "suspect the model first"
	assert_contains "$AGENTS/implementer.md" "the model is the first suspect"
	only_commands "$SKILLS/implement/SKILL.md" verify formal job
	only_commands "$AGENTS/implementer.md" verify formal job
}

# AC-V8-11: diagnose writes the repro test of a bug that breaks a finding with
# the steps of formal trace and names the counter-example in it.
test_ac_v8_11_diagnose_replays_the_counter_example() {
	f=$SKILLS/diagnose/SKILL.md
	for t in "## Findings" "./softwary formal trace <spec> <invariant>" "\`CE-<spec>-<invariant>\`" "the model is wrong first"; do
		assert_contains "$f" "$t"
	done
}

# AC-V8-11: maintain decides the two new drift items with the human, and says
# where to read what each one asks for.
test_ac_v8_11_maintain_new_items() {
	f=$SKILLS/maintain/SKILL.md
	for t in "\`untested ST-<entity>-<state>-<event>\`" "\`unreplayed CE-<spec>-<invariant>\`" "./softwary states tests" "./softwary formal trace <spec> <invariant>"; do
		assert_contains "$f" "$t"
	done
}

# AC-V8-11: blueprint writes the first verdict for code that exists, and
# proposes Lean only for a pure R3 core, with the proof in architecture/proofs/
# and its command in proof_check.
test_ac_v8_11_blueprint_verdict_and_lean() {
	f=$SKILLS/blueprint/SKILL.md
	for t in "./softwary formal verified <name> compatible" "Lean only for a" "pure algorithmic core at risk R3" "\`architecture/proofs/\`" "\`proof_check\`" "Never for anything else"; do
		assert_contains "$f" "$t"
	done
}

# AC-V8-11: the reviewer checks that a changed model was not weakened to fit
# the code, with the diff and formal check as evidence.
test_ac_v8_11_reviewer_checks_the_model() {
	f=$AGENTS/reviewer.md
	for t in "architecture/formal/*.tla" "was not weakened to fit the code" "no invariant left out of a" "no variant that stopped failing" "./softwary formal check"; do
		assert_contains "$f" "$t"
	done
}

# AC-V8-11: the six files reach the three tools, stay within 80 lines and name
# only commands that help lists.
test_ac_v8_11_distributed_short_and_known_commands() {
	setup_repo
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	known=$(sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u)
	for s in implement diagnose maintain blueprint; do
		for d in .claude .cursor .agents; do
			[ -s "$REPO/$d/skills/softwary-$s/SKILL.md" ] || fail "$d/skills/softwary-$s/SKILL.md missing"
		done
	done
	for d in .claude .cursor; do
		for a in implementer reviewer; do
			[ -s "$REPO/$d/agents/$a.md" ] || fail "$d/agents/$a.md missing"
		done
	done
	for f in "$SKILLS/implement/SKILL.md" "$SKILLS/diagnose/SKILL.md" "$SKILLS/maintain/SKILL.md" "$SKILLS/blueprint/SKILL.md" "$AGENTS/implementer.md" "$AGENTS/reviewer.md"; do
		[ "$(wc -l <"$f" | tr -d ' ')" -le 80 ] || fail "${f#"$PKG_ROOT"/} is longer than 80 lines"
		for c in $(commands_in "$f"); do
			printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "${f#"$PKG_ROOT"/} uses unknown command: ./softwary $c"
		done
	done
	for c in states formal; do
		printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "help does not list $c"
	done
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

run_tests "$0"
