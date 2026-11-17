#!/bin/sh
# Tests for the state machine files of ./softwary blueprint check (V5).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

STATES_REL=architecture/states/order.json
P=architecture/states/order.json

# ready: a repo whose blueprint has the order's state machine and TLA+ model.
ready() {
	setup_repo
	add_product
	add_blueprint
	add_formal
}

# states_edit FILTER: rewrites the repo's state machine with a jq FILTER.
states_edit() {
	jq "$1" "$REPO/$STATES_REL" >"$T/states.tmp" || fail "jq filter failed: $1"
	mv "$T/states.tmp" "$REPO/$STATES_REL"
}

# AC-V5-02: the sample state machine passes and is counted.
test_ac_v5_02_valid_state_machine_passes() {
	ready
	sw blueprint check
	assert_match "$OUT" "^blueprint: valid \(3 nodes, 3 entities, 2 features\)$"
	assert_match "$OUT" "^blueprint: 1 flow\(s\), 1 state machine\(s\)"
	assert_no_match "$OUT" "$P"
}

# AC-V5-02: invalid JSON and a file that is not an object.
test_ac_v5_02_json_shape() {
	ready
	printf '{ "entity": \n' >"$REPO/$STATES_REL"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with invalid JSON"
	assert_match "$OUT" "^$P: invalid JSON"
	printf '"order"\n' >"$REPO/$STATES_REL"
	sw blueprint check
	assert_match "$OUT" "^$P: \(root\): must be a JSON object$"
}

# AC-V5-02: the file name must be an entity of the data model, and the entity
# field must say the same.
test_ac_v5_02_entity() {
	ready
	mv "$REPO/$STATES_REL" "$REPO/architecture/states/invoice.json"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^architecture/states/invoice\.json: file name 'invoice' is not an entity of the data model$"
	assert_match "$OUT" "^architecture/states/invoice\.json: entity: 'order' must be the file name 'invoice'$"
	mv "$REPO/architecture/states/invoice.json" "$REPO/$STATES_REL"
	states_edit 'del(.entity)'
	sw blueprint check
	assert_match "$OUT" "^$P: entity: missing or not a non-empty string$"
}

# AC-V5-02: initial and every transition end must be a declared state.
test_ac_v5_02_undeclared_states() {
	ready
	states_edit '.initial = "new" | .transitions[0].to = "lost" | .transitions[1].from = "limbo" | .final += ["gone"]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: initial: 'new' is not a declared state$"
	assert_match "$OUT" "^$P: transitions\[0\]\.to: 'lost' is not a declared state$"
	assert_match "$OUT" "^$P: transitions\[1\]\.from: 'limbo' is not a declared state$"
	assert_match "$OUT" "^$P: final\[2\]: 'gone' is not a declared state$"
}

# AC-V5-02: a state that cannot be reached from the initial state.
test_ac_v5_02_unreachable() {
	ready
	states_edit '.states += ["archived"] | .final += ["archived"]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: state 'archived' is not reachable from the initial state 'created'$"
	assert_no_match "$OUT" "state 'shipped'"
}

# AC-V5-02: a state that is not final and has no transition out.
test_ac_v5_02_dead_end() {
	ready
	states_edit '.final = ["cancelled"]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: state 'shipped' has no transition out and is not final$"
	assert_no_match "$OUT" "state 'cancelled'"
}

# AC-V5-02: two transitions from one state on one event.
test_ac_v5_02_nondeterministic() {
	ready
	states_edit '.transitions += [{"from": "created", "event": "pay", "to": "cancelled"}]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: transitions\[4\]: state 'created' already has a transition on event 'pay' \(transitions\[0\]\)$"
}

# AC-V5-02: an event name and a state name must be plain identifiers.
test_ac_v5_02_names() {
	ready
	states_edit '.transitions[0].event = "Pay Now" | .states += ["Half Done"]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: transitions\[0\]\.event: must match \^\[a-z\]\[a-z0-9_\]\*"
	assert_match "$OUT" "^$P: states\[4\]: must match \^\[a-z\]\[a-z0-9_\]\*"
}

# AC-V5-02: a state machine has to name its specification, and the template's
# UNSET is reported.
test_ac_v5_02_formal_required() {
	ready
	states_edit 'del(.formal)'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: formal: missing; every state machine needs a TLA\+ specification$"
	[ -f "$REPO/.softwary/templates/states.json" ] || fail "states.json template is not installed"
	cp "$REPO/.softwary/templates/states.json" "$REPO/$STATES_REL"
	sw blueprint check
	assert_match "$OUT" "^$P: .*is UNSET$"
}

run_tests "$0"
