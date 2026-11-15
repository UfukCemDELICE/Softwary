#!/bin/sh
# Files with CRLF line endings (Git for Windows checks text out with CRLF by
# default): sources and artifacts are read as if they had LF.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# to_crlf FILE...: rewrites each FILE with CRLF line endings.
to_crlf() {
	for _f in "$@"; do
		sed 's/$/\r/' "$_f" >"$_f.tmp" && mv "$_f.tmp" "$_f"
	done
}

# AC-M1-04: managed sources with CRLF line endings are synced; the generated
# files have LF line endings and stay up to date.
test_ac_m1_04_crlf_sources() {
	setup_repo
	to_crlf "$REPO"/.softwary/skills/*/SKILL.md "$REPO"/.softwary/agents/*.md "$REPO/.softwary/rules/core.md"
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	for f in .claude/skills/softwary-setup/SKILL.md .claude/agents/reviewer.md .codex/agents/reviewer.toml AGENTS.md; do
		! grep -q "$(printf '\r')" "$REPO/$f" || fail "$f has CR characters"
	done
	assert_contains "$REPO/.claude/skills/softwary-setup/SKILL.md" "name: softwary-setup"
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

# AC-M2-05, AC-M2-07, AC-M3-03: specs, slices, reviews and ADRs with CRLF line
# endings trace like LF ones; an open question under a CRLF heading still fails.
test_ac_m2_05_crlf_artifacts() {
	setup_repo
	conf_all true
	add_specs
	write_adr 0001 accepted "$MODEL_REL"
	to_crlf "$REPO"/specs/001-login/spec.md "$REPO"/specs/001-login/slices/*.md "$REPO"/specs/001-login/reviews/*.md "$REPO"/architecture/decisions/*.md
	sw trace
	assert_eq "$RC" 0 "trace exit code"
	assert_match "$OUT" "^trace: 1 spec\(s\), 2 slice\(s\), 3 criteria$"
	assert_match "$OUT" "^trace: 1 ADR\(s\)$"
	printf '## Open questions\r\n\r\n- Which hash?\r\n' >>"$REPO/specs/001-login/spec.md"
	sw trace
	assert_eq "$RC" 1 "trace exit code with an open question"
	assert_match "$OUT" "open questions: an approved spec must have none"
}

run_tests "$0"
