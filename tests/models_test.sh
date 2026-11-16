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
	loop_set concurrency 2
	loop_set max_job_tokens UNSET
	loop_set max_run_tokens 12.5
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "$LOOP_RE:1: max_rounds: '0' is not a positive integer\)$"
	assert_match "$OUT" "$LOOP_RE:2: max_job_minutes: '-5' is not a positive integer\)$"
	assert_match "$OUT" "$LOOP_RE:3: max_run_minutes: 'soon' is not a positive integer\)$"
	assert_match "$OUT" "$LOOP_RE:4: concurrency above 1 arrives with parallel jobs \(V4\)\)$"
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
	assert_match "$OUT" "$LOOP_RE:[0-9]+: concurrency: '0' is not a positive integer\)$"
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
# header, right after the description; Cursor and Codex files carry none.
test_ac_v2_14_sync_writes_model() {
	ready
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/implementer.md")" "model: sonnet" "implementer model line"
	assert_eq "$(sed -n 3p "$REPO/.claude/agents/implementer.md" | cut -c1-12)" "description:" "description line"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/reviewer.md")" "model: opus" "reviewer model line"
	for f in "$REPO"/.claude/agents/*.md; do
		assert_contains "$f" "model: "
	done
	for f in "$REPO"/.cursor/agents/*.md "$REPO"/.codex/agents/*.toml; do
		! grep -E '^model' "$f" >/dev/null || fail "${f#"$REPO"/} carries a model"
	done
	assert_contains "$REPO/.cursor/agents/implementer.md" "description:"
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

run_tests "$0"
