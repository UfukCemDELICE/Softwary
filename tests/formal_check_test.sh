#!/bin/sh
# Tests for the specification records of ./softwary blueprint check and for
# ./softwary formal check|install and model_check (V5). The tests that run TLC
# need Java and the pinned jar (SW_SKIP_FORMAL=<reason> skips them, visibly).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

F=architecture/formal
MD=$F/order.md

# ready: a repo whose blueprint has the order's state machine and TLA+ model.
ready() {
	rm -rf "$T/repo"
	setup_repo
	add_product
	add_blueprint
	add_formal
}

# md_drop PATTERN: deletes the lines of the record that match the ERE.
md_drop() {
	grep -Ev -e "$1" "$REPO/$MD" >"$T/md.tmp" || :
	mv "$T/md.tmp" "$REPO/$MD"
}

# md_sub FROM TO: replaces the fixed text FROM by TO in the record.
md_sub() {
	awk -v f="$1" -v t="$2" '{ while ((i = index($0, f)) > 0) $0 = substr($0, 1, i - 1) t substr($0, i + length(f)); print }' \
		"$REPO/$MD" >"$T/md.tmp"
	mv "$T/md.tmp" "$REPO/$MD"
}

# AC-V5-03: a formal reference needs the model, its configuration and the
# record; every missing file is a line of its own, naming who asked for it.
test_ac_v5_03_missing_files() {
	ready
	rm "$REPO/$F/order.tla" "$REPO/$F/order.cfg" "$REPO/$MD"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	for ext in tla cfg md; do
		assert_match "$OUT" "^$F/order\\.$ext: not found \\(named by architecture/states/order\\.json\\)$"
	done
}

# AC-V5-03: a flow's reference counts too; a model nobody names still needs
# its configuration and record.
test_ac_v5_03_flow_reference_and_orphan_model() {
	ready
	jq '.traits = ["retry"] | .formal = "signin"' "$REPO/architecture/flows/signin.json" >"$T/f" &&
		mv "$T/f" "$REPO/architecture/flows/signin.json"
	cp "$REPO/$F/order.tla" "$REPO/$F/lonely.tla"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$F/signin\\.tla: not found \\(named by architecture/flows/signin\\.json\\)$"
	assert_match "$OUT" "^$F/lonely\\.cfg: not found$"
	assert_match "$OUT" "^$F/lonely\\.md: not found$"
}

# AC-V5-03: each of the six sections is required.
test_ac_v5_03_missing_sections() {
	ready
	md_drop '^## '
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	for s in "Invariants" "Actions" "Coverage" "Bounds and assumptions" "Last verified" "Variants"; do
		assert_match "$OUT" "^$MD: missing section '## $s'$"
	done
}

# AC-V5-03: an invariant needs a statement and a harm; the tables need their
# columns; an empty list of actions, bounds or coverage is a problem.
test_ac_v5_03_section_contents() {
	ready
	md_sub '| An order that is shipped has been paid for. |' '|  |'
	md_sub '| A customer is refunded for goods that have already left. |' '| |'
	md_sub '| planned | - |' '| src/order.sh | - |'
	md_drop '^- '
	md_sub 'never' 'maybe'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MD: invariant 'ShippedWasPaid' has no statement$"
	assert_match "$OUT" "^$MD: invariant 'CancelledNeverShipped' has no harm$"
	assert_match "$OUT" "^$MD: coverage 'src/order.sh' names no functions \\(or use 'planned'\\)$"
	assert_match "$OUT" "^$MD: '## Bounds and assumptions' has no item$"
	assert_match "$OUT" "^$MD: '## Last verified' must be a 40-digit commit or 'never'$"
	ready
	md_sub '| Name | Statement | Harm |' '| Name | Text |'
	sw blueprint check
	assert_match "$OUT" "^$MD: '## Invariants' table must have the columns Name, Statement, Harm$"
}

# AC-V5-03: an invariant with no variant; a variant that breaks an invariant
# the table does not have; a variant file that does not exist; a badly named one.
test_ac_v5_03_variants() {
	ready
	md_drop 'shipcancelled\.cfg`'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MD: invariant 'CancelledNeverShipped' has no variant that breaks it$"
	ready
	md_sub '| `order-shipcancelled.cfg` | `CancelledNeverShipped` |' '| `order-shipcancelled.cfg` | `Ghost` |'
	sw blueprint check
	assert_match "$OUT" "^$MD: variant 'order-shipcancelled.cfg' breaks 'Ghost', which is not in the invariants table$"
	assert_match "$OUT" "^$MD: invariant 'CancelledNeverShipped' has no variant that breaks it$"
	ready
	rm "$REPO/$F/order-shipunpaid.cfg"
	sw blueprint check
	assert_match "$OUT" "^$MD: variant file 'order-shipunpaid.cfg' not found$"
	ready
	md_sub '`order-shipunpaid.cfg`' '`unpaid.cfg`'
	sw blueprint check
	assert_match "$OUT" "^$MD: variant file 'unpaid.cfg' must be named order-<variant>.cfg$"
}

# AC-V5-03: every event of the state machine is an action of the record.
test_ac_v5_03_event_without_action() {
	ready
	md_drop '^\| `cancel` \|'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^architecture/states/order\\.json: event 'cancel' has no action in $MD$"
	assert_no_match "$OUT" "event 'pay'"
}

# AC-V5-03: the configuration of the good model checks every invariant of the table.
test_ac_v5_03_cfg_checks_every_invariant() {
	ready
	grep -v 'CancelledNeverShipped' "$REPO/$F/order.cfg" >"$T/cfg" && mv "$T/cfg" "$REPO/$F/order.cfg"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$F/order\\.cfg: invariant 'CancelledNeverShipped' of order\\.md is not checked \\(list it under INVARIANTS or PROPERTIES\\)$"
}

# AC-V5-03: the template carries the six sections and is installed.
test_ac_v5_03_template() {
	setup_repo
	t=$REPO/.softwary/templates/formal.md
	[ -f "$t" ] || fail "formal.md template is not installed"
	for s in "Invariants" "Actions" "Coverage" "Bounds and assumptions" "Last verified" "Variants"; do
		assert_match "$t" "^## $s\$"
	done
}

run_tests "$0"
