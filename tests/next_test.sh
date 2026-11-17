#!/bin/sh
# Tests for ./softwary next and ./softwary handoff (V5).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

HANDOFF_REL=.softwary/state/handoff.md

# next_is STEP: `next` exits 0, prints exactly one line, and it starts with
# "next: STEP (" and ends with ")".
next_is() {
	sw next
	assert_eq "$RC" 0 "next exit code"
	assert_eq "$(wc -l <"$OUT" | tr -d ' ')" 1 "lines of next"
	case $(cat "$OUT") in
	"next: $1 ("*")") ;;
	*) fail "expected next: $1 (<reason>), got [$(cat "$OUT")]" ;;
	esac
}

# AC-V5-10: from an empty repository to the end of the plan, each step the
# files call for, in order, with a reason.
test_ac_v5_10_each_step() {
	setup_repo
	conf_all true
	next_is define
	assert_contains "$OUT" "product/PRODUCT.md"
	add_product
	sed 's/^Small teams lose track of who does what\.$/UNSET/' "$REPO/product/PRODUCT.md" >"$T/p" && mv "$T/p" "$REPO/product/PRODUCT.md"
	next_is define
	assert_contains "$OUT" "product check"
	add_product
	next_is "approve product (human)"
	sw approve product
	next_is blueprint
	add_blueprint
	next_is critique
	assert_contains "$OUT" "no critique"
	add_critique changes
	next_is critique
	add_critique pass
	next_is "approve blueprint (human)"
	sw approve blueprint
	next_is plan
	assert_contains "$OUT" "no spec"
	add_plan
	next_is run
	assert_contains "$OUT" "planned"
}

# AC-V5-10: a stale approval or critique sends the project back a step.
test_ac_v5_10_stale_steps() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	next_is run
	printf '\n' >>"$REPO/architecture/data/model.json"
	next_is critique
	assert_contains "$OUT" "stale"
	add_critique pass
	next_is "approve blueprint (human)"
	assert_contains "$OUT" "stale"
	printf '\n' >>"$REPO/product/PRODUCT.md"
	next_is "approve product (human)"
}

# AC-V5-10: a draft spec whose analysis passes for this version is approved with
# plan approve; without a current analysis the plan stage goes on.
test_ac_v5_10_draft_spec() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	rm -r "$REPO/specs/002-tasks"
	fm_set "$REPO/specs/001-login/spec.md" status draft
	next_is plan
	assert_contains "$OUT" "analysis"
	printf -- '---\nspec: 001\ndigest: %s\ndecision: pass\n---\n' "$(git -C "$REPO" hash-object specs/001-login/spec.md)" >"$REPO/specs/001-login/analysis.md"
	next_is "plan approve 001"
	printf -- '---\nspec: 001\ndigest: %s\ndecision: fail\n---\n' "$(git -C "$REPO" hash-object specs/001-login/spec.md)" >"$REPO/specs/001-login/analysis.md"
	next_is plan
	printf '\nmore\n' >>"$REPO/specs/001-login/spec.md"
	next_is plan
}

# AC-V5-10: an open run with a job that waits for a human says so; a run with
# nothing left says none.
test_ac_v5_10_waiting_and_none() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	open_run
	mkdir -p "$REPO/.softwary/state/jobs/001-S1"
	printf 'state=escalated\nround=1\n' >"$REPO/.softwary/state/jobs/001-S1/job"
	next_is "waiting: 001-S1"
	rm -r "$REPO/.softwary/state/jobs" "$REPO/specs/002-tasks"
	for f in "$REPO"/specs/*/slices/*.md; do fm_set "$f" status in-progress; done
	next_is none
}

# AC-V5-10: the specifications are not run: next looks at their files only, and
# says that the models were not checked when Java is missing.
test_ac_v5_10_does_not_run_tlc() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	add_formal
	sw approve product
	mkdir -p "$T/bin"
	printf '#!/bin/sh\ntouch "%s/java-ran"\nexit 1\n' "$T" >"$T/bin/java"
	chmod +x "$T/bin/java"
	RC=0
	(PATH=$T/bin:$PATH && export PATH && cd "$REPO" && ./softwary next) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^next: critique \("
	assert_contains "$OUT" "formal check was not run"
	[ ! -e "$T/java-ran" ] || fail "next ran TLC"
}

# AC-V5-10: a broken record of a specification is a blueprint step.
test_ac_v5_10_broken_specification() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	add_formal
	sw approve product
	rm "$REPO/architecture/formal/order.cfg"
	next_is blueprint
	assert_contains "$OUT" "order.cfg"
}

# AC-V5-10: next reads and writes nothing.
test_ac_v5_10_writes_nothing() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	snapshot >"$T/before"
	sw next
	assert_eq "$RC" 0 "exit code"
	snapshot >"$T/after"
	cmp -s "$T/before" "$T/after" || fail "next wrote: $(changed_paths "$T/before" "$T/after")"
	sw next extra
	assert_eq "$RC" 2 "usage error"
}

# AC-V5-11: handoff writes the file, prints its path and gathers where we are.
test_ac_v5_11_handoff_sections() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	commit_all "base"
	printf 'x\n' >"$REPO/untracked.txt"
	open_run
	mkdir -p "$REPO/.softwary/state/jobs/001-S1"
	printf 'state=escalated\nround=1\n' >"$REPO/.softwary/state/jobs/001-S1/job"
	printf 'Which hash function?\n' >"$REPO/.softwary/state/jobs/001-S1/escalation"
	sw handoff
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(cat "$OUT")" "$HANDOFF_REL" "printed path"
	f=$REPO/$HANDOFF_REL
	for h in "# Handoff" "## Where" "## Working tree" "## Next" "## Approvals" "## Jobs" "## Recent events" "## Notes"; do
		assert_match "$f" "^$h\$"
	done
	assert_match "$f" "^- time: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z$"
	assert_match "$f" "^- branch: main$"
	assert_match "$f" "^- commit: [0-9a-f]{7,} base$"
	assert_match "$f" "^\?\? untracked\.txt$"
	assert_match "$f" "^next: waiting: 001-S1 \("
	assert_match "$f" "^approval product: approved$"
	assert_match "$f" "^approval blueprint: approved$"
	assert_match "$f" "^job 001-S1 +escalated"
	assert_contains "$f" "Which hash function?"
	assert_match "$f" "approve_blueprint"
}

# AC-V5-11: only the last ten events; the notes of an earlier handoff survive.
test_ac_v5_11_notes_kept() {
	setup_repo
	conf_all true
	commit_all "base"
	i=0
	mkdir -p "$REPO/.softwary/state"
	while [ "$i" -lt 14 ]; do
		i=$((i + 1))
		printf '{"time":"2026-11-17T10:00:%02dZ","job":"-","event":"e%s","from":"-","to":"-","detail":""}\n' "$i" "$i" >>"$REPO/.softwary/state/events.log"
	done
	sw handoff
	assert_eq "$RC" 0 "exit code"
	f=$REPO/$HANDOFF_REL
	assert_match "$f" "e14"
	assert_match "$f" "e5"
	assert_no_match "$f" "e4( |\$)"
	printf '\nThe flaky test is test_login; do not retry it.\n\n### Open\n\nAsk about the logo.\n' >>"$f"
	sw handoff
	assert_eq "$RC" 0 "second exit code"
	assert_contains "$f" "The flaky test is test_login; do not retry it."
	assert_contains "$f" "### Open"
	assert_contains "$f" "Ask about the logo."
	assert_eq "$(grep -c '^## Notes$' "$f")" 1 "notes sections"
}

# AC-V5-11: before the first commit, and the handoff skill.
test_ac_v5_11_empty_repository_and_skill() {
	setup_repo
	conf_all true
	sw handoff
	assert_eq "$RC" 0 "exit code"
	assert_match "$REPO/$HANDOFF_REL" "^- commit: none yet$"
	f=$PKG_ROOT/src/skills/handoff/SKILL.md
	[ -f "$f" ] || fail "src/skills/handoff/SKILL.md missing"
	assert_contains "$f" "./softwary handoff"
	assert_contains "$f" "## Notes"
	assert_contains "$f" ".softwary/state/handoff.md"
	assert_contains "$f" "read"
	[ "$(wc -l <"$f" | tr -d ' ')" -le 80 ] || fail "handoff skill is longer than 80 lines"
	sw handoff extra
	assert_eq "$RC" 2 "usage error"
}

run_tests "$0"
