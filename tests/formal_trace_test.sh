#!/bin/sh
# Tests for the part of V8 that narrows the gap between a model and the code:
# `formal trace` prints the counter-example of a finding as steps a test can
# replay, and `states tests` lists the tests a state machine owes. The tests
# that run TLC need Java and the pinned jar (SW_SKIP_FORMAL=<reason> skips
# them, visibly).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

F=architecture/formal
MD=$F/order.md
FOUND='| `ShippedWasPaid` | 2999-12-31 | The old order code ships a created order. |'

# legacy_repo: the order model describes code that ships an unpaid order, and
# the record has that as a finding.
legacy_repo() {
	setup_repo
	add_product
	add_blueprint
	add_formal
	cp "$FORMALFIX/broken/order.cfg" "$REPO/$F/order.cfg"
	printf '\n## Findings\n\n| Invariant | Until | Reason |\n| --- | --- | --- |\n%s\n' "$FOUND" >>"$REPO/$MD"
}

# AC-V8-07: the finding's counter-example: the id first, then the steps in the
# record's sentences, as formal check prints them.
test_ac_v8_07_trace_of_a_finding() {
	need_tlc || return 0
	legacy_repo
	sw formal trace order ShippedWasPaid
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(sed -n 1p "$OUT")" "CE-order-ShippedWasPaid" "first line"
	assert_match "$OUT" '^  1\. A new order is created and has not been paid \(Init\): everShipped = FALSE, paid = FALSE, status = "created"$'
	assert_match "$OUT" '^  2\. A paid order is shipped \(ship\): everShipped = TRUE, status = "shipped"$'
	assert_eq "$(wc -l <"$OUT" | tr -d ' ')" 3 "lines"
	[ -z "$(find "$REPO/$F" -name '*TTrace*' -o -name states)" ] || fail "TLC left files in architecture/formal"
}

# AC-V8-07: an invariant that has no finding has no counter-example to replay:
# a usage error that says so, and so are an unknown specification and a wrong
# number of words.
test_ac_v8_07_no_finding_unknown_and_usage() {
	legacy_repo
	sw formal trace order CancelledNeverShipped
	assert_eq "$RC" 2 "exit code for an invariant without a finding"
	assert_match "$OUT" "^formal trace: order has no finding for CancelledNeverShipped$"
	sw formal trace order Ghost
	assert_eq "$RC" 2 "exit code for an unknown invariant"
	sw formal trace ghost ShippedWasPaid
	assert_eq "$RC" 2 "exit code for an unknown specification"
	assert_match "$OUT" "^formal trace: no specification 'ghost' "
	sw formal trace order
	assert_eq "$RC" 2 "exit code for a missing invariant"
	assert_match "$OUT" "^usage: ./softwary formal "
}

# AC-V8-07: a finding that the model no longer breaks is exit 1: the finding
# is stale, and there is no path.
test_ac_v8_07_no_longer_violated() {
	need_tlc || return 0
	legacy_repo
	cp "$FORMALFIX/architecture/formal/order.cfg" "$REPO/$F/order.cfg"
	sw formal trace order ShippedWasPaid
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal trace: ShippedWasPaid is not violated by the model of order any more \\(remove the finding\\)$"
	assert_no_match "$OUT" "^CE-"
}

# AC-V8-07: without TLC the command says what to do and is exit 2.
test_ac_v8_07_needs_tlc() {
	legacy_repo
	RC=0
	(cd "$REPO" && SW_TLA2TOOLS=$T/none.jar ./softwary formal trace order ShippedWasPaid) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "./softwary formal install"
}

# states_repo: the order's state machine and nothing else of the blueprint.
states_repo() {
	setup_repo
	add_product
	add_blueprint
	add_formal
}

# AC-V8-08: every state with every event of the machine: a line that says what
# the code must do, 4 states by 3 events for the order, in the order of the
# file (states as declared, events as they first appear).
test_ac_v8_08_obligations_of_the_order() {
	states_repo
	sw states tests
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(wc -l <"$OUT" | tr -d ' ')" 12 "lines"
	assert_eq "$(sed -n 1,3p "$OUT" | paste -sd, -)" "ST-order-created-pay allowed -> paid,ST-order-created-cancel allowed -> cancelled,ST-order-created-ship refused" "first lines"
	assert_match "$OUT" "^ST-order-paid-ship allowed -> shipped$"
	assert_match "$OUT" "^ST-order-paid-cancel allowed -> cancelled$"
	assert_match "$OUT" "^ST-order-paid-pay refused$"
	assert_match "$OUT" "^ST-order-shipped-cancel refused$"
	assert_match "$OUT" "^ST-order-cancelled-pay refused$"
	assert_eq "$(grep -c ' allowed -> ' "$OUT")" 4 "allowed"
	assert_eq "$(grep -c ' refused$' "$OUT")" 8 "refused"
}

# AC-V8-08: a name selects one machine; every machine is listed otherwise; an
# unknown name is a usage error.
test_ac_v8_08_entity_filter() {
	states_repo
	jq '.entity = "ticket" | .formal = "ticket"' "$REPO/architecture/states/order.json" >"$REPO/architecture/states/ticket.json"
	sw states tests
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(wc -l <"$OUT" | tr -d ' ')" 24 "lines"
	sw states tests ticket
	assert_eq "$RC" 0 "exit code for one entity"
	assert_eq "$(wc -l <"$OUT" | tr -d ' ')" 12 "lines for one entity"
	assert_no_match "$OUT" "^ST-order-"
	sw states tests ghost
	assert_eq "$RC" 2 "exit code for an unknown entity"
	assert_match "$OUT" "^states: no state machine 'ghost' "
	sw states
	assert_eq "$RC" 2 "exit code without a subcommand"
	assert_match "$OUT" "^usage: ./softwary states tests"
}

# AC-V8-08: the command lists what is in the files and writes nothing.
test_ac_v8_08_writes_nothing() {
	states_repo
	snapshot >"$T/before"
	sw states tests
	assert_eq "$RC" 0 "exit code"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "paths changed"
}

# AC-V8-08: `help` lists the command.
test_ac_v8_08_help_lists_the_commands() {
	setup_repo
	sw help
	assert_match "$OUT" "^  states tests "
	assert_match "$OUT" "^  formal verified "
	assert_contains "$OUT" "formal trace <spec> <invariant>"
}

run_tests "$0"
