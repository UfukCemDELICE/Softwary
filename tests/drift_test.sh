#!/bin/sh
# Tests for ./softwary drift and architecture/drift.md (V7).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

DRIFT_REL=architecture/drift.md
FAR=2999-12-31

# drift_repo: a repository whose model covers its source: src/core/a.sh under
# src_paths = src, a test under tests/. Everything is committed.
drift_repo() {
	setup_repo --no-model
	conf_all true
	conf_set test_paths tests
	rm -f "$REPO/src/.gitkeep"
	mkdir -p "$REPO/src/core" "$REPO/tests"
	printf 'a\n' >"$REPO/src/core/a.sh"
	printf 't\n' >"$REPO/tests/t.sh"
	core_model '["src/core/*"]' active
	commit_all "base"
}

# write_drift: architecture/drift.md with the rows given on stdin.
write_drift() {
	mkdir -p "$REPO/architecture"
	{
		printf '# Drift decisions\n\nWhat the human decided about each difference.\n\n'
		printf '| Item | Decision | Until | Reason |\n| --- | --- | --- | --- |\n'
		cat
	} >"$REPO/$DRIFT_REL"
}

# AC-V7-08: a model that covers the code and no examples to exercise: nothing
# to report, exit 0.
test_ac_v7_08_clean() {
	drift_repo
	sw drift
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^drift: 0 item\(s\), 0 undecided$"
	assert_eq "$(wc -l <"$OUT" | tr -d ' ')" 1 "lines"
}

# AC-V7-08: a tracked file under src_paths that no node owns is uncovered; an
# untracked one, one outside src_paths and one a node owns are not.
test_ac_v7_08_uncovered() {
	drift_repo
	printf 'x\n' >"$REPO/src/extra.sh"
	printf 'x\n' >"$REPO/docs.txt"
	commit_all "extra"
	printf 'x\n' >"$REPO/src/untracked.sh"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: uncovered src/extra\.sh: undecided$"
	assert_no_match "$OUT" "untracked"
	assert_no_match "$OUT" "docs\.txt"
	assert_no_match "$OUT" "src/core/a\.sh"
	assert_match "$OUT" "^drift: 1 item\(s\), 1 undecided$"
}

# AC-V7-08: a node path that does not exist is missing, for the path that is
# gone and not for the one that is there; a planned node has no code yet and
# is not reported.
test_ac_v7_08_missing() {
	drift_repo
	core_model '["src/core/*", "src/gone/*", "lib/gone.sh"]' active
	commit_all "paths"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: missing core src/gone/\*: undecided$"
	assert_match "$OUT" "^drift: missing core lib/gone\.sh: undecided$"
	assert_no_match "$OUT" "missing core src/core"
	core_model '["src/core/*", "src/gone/*"]' planned
	commit_all "planned"
	sw drift
	assert_no_match "$OUT" "^drift: missing"
}

# AC-V7-08: an active node without a file is empty.
test_ac_v7_08_empty() {
	drift_repo
	core_model '["src/nothing/*"]' active
	commit_all "no code"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: empty core: undecided$"
	core_model '["src/nothing/*"]' deprecated
	commit_all "deprecated"
	sw drift
	assert_no_match "$OUT" "^drift: empty"
}

# AC-V7-08: a planned node that has code is planned-with-code.
test_ac_v7_08_planned_with_code() {
	drift_repo
	core_model '["src/core/*"]' planned
	commit_all "planned"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: planned-with-code core: undecided$"
	assert_no_match "$OUT" "^drift: (empty|missing)"
}

# AC-V7-08: an example whose criteria no test under test_paths names is
# unexercised: the one that has a test is not, and neither is one named only
# in a file outside test_paths.
test_ac_v7_08_unexercised() {
	drift_repo
	add_product
	add_plan
	printf '# covers AC-001-01\n' >"$REPO/tests/test_login.py"
	printf '# covers AC-001-02 AC-002-01\n' >"$REPO/src/core/notes.txt"
	commit_all "product, plan and a test"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_no_match "$OUT" "EX-F1-01"
	assert_match "$OUT" "^drift: unexercised EX-F1-02: undecided$"
	assert_match "$OUT" "^drift: unexercised EX-F2-01: undecided$"
	assert_match "$OUT" "^drift: 2 item\(s\), 2 undecided$"
	# an example that no criterion names has no test at all
	sed 's/ Covers EX-F2-01\.//' "$REPO/specs/002-tasks/spec.md" >"$T/s" && cp "$T/s" "$REPO/specs/002-tasks/spec.md"
	sw drift
	assert_match "$OUT" "^drift: unexercised EX-F2-01: undecided$"
}

# AC-V7-08: without a product definition there is no example to exercise.
test_ac_v7_08_no_product() {
	drift_repo
	sw drift
	assert_no_match "$OUT" "unexercised"
}

# AC-V7-08: the three decisions; a decided item shows its decision and date,
# and with every item decided the exit code is 0.
test_ac_v7_08_decisions() {
	drift_repo
	add_product
	add_plan
	printf 'x\n' >"$REPO/src/extra.sh"
	commit_all "extra"
	write_drift <<ROWS
| uncovered src/extra.sh | accept | $FAR | the old import path |
| unexercised EX-F1-01 | blueprint | $FAR | the model should name it |
| unexercised EX-F1-02 | fix 001 | $FAR | specified in spec 001 |
| unexercised EX-F2-01 | accept | $FAR | manual check |
ROWS
	sw drift
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^drift: uncovered src/extra\.sh: decided \(accept, until $FAR\)$"
	assert_match "$OUT" "^drift: unexercised EX-F1-01: decided \(blueprint, until $FAR\)$"
	assert_match "$OUT" "^drift: unexercised EX-F1-02: decided \(fix 001, until $FAR\)$"
	assert_match "$OUT" "^drift: 4 item\(s\), 0 undecided$"
}

# AC-V7-08: a decision that is not one of the three, a fix that names no spec
# or one that does not exist, a bad date and an empty reason leave the item
# undecided, each with its own reason; the file's other rows still count.
test_ac_v7_08_invalid_decisions() {
	drift_repo
	for f in a b c d e g; do printf 'x\n' >"$REPO/src/$f.sh"; done
	commit_all "extra"
	write_drift <<ROWS
| uncovered src/a.sh | later | $FAR | no |
| uncovered src/b.sh | fix | $FAR | no spec |
| uncovered src/c.sh | fix 099 | $FAR | no such spec |
| uncovered src/d.sh | accept | 2999-02-30 | bad date |
| uncovered src/e.sh | accept | $FAR |  |
| uncovered src/g.sh | accept | $FAR | fine |
ROWS
	add_plan
	commit_all "plan"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: uncovered src/a\.sh: undecided \(decision 'later' is not accept, blueprint or fix <spec>\)$"
	assert_match "$OUT" "^drift: uncovered src/b\.sh: undecided \(fix needs a spec number\)$"
	assert_match "$OUT" "^drift: uncovered src/c\.sh: undecided \(fix 099: no such spec\)$"
	assert_match "$OUT" "^drift: uncovered src/d\.sh: undecided \(invalid date '2999-02-30'"
	assert_match "$OUT" "^drift: uncovered src/e\.sh: undecided \(no reason\)$"
	assert_match "$OUT" "^drift: uncovered src/g\.sh: decided \(accept, until $FAR\)$"
	assert_match "$OUT" "^drift: 6 item\(s\), 5 undecided$"
}

# AC-V7-08: a decision whose date has passed is expired and holds the exit
# code at 1; one that is still in force does not.
test_ac_v7_08_expired() {
	drift_repo
	printf 'x\n' >"$REPO/src/a.sh"
	printf 'x\n' >"$REPO/src/b.sh"
	commit_all "extra"
	write_drift <<ROWS
| uncovered src/a.sh | accept | 2000-01-01 | was fine once |
| uncovered src/b.sh | accept | $FAR | fine |
ROWS
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: uncovered src/a\.sh: expired 2000-01-01$"
	assert_match "$OUT" "^drift: uncovered src/b\.sh: decided \(accept, until $FAR\)$"
	assert_match "$OUT" "^drift: 2 item\(s\), 1 undecided$"
}

# AC-V7-08: the decision of an item that is gone is stale: reported, and it
# does not by itself fail drift.
test_ac_v7_08_stale_decision() {
	drift_repo
	write_drift <<ROWS
| uncovered src/gone.sh | accept | $FAR | the file was removed |
ROWS
	sw drift
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^drift: uncovered src/gone\.sh: stale decision \(remove it\)$"
	assert_match "$OUT" "^drift: 0 item\(s\), 0 undecided$"
}

# AC-V7-08: two rows for one item are not a decision: which of them holds is
# not clear, so the item stays undecided.
test_ac_v7_08_duplicate_rows() {
	drift_repo
	printf 'x\n' >"$REPO/src/a.sh"
	commit_all "extra"
	write_drift <<ROWS
| uncovered src/a.sh | accept | $FAR | the first |
| uncovered src/a.sh | blueprint | $FAR | the second |
ROWS
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: uncovered src/a\\.sh: undecided \\(more than one decision row\\)$"
}

# AC-V7-08: a table with other columns, or no table, decides nothing.
test_ac_v7_08_no_table_decides_nothing() {
	drift_repo
	printf 'x\n' >"$REPO/src/a.sh"
	commit_all "extra"
	printf '# Drift\n\n| Item | Verdict |\n| --- | --- |\n| uncovered src/a.sh | accept |\n' >"$REPO/$DRIFT_REL"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: uncovered src/a\.sh: undecided$"
	printf 'no table\n' >"$REPO/$DRIFT_REL"
	sw drift
	assert_eq "$RC" 1 "exit code with no table"
}

# AC-V7-08: with src_paths = . and nodes inside each other, the code of a
# node is covered by it or by the node within it; the package's own files, the
# generated ones and the views are not counted, the project's other files are.
test_ac_v7_08_dot_src_paths_and_nested_nodes() {
	drift_repo
	conf_set src_paths .
	tools_set claude-code on
	mkdir -p "$REPO/src/core/deep"
	printf 'x\n' >"$REPO/src/core/deep/b.sh"
	core_model '["src/core"]' active '{ "unique-id": "deep", "node-type": "service", "name": "Deep", "description": "Inside core.", "metadata": { "paths": ["src/core/deep/*"], "risk": "R1", "status": "active" } }'
	sw sync
	assert_eq "$RC" 0 "sync"
	commit_all "dot"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_no_match "$OUT" "uncovered src/core/"
	assert_no_match "$OUT" "uncovered \.softwary/"
	assert_no_match "$OUT" "uncovered \.claude/"
	assert_no_match "$OUT" "uncovered architecture/views/"
	assert_match "$OUT" "^drift: uncovered tests/t\.sh: undecided$"
	assert_match "$OUT" "^drift: uncovered softwary: undecided$"
	assert_match "$OUT" "^drift: uncovered architecture/model/system\.calm\.json: undecided$"
	# the node inside the first one is not empty for owning only its own files
	assert_no_match "$OUT" "^drift: empty"
	# a path with a trailing slash and a leading ./ names the same directory
	core_model '["./src/core/"]' active
	commit_all "slashes"
	sw drift
	assert_no_match "$OUT" "uncovered src/core/"
	assert_no_match "$OUT" "^drift: (missing|empty)"
}

# AC-V7-08: drift needs a model and a usable src_paths: exit 2 and no report.
test_ac_v7_08_configuration() {
	drift_repo
	rm "$REPO/$MODEL_REL"
	sw drift
	assert_eq "$RC" 2 "exit code without a model"
	assert_match "$OUT" "^drift: no model"
	core_model '["src/core/*"]' active
	conf_del src_paths
	sw drift
	assert_eq "$RC" 2 "exit code without src_paths"
	assert_match "$OUT" "src_paths"
	conf_set src_paths src
	sw drift extra
	assert_eq "$RC" 2 "exit code with an argument"
	assert_contains "$OUT" "usage: ./softwary drift"
}

# AC-V7-08: examples need test_paths to be looked up.
test_ac_v7_08_examples_need_test_paths() {
	drift_repo
	add_product
	add_plan
	conf_set test_paths UNSET
	sw drift
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^drift: test_paths is not set"
}

# AC-V7-08: drift writes nothing and is not one of verify's checks.
test_ac_v7_08_reads_only_and_is_not_in_verify() {
	drift_repo
	printf 'x\n' >"$REPO/src/a.sh"
	commit_all "extra"
	snapshot >"$T/before"
	sw drift
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after" | grep -v '^\.softwary/state/' || :)" "" "paths drift changed"
	sw verify --base main
	assert_eq "$RC" 0 "verify exit code with an undecided drift item"
	assert_no_match "$OUT" "drift"
	! grep -n 'drift' "$PKG_ROOT/src/lib/verify.sh" >/dev/null || fail "verify.sh mentions drift"
}

# AC-V7-08: architecture/drift.md is a protected path: a job that edits it
# fails the guard.
test_ac_v7_08_drift_md_is_protected() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_plan
	mkdir -p "$REPO/tests" "$REPO/src/api"
	printf '# covers AC-001-01\n' >"$REPO/tests/test_login.py"
	printf 'code\n' >"$REPO/src/api/login.py"
	add_origin
	git -C "$REPO" checkout -q -b softwary/001-S1
	write_drift <<ROWS
| uncovered src/api/login.py | accept | $FAR | the job decides for itself |
ROWS
	commit_all "decide"
	sw guard 001-S1 --base main
	assert_eq "$RC" 1 "guard exit code"
	assert_match "$OUT" "^guard: protected: architecture/drift\.md$"
}

# AC-V7-08: the template is installed and its table has the columns drift reads.
test_ac_v7_08_template() {
	setup_repo
	t=$REPO/.softwary/templates/drift.md
	[ -s "$t" ] || fail "the drift.md template is not installed"
	assert_contains "$t" "| Item | Decision | Until | Reason |"
	cp "$t" "$REPO/$DRIFT_REL"
	printf 'x\n' >"$REPO/src/a.sh"
	sw drift
	assert_no_match "$OUT" ": decided|stale"
}

# order_repo: drift_repo with the order's state machine and the record of its
# model, which has a finding: twelve tests the machine owes and one
# counter-example to replay. Everything is committed.
order_repo() {
	drift_repo
	cp -R "$FORMALFIX/architecture/." "$REPO/architecture/"
	printf '\n## Findings\n\n| Invariant | Until | Reason |\n| --- | --- | --- |\n| `ShippedWasPaid` | %s | The old order code ships a created order. |\n' "$FAR" \
		>>"$REPO/architecture/formal/order.md"
	commit_all "the order model"
}

# order_ids: the identifiers of the tests the order owes, then the finding's.
order_ids() {
	sw states tests
	[ "$RC" -eq 0 ] || fail "states tests: $(cat "$OUT")"
	cut -d' ' -f1 "$OUT"
	printf 'CE-order-ShippedWasPaid\n'
}

# AC-V8-09: a state machine owes a test for every state and event, and a
# finding a test that replays its counter-example: until the tests name them
# they are drift, an item each.
test_ac_v8_09_untested_and_unreplayed() {
	order_repo
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_eq "$(grep -c '^drift: untested ST-order-[a-z_]*-[a-z_]*: undecided$' "$OUT")" 12 "untested"
	assert_match "$OUT" "^drift: untested ST-order-created-pay: undecided$"
	assert_match "$OUT" "^drift: untested ST-order-cancelled-ship: undecided$"
	assert_match "$OUT" "^drift: unreplayed CE-order-ShippedWasPaid: undecided$"
	assert_match "$OUT" "^drift: 13 item\\(s\\), 13 undecided$"
	# the new items come last
	assert_eq "$(sed -n 1p "$OUT")" "drift: untested ST-order-created-pay: undecided" "first line"
}

# AC-V8-09: a test under test_paths that names the identifier closes the item;
# the others stay.
test_ac_v8_09_a_test_names_it() {
	order_repo
	printf '# covers ST-order-paid-ship and CE-order-ShippedWasPaid\n' >>"$REPO/tests/t.sh"
	commit_all "a test"
	sw drift
	assert_no_match "$OUT" "ST-order-paid-ship:"
	assert_no_match "$OUT" "CE-order-ShippedWasPaid"
	assert_match "$OUT" "^drift: untested ST-order-paid-cancel: undecided$"
	assert_match "$OUT" "^drift: 11 item\\(s\\), 11 undecided$"
	order_ids | sed 's/^/# /' >>"$REPO/tests/t.sh"
	commit_all "every identifier"
	sw drift
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^drift: 0 item\\(s\\), 0 undecided$"
}

# AC-V8-09: only the tests close an item: a source file that names the
# identifier does not, and neither does a file git does not track.
test_ac_v8_09_only_tracked_tests_count() {
	order_repo
	order_ids | sed 's/^/# /' >"$REPO/src/core/notes.txt"
	commit_all "the identifiers in the source"
	order_ids | sed 's/^/# /' >"$REPO/tests/untracked.sh"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^drift: 13 item\\(s\\), 13 undecided$"
}

# AC-V8-09: an identifier is a word: a longer one that starts with it, or that
# it is the end of, is another; punctuation around it is not part of it.
test_ac_v8_09_identifier_is_a_word() {
	order_repo
	{
		printf '# ST-order-paid-shipped ST-order-paid-ship_x ST-order-paid-ship-y\n'
		printf '# XST-order-paid-ship TEST-order-paid-ship CE-order-ShippedWasPaid2\n'
	} >>"$REPO/tests/t.sh"
	commit_all "near misses"
	sw drift
	assert_match "$OUT" "^drift: untested ST-order-paid-ship: undecided$"
	assert_match "$OUT" "^drift: unreplayed CE-order-ShippedWasPaid: undecided$"
	printf 'check "(ST-order-paid-ship)", ST-order-paid-ship. CE-order-ShippedWasPaid;\n' >>"$REPO/tests/t.sh"
	commit_all "the words"
	sw drift
	assert_no_match "$OUT" "ST-order-paid-ship:"
	assert_no_match "$OUT" "CE-order-ShippedWasPaid"
}

# AC-V8-09: the decisions of V7 hold for the new items: accept, with a date and
# a reason, decides them; with each decided the exit code is 0.
test_ac_v8_09_decisions() {
	order_repo
	sw drift
	{
		printf '# Drift decisions\n\n| Item | Decision | Until | Reason |\n| --- | --- | --- | --- |\n'
		sed -n "s/^drift: \\(.*\\): undecided\$/| \\1 | accept | $FAR | checked by hand |/p" "$OUT"
	} >"$REPO/$DRIFT_REL"
	sw drift
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^drift: untested ST-order-paid-ship: decided \\(accept, until $FAR\\)$"
	assert_match "$OUT" "^drift: unreplayed CE-order-ShippedWasPaid: decided \\(accept, until $FAR\\)$"
	assert_match "$OUT" "^drift: 13 item\\(s\\), 0 undecided$"
	sed 's/| 2999-12-31 | checked by hand |$/| 2000-01-01 | checked by hand |/' "$REPO/$DRIFT_REL" >"$T/d" && cp "$T/d" "$REPO/$DRIFT_REL"
	sw drift
	assert_eq "$RC" 1 "exit code with every decision expired"
	assert_match "$OUT" "^drift: unreplayed CE-order-ShippedWasPaid: expired 2000-01-01$"
}

# AC-V8-09: the findings of a record are counter-examples whether or not they
# are expired; a machine without a record's findings owes tests only.
test_ac_v8_09_findings_and_machines() {
	order_repo
	sed 's/2999-12-31/2000-01-01/' "$REPO/architecture/formal/order.md" >"$T/m" && cp "$T/m" "$REPO/architecture/formal/order.md"
	sw drift
	assert_match "$OUT" "^drift: unreplayed CE-order-ShippedWasPaid: undecided$"
	awk '/^## Findings/ { exit } { print }' "$REPO/architecture/formal/order.md" >"$T/m" && cp "$T/m" "$REPO/architecture/formal/order.md"
	sw drift
	assert_no_match "$OUT" "unreplayed"
	assert_match "$OUT" "^drift: 12 item\\(s\\), 12 undecided$"
	rm -r "$REPO/architecture/states"
	sw drift
	assert_no_match "$OUT" "untested"
}

# AC-V8-09: with state machines or findings and no test_paths to look in,
# drift cannot say: exit 2 and why.
test_ac_v8_09_needs_test_paths() {
	order_repo
	conf_set test_paths UNSET
	sw drift
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^drift: test_paths is not set"
}

run_tests "$0"
