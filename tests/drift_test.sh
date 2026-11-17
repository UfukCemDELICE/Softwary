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

run_tests "$0"
