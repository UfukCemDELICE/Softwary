#!/bin/sh
# Tests for the pipeline skills and subagents (M4).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

STAGES="define blueprint plan implement review"
AGENTS="spec-analyst implementer reviewer"

skill() { printf '%s\n' "$PKG_ROOT/src/skills/$1/SKILL.md"; }
agent() { printf '%s\n' "$PKG_ROOT/src/agents/$1.md"; }

# AC-M4-01: the five stage skills and three agents go to the three tools; the Codex
# agents are valid TOML; sync --check is clean afterwards.
test_ac_m4_01_distributed_to_three_tools() {
	command -v python3 >/dev/null || fail "python3 is required to validate TOML"
	setup_repo
	tools_all on
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	for s in $STAGES; do
		for d in .claude .cursor .agents; do
			[ -s "$REPO/$d/skills/softwary-$s/SKILL.md" ] || fail "$d/skills/softwary-$s/SKILL.md missing"
		done
	done
	for a in $AGENTS; do
		for d in .claude .cursor; do
			[ -s "$REPO/$d/agents/$a.md" ] || fail "$d/agents/$a.md missing"
		done
		python3 - "$REPO/.codex/agents/$a.toml" "$a" >"$OUT" 2>&1 <<'PY' || fail "invalid Codex TOML for $a: $(cat "$OUT")"
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    d = tomllib.load(f)
assert set(d) == {"name", "description", "developer_instructions"}, d
assert d["name"] == sys.argv[2], d["name"]
assert d["description"] and d["developer_instructions"].strip(), d
PY
	done
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

# AC-M4-02: every ./softwary command in a skill or agent is one the package
# recognises, and none is longer than 80 lines.
test_ac_m4_02_known_commands_and_short() {
	known=$(sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u)
	[ -n "$known" ] || fail "could not read the command list from help"
	files=
	for s in $STAGES; do files="$files $(skill "$s")"; done
	for a in $AGENTS; do files="$files $(agent "$a")"; done
	for f in $files; do
		[ -f "$f" ] || fail "${f#"$PKG_ROOT"/} missing"
		n=$(wc -l <"$f" | tr -d ' ')
		[ "$n" -le 80 ] || fail "${f#"$PKG_ROOT"/} has $n lines (at most 80)"
		used=$(awk '{
			s = $0
			while ((i = index(s, "./softwary ")) > 0) {
				s = substr(s, i + 11)
				split(s, w, /[^a-z-]/)
				if (w[1] != "") print w[1]
			}
		}' "$f" | sort -u)
		for c in $used; do
			printf '%s\n' "$known" | grep -Fqx -e "$c" || fail "${f#"$PKG_ROOT"/} uses unknown command: ./softwary $c"
		done
	done
}

# AC-M4-03: each skill names its output and its gate.
test_ac_m4_03_skills_name_outputs_and_gates() {
	f=$(skill define)
	for t in "CONTEXT.md" "open questions"; do assert_contains "$f" "$t"; done
	f=$(skill blueprint)
	for t in "./softwary model validate" "./softwary views" ".softwary/templates/adr.md" "status: proposed" "only a human"; do assert_contains "$f" "$t"; done
	f=$(skill plan)
	for t in ".softwary/templates/spec.md" ".softwary/templates/slice.md" "spec-analyst" "status: draft" "./softwary trace"; do assert_contains "$f" "$t"; done
	f=$(skill implement)
	for t in "implementer" "criterion id" "test first" "./softwary verify" "three attempts" "weaken" ".softwary/config/" "blueprint"; do assert_contains "$f" "$t"; done
	f=$(skill review)
	for t in "reviewer" "./softwary risk" ".softwary/templates/review.md" "decision: approve"; do assert_contains "$f" "$t"; done
}

# AC-M4-04: the reviewer and the spec analyst edit nothing but the review
# record; review and plan hand over to a fresh session where a tool has no
# subagents.
test_ac_m4_04_clean_context_roles() {
	for a in reviewer spec-analyst; do
		assert_contains "$(agent "$a")" "Do not edit code"
		assert_contains "$(agent "$a")" "clean context"
	done
	assert_contains "$(agent reviewer)" "reviews/S<n>.md"
	assert_contains "$(agent spec-analyst)" "Do not edit the spec"
	for s in review plan; do
		assert_contains "$(skill "$s")" "fresh session"
	done
}

# AC-M4-07: the setup skill asks for src_paths.
test_ac_m4_07_setup_names_src_paths() {
	assert_contains "$(skill setup)" "src_paths"
}

run_tests "$0"
