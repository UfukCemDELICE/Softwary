#!/bin/sh
# Tests for loop.conf, models.conf, doctor and sync's model line (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

MODELS_REL=.softwary/config/models.conf
LOOP_RE='^loop\.conf +FAIL \(\.softwary/config/loop\.conf'
MODELS_RE='^models +FAIL \(\.softwary/config/models\.conf'

# ready: a complete repo, so doctor reports only what a test changes.
ready() {
	setup_repo
	conf_all true
}

# models_set KEY VALUE: sets KEY in models.conf.
models_set() {
	file_set "$REPO/$MODELS_REL" "$1" "$2"
}

# AC-V2-11: a valid loop.conf passes; every invalid value is its own doctor
# line, with the line number of the setting.
test_ac_v2_11_loop_conf_validation() {
	ready
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_match "$OUT" "^loop\.conf +PASS"
	loop_set max_rounds 0
	loop_set max_job_minutes -5
	loop_set max_run_minutes soon
	loop_set concurrency 4
	loop_set max_job_tokens UNSET
	loop_set max_run_tokens 12.5
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$LOOP_RE:1: max_rounds: '0' is not a positive integer\)$"
	assert_match "$OUT" "$LOOP_RE:2: max_job_minutes: '-5' is not a positive integer\)$"
	assert_match "$OUT" "$LOOP_RE:3: max_run_minutes: 'soon' is not a positive integer\)$"
	assert_match "$OUT" "$LOOP_RE:4: concurrency must be 1, 2 or 3\)$"
	assert_match "$OUT" "$LOOP_RE:5: max_job_tokens: is UNSET \(set a positive integer or 'NONE: <reason>'\)\)$"
	assert_match "$OUT" "$LOOP_RE:6: max_run_tokens: '12.5' is not a positive integer or 'NONE: <reason>'\)$"
	assert_no_match "$OUT" "^loop\.conf +PASS"
}

# AC-V2-11: a zero concurrency, a NONE limit on a time key, a missing key, an
# unknown key and a NONE without a reason are problems; a token limit may be NONE.
test_ac_v2_11_loop_conf_shape() {
	ready
	loop_set concurrency 0
	loop_set max_rounds 'NONE: unlimited'
	loop_set mystery 1
	sed '/^max_run_minutes/d' "$REPO/.softwary/config/loop.conf" >"$T/l" && cp "$T/l" "$REPO/.softwary/config/loop.conf"
	loop_set max_job_tokens 'NONE'
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$LOOP_RE:[0-9]+: concurrency must be 1, 2 or 3\)$"
	assert_match "$OUT" "$LOOP_RE:[0-9]+: max_rounds: 'NONE: unlimited' is not a positive integer\)$"
	assert_match "$OUT" "$LOOP_RE:[0-9]+: unknown key 'mystery'"
	assert_match "$OUT" "$LOOP_RE: 'max_run_minutes' is missing\)$"
	assert_match "$OUT" "$LOOP_RE:[0-9]+: malformed line: 'max_job_tokens' needs a reason"
	loop_conf
	sw doctor
	assert_eq "$RC" 0 "doctor exit code with a valid file"
}

# AC-V2-11: the template that install.sh writes leaves the token limits UNSET,
# so doctor fails until the human chooses them; a missing file fails too.
test_ac_v2_11_installed_template_fails_on_tokens() {
	ready
	cp "$PKG_ROOT/src/templates/loop.conf" "$REPO/.softwary/config/loop.conf"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$LOOP_RE:[0-9]+: max_job_tokens: is UNSET"
	assert_match "$OUT" "$LOOP_RE:[0-9]+: max_run_tokens: is UNSET"
	assert_eq "$(grep -Ec '^loop\.conf +FAIL' "$OUT")" 2 "failing loop.conf lines"
	rm "$REPO/.softwary/config/loop.conf"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code without the file"
	assert_match "$OUT" "$LOOP_RE: file not found; rerun install.sh\)$"
}

# AC-V2-14: sync writes each agent's model into the Claude Code subagent
# header, right after the description. (V9: Cursor and Codex carry their own
# model ids, see AC-V9-02; here they are off.)
test_ac_v2_14_sync_writes_model() {
	ready
	tools_set claude-code on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/implementer.md")" "model: sonnet" "implementer model line"
	assert_eq "$(sed -n 3p "$REPO/.claude/agents/implementer.md" | cut -c1-12)" "description:" "description line"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/reviewer.md")" "model: opus" "reviewer model line"
	for f in "$REPO"/.claude/agents/*.md; do
		assert_contains "$f" "model: "
	done
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
	models_set implementer haiku
	sw sync --check
	assert_eq "$RC" 1 "sync --check after a model change"
	assert_contains "$OUT" ".claude/agents/implementer.md"
	sw sync
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/implementer.md")" "model: haiku" "changed model line"
}

# AC-V2-14: doctor reports each models.conf problem on its own line.
test_ac_v2_14_doctor_models_problems() {
	ready
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_match "$OUT" "^models +PASS"
	sed '/^advisor/d; /^approver/d' "$REPO/$MODELS_REL" >"$T/m" && cp "$T/m" "$REPO/$MODELS_REL"
	models_set ghost opus
	models_set implementer 'bad/model'
	models_set reviewer sonnet
	printf 'spec-analyst = opus\njunk\n' >>"$REPO/$MODELS_REL"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$MODELS_RE: agent 'advisor' has no model\)$"
	assert_match "$OUT" "$MODELS_RE: agent 'approver' has no model\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: unknown agent 'ghost'\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: invalid model 'bad/model' for 'implementer'\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: malformed line: duplicate key 'spec-analyst'"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: malformed line: expected"
	assert_no_match "$OUT" "^models +PASS"
}

# AC-V2-14: the reviewer and the approver must not use the implementer's model.
test_ac_v2_14_doctor_same_model_as_implementer() {
	ready
	models_set reviewer sonnet
	models_set approver sonnet
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: reviewer must not use the same model as implementer \(sonnet\)\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: approver must not use the same model as implementer \(sonnet\)\)$"
	assert_eq "$(grep -Ec '^models +FAIL' "$OUT")" 2 "failing models lines"
}

# AC-V2-14: a local agent needs a model line too; a local agent counts as installed.
test_ac_v2_14_local_agent_needs_a_model() {
	ready
	add_sources
	sw doctor
	assert_match "$OUT" "$MODELS_RE: agent 'helper' has no model\)$"
	models_set helper haiku
	sw doctor
	assert_no_match "$OUT" "^models +FAIL"
}

# AC-V2-14: without a usable models.conf sync still works, writes no model
# line and leaves the complaint to doctor.
test_ac_v2_14_missing_models_conf_keeps_sync() {
	ready
	tools_all on
	rm "$REPO/$MODELS_REL"
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	for f in "$REPO"/.claude/agents/*.md; do
		! grep -E '^model' "$f" >/dev/null || fail "${f#"$REPO"/} carries a model"
	done
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$MODELS_RE: file not found; rerun install.sh\)$"
	cp "$PKG_ROOT/src/templates/models.conf" "$REPO/$MODELS_REL"
	models_set reviewer sonnet
	sw sync
	assert_eq "$RC" 0 "sync exit code with an invalid file"
	! grep -E '^model' "$REPO/.claude/agents/reviewer.md" >/dev/null || fail "an invalid models.conf was applied"
}

# AC-V2-14: install.sh writes both files once; install and upgrade keep them.
test_ac_v2_14_install_keeps_owned_files() {
	ready
	cmp -s "$PKG_ROOT/src/templates/models.conf" "$REPO/$MODELS_REL" || fail "models.conf is not the template"
	printf 'max_rounds = 7\n' >"$REPO/.softwary/config/loop.conf"
	printf 'implementer = haiku\n' >"$REPO/$MODELS_REL"
	sh "$PKG_ROOT/install.sh" "$REPO" >"$OUT" 2>&1 || fail "install failed"
	assert_contains "$OUT" ".softwary/config/loop.conf (exists, kept)"
	assert_contains "$OUT" ".softwary/config/models.conf (exists, kept)"
	assert_eq "$(cat "$REPO/.softwary/config/loop.conf")" "max_rounds = 7" "loop.conf"
	assert_eq "$(cat "$REPO/$MODELS_REL")" "implementer = haiku" "models.conf"
	sw upgrade "$PKG_ROOT"
	assert_eq "$(cat "$REPO/.softwary/config/loop.conf")" "max_rounds = 7" "loop.conf after upgrade"
	assert_eq "$(cat "$REPO/$MODELS_REL")" "implementer = haiku" "models.conf after upgrade"
}

# tr_set TOOL CLASS ID: sets the model id of CLASS in TOOL in models.conf.
tr_set() {
	sed "/^$1: $2 = /d" "$REPO/$MODELS_REL" >"$T/m" && cp "$T/m" "$REPO/$MODELS_REL"
	printf '%s: %s = %s\n' "$1" "$2" "$3" >>"$REPO/$MODELS_REL"
}

# plan_repo: approved product and blueprint, the sample plan and an origin, so
# that `run start` can open a run.
plan_repo() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	add_origin
}

# AC-V9-01: a class has one line per tool; the lines of a tool that is off may
# be there, Claude Code uses its line, and a tool without one gets the class name.
test_ac_v9_01_translation_lines_are_read() {
	ready
	models_translate cursor codex claude-code
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_match "$OUT" "^models +PASS"
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/implementer.md")" "model: claude-code-small" "translated Claude Code model"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/reviewer.md")" "model: claude-code-big" "translated Claude Code model of the reviewer"
	sed '/^claude-code:/d' "$REPO/$MODELS_REL" >"$T/m" && cp "$T/m" "$REPO/$MODELS_REL"
	sw sync
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/implementer.md")" "model: sonnet" "Claude Code without a translation is the class"
}

# AC-V9-01: Cursor or Codex on without a model id for a class is a doctor
# failure, one line for each class; a tool that is off needs none.
test_ac_v9_01_missing_translation_fails_when_tool_on() {
	ready
	sw doctor
	assert_eq "$RC" 0 "doctor exit code with every tool off"
	tools_set cursor on
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$MODELS_RE: cursor is on but the class 'opus' has no model id \(add 'cursor: opus = <model id>'\)\)$"
	assert_match "$OUT" "$MODELS_RE: cursor is on but the class 'sonnet' has no model id"
	assert_eq "$(grep -Ec '^models +FAIL' "$OUT")" 2 "failing models lines"
	printf 'cursor: opus = big\n' >>"$REPO/$MODELS_REL"
	sw doctor
	assert_eq "$(grep -Ec '^models +FAIL' "$OUT")" 1 "failing models lines with one class translated"
	assert_match "$OUT" "the class 'sonnet' has no model id"
	printf 'cursor: sonnet = small\n' >>"$REPO/$MODELS_REL"
	sw sync
	sw doctor
	assert_eq "$RC" 0 "doctor exit code with Cursor translated"
	tools_set codex on
	sw doctor
	assert_eq "$RC" 2 "doctor exit code with Codex on"
	assert_match "$OUT" "$MODELS_RE: codex is on but the class 'opus' has no model id"
	tools_set codex off
	tools_set claude-code on
	sw sync
	sw doctor
	assert_eq "$RC" 0 "Claude Code needs no translation"
}

# AC-V9-01: `run start` stops (2) on a missing translation of a tool that is on
# and opens no run; with the translation it opens one.
test_ac_v9_01_run_start_stops_on_missing_translation() {
	plan_repo
	tools_set cursor on
	commit_all "cursor on"
	sw run start
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "cursor is on but the class 'opus' has no model id"
	[ ! -e "$REPO/.softwary/state/run" ] || fail "a run was opened"
	models_translate cursor
	commit_all "translated"
	sw run start
	assert_eq "$RC" 0 "exit code with the translation"
}

# AC-V9-01: an unknown tool, a class no agent uses, a duplicate line, an UNSET,
# empty or malformed id are each a problem of their own, with the line number.
test_ac_v9_01_translation_errors() {
	ready
	{
		printf 'vim: opus = big\n'
		printf 'cursor: haiku = small\n'
		printf 'cursor: opus = big\n'
		printf 'cursor: opus = other\n'
		printf 'codex: opus = UNSET\n'
		printf 'codex: sonnet =\n'
		printf 'claude-code: opus = has space\n'
		printf 'claude-code: sonnet = a"b\n'
		printf ': opus = x\n'
		printf 'cursor: = x\n'
		printf 'cursor: a/b = x\n'
		printf 'cursor: a b = x\n'
	} >>"$REPO/$MODELS_REL"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: unknown tool 'vim' in 'vim:opus' \(known: claude-code codex cursor\)\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: no agent uses the class 'haiku' \('cursor:haiku'\)\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: malformed line: duplicate key 'cursor:opus'"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: invalid model id 'UNSET' for 'codex:opus'\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: malformed line: empty value for 'codex:sonnet'"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: invalid model id 'has space' for 'claude-code:opus'\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: invalid model id 'a\"b' for 'claude-code:sonnet'\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: malformed line: invalid key ':opus'"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: malformed line: invalid key 'cursor:'"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: malformed line: invalid key 'cursor:a/b'"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: malformed line: invalid key 'cursor:a b'"
	assert_no_match "$OUT" "^models +PASS"
}

# AC-V9-01: a translation key never takes the place of an agent's: an agent
# called cursor-copus and the line `cursor: opus` keep their own values.
test_ac_v9_01_keys_do_not_collide() {
	ready
	cp "$REPO/.softwary/agents/implementer.md" "$T/impl.md"
	mkdir -p "$REPO/.softwary/local/agents"
	sed 's/^name: .*/name: cursor-copus/' "$T/impl.md" >"$REPO/.softwary/local/agents/cursor-copus.md"
	models_set cursor-copus haiku
	printf 'cursor: opus = cursor-big\ncursor: sonnet = cursor-small\ncursor: haiku = cursor-tiny\n' >>"$REPO/$MODELS_REL"
	tools_set claude-code on
	tools_set cursor on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/cursor-copus.md")" "model: haiku" "the agent's class"
	assert_eq "$(sed -n 4p "$REPO/.cursor/agents/cursor-copus.md")" "model: cursor-tiny" "the agent's id in Cursor"
	assert_eq "$(sed -n 4p "$REPO/.cursor/agents/reviewer.md")" "model: cursor-big" "another agent's id in Cursor"
}

# AC-V9-02: sync writes the model id of each agent into the Cursor header (a
# `model:` line after the description) and into the Codex TOML (`model = "..."`),
# the class or its Claude Code line into the Claude Code file.
test_ac_v9_02_sync_writes_model_in_cursor_and_codex() {
	ready
	tools_all on
	models_translate
	tr_set cursor opus "claude-opus-5[effort=high]"
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	assert_eq "$(sed -n 4p "$REPO/.cursor/agents/reviewer.md")" "model: claude-opus-5[effort=high]" "reviewer in Cursor"
	assert_eq "$(sed -n 3p "$REPO/.cursor/agents/reviewer.md" | cut -c1-12)" "description:" "description line"
	assert_eq "$(sed -n 5p "$REPO/.cursor/agents/reviewer.md")" "---" "closing line"
	assert_eq "$(sed -n 4p "$REPO/.cursor/agents/implementer.md")" "model: cursor-small" "implementer in Cursor"
	assert_eq "$(sed -n 4p "$REPO/.codex/agents/reviewer.toml")" 'model = "codex-big"' "reviewer in Codex"
	assert_eq "$(sed -n 4p "$REPO/.codex/agents/implementer.toml")" 'model = "codex-small"' "implementer in Codex"
	assert_eq "$(sed -n 3p "$REPO/.codex/agents/reviewer.toml" | cut -c1-15)" "description = \"" "description line in Codex"
	assert_eq "$(sed -n 5p "$REPO/.codex/agents/reviewer.toml")" 'developer_instructions = """' "instructions line in Codex"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/reviewer.md")" "model: opus" "reviewer in Claude Code"
	for f in "$REPO"/.cursor/agents/*.md; do
		assert_eq "$(grep -c '^model: ' "$f")" 1 "model lines of ${f#"$REPO"/}"
	done
	for f in "$REPO"/.codex/agents/*.toml; do
		assert_eq "$(grep -c '^model = ' "$f")" 1 "model lines of ${f#"$REPO"/}"
	done
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
	tr_set codex sonnet codex-medium
	sw sync --check
	assert_eq "$RC" 1 "sync --check after a translation change"
	assert_contains "$OUT" ".codex/agents/implementer.toml"
	assert_no_match "$OUT" "\.cursor/agents"
	sw sync
	assert_eq "$(sed -n 4p "$REPO/.codex/agents/implementer.toml")" 'model = "codex-medium"' "changed model in Codex"
}

# AC-V9-02: a local agent gets its models too; only the tools that are on are written.
test_ac_v9_02_local_agent_and_tools_off() {
	ready
	add_sources
	models_translate
	models_set helper haiku
	printf 'cursor: haiku = cursor-tiny\ncodex: haiku = codex-tiny\n' >>"$REPO/$MODELS_REL"
	tools_set cursor on
	tools_set codex off
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	assert_eq "$(sed -n 4p "$REPO/.cursor/agents/helper.md")" "model: cursor-tiny" "local agent in Cursor"
	[ ! -e "$REPO/.codex" ] || fail "Codex is off but .codex was written"
}

# AC-V9-02: without a usable models.conf no tool gets a model field (the V2
# rule); sync still works and doctor complains.
test_ac_v9_02_unusable_models_conf_writes_no_field() {
	ready
	tools_all on
	models_translate
	models_set implementer 'bad/model'
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	for f in "$REPO"/.claude/agents/*.md "$REPO"/.cursor/agents/*.md "$REPO"/.codex/agents/*.toml; do
		! grep -E '^model' "$f" >/dev/null || fail "${f#"$REPO"/} carries a model"
	done
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: invalid model 'bad/model' for 'implementer'\)$"
	rm -f "${REPO:?}/${MODELS_REL:?}"
	sw sync
	assert_eq "$RC" 0 "sync exit code without models.conf"
	assert_no_match "$REPO/.cursor/agents/reviewer.md" "^model"
}

# AC-V9-03: in a tool that is on the reviewer and the approver must not end up
# with the implementer's model id; every tool is worked out by itself, and a
# tool that is off is not compared.
test_ac_v9_03_cursor_reviewer_uses_the_implementers_model() {
	ready
	{
		printf 'cursor: opus = same-id\ncursor: sonnet = same-id\n'
		printf 'codex: opus = codex-big\ncodex: sonnet = codex-small\n'
	} >>"$REPO/$MODELS_REL"
	sw doctor
	assert_eq "$RC" 0 "doctor exit code with Cursor off"
	tools_set cursor on
	tools_set codex on
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: reviewer uses the implementer's model in cursor \(same-id\)\)$"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: approver uses the implementer's model in cursor \(same-id\)\)$"
	assert_eq "$(grep -Ec '^models +FAIL' "$OUT")" 2 "failing models lines"
	assert_no_match "$OUT" "in codex"
	assert_no_match "$OUT" "in claude-code"
	assert_no_match "$OUT" "must not use the same model"
	tr_set codex opus codex-small
	sw doctor
	assert_match "$OUT" "reviewer uses the implementer's model in codex \(codex-small\)"
	assert_match "$OUT" "reviewer uses the implementer's model in cursor \(same-id\)"
	assert_eq "$(grep -Ec '^models +FAIL' "$OUT")" 4 "failing models lines"
}

# AC-V9-03: `run start` stops (2) on it and opens no run.
test_ac_v9_03_run_start_stops_on_it() {
	plan_repo
	printf 'cursor: opus = same-id\ncursor: sonnet = same-id\n' >>"$REPO/$MODELS_REL"
	tools_set cursor on
	commit_all "cursor on"
	sw run start
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "reviewer uses the implementer's model in cursor (same-id)"
	[ ! -e "$REPO/.softwary/state/run" ] || fail "a run was opened"
}

# AC-V9-03: the Claude Code rule is the V2 one (by class name, one line each),
# and a translation that makes two classes one id is caught there too.
test_ac_v9_03_claude_code_rule_is_kept() {
	ready
	tools_all on
	models_translate
	models_set reviewer sonnet
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$MODELS_RE:[0-9]+: reviewer must not use the same model as implementer \(sonnet\)\)$"
	assert_no_match "$OUT" "in claude-code"
	assert_match "$OUT" "reviewer uses the implementer's model in cursor \(cursor-small\)"
	models_set reviewer opus
	printf 'claude-code: opus = one\nclaude-code: sonnet = one\n' >>"$REPO/$MODELS_REL"
	sw doctor
	assert_match "$OUT" "$MODELS_RE:[0-9]+: reviewer uses the implementer's model in claude-code \(one\)\)$"
}

run_tests "$0"
