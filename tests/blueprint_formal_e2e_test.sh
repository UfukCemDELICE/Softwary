#!/bin/sh
# End-to-end tests of the V5 blueprint with the order fixture (a state machine,
# its TLA+ model, two invariants, a variant for each): blueprint check, the
# critic, approve blueprint, verify with model_check, and a model that really
# breaks an invariant. They need Java and the pinned jar (SW_SKIP_FORMAL=<reason>
# skips them, visibly).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

F=architecture/formal

# AC-V5-13: from the checked blueprint through the critic and the approval to a
# green verify; a changed invariant sentence makes the approval stale.
test_ac_v5_13_end_to_end() {
	need_tlc || return 0
	setup_repo
	conf_all true
	conf_set model_check "./softwary formal check"
	add_product
	add_blueprint
	add_formal
	sw blueprint check
	assert_eq "$RC" 0 "blueprint check exit code"
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg fails on ShippedWasPaid$"
	assert_match "$OUT" "^formal order: PASS \\([0-9]+ states\\)$"
	assert_match "$OUT" "^blueprint: valid \\(3 nodes, 3 entities, 2 features\\)$"
	sw approve product
	assert_eq "$RC" 0 "approve product exit code"
	sw next
	assert_match "$OUT" "^next: critique \\(no critique"
	add_critique
	sw next
	assert_match "$OUT" "^next: approve blueprint \\(human\\) \\("
	sw approve blueprint
	assert_eq "$RC" 0 "approve blueprint exit code"
	sw next
	assert_match "$OUT" "^next: plan \\("
	sw verify
	assert_eq "$RC" 0 "verify exit code"
	assert_match "$OUT" "^model_check +PASS "
	assert_match "$OUT" "^views +PASS "
	sed 's/has been paid for\./has been paid for in full./' "$REPO/$F/order.md" >"$T/md" && mv "$T/md" "$REPO/$F/order.md"
	sw status
	assert_match "$OUT" "^approval blueprint: stale$"
	sw approve blueprint
	assert_eq "$RC" 1 "approve exit code with a stale critique"
	assert_match "$OUT" "^blueprint: critique is stale"
}

# AC-V5-13: a model that really breaks an invariant fails blueprint check, the
# path is printed in the record's sentences, and nothing can be approved.
test_ac_v5_13_broken_model() {
	need_tlc || return 0
	setup_repo
	conf_all true
	conf_set model_check "./softwary formal check"
	add_product
	add_blueprint
	add_formal
	cp "$FORMALFIX/broken/order.cfg" "$REPO/$F/order.cfg"
	sw blueprint check
	assert_eq "$RC" 1 "blueprint check exit code"
	assert_match "$OUT" "^formal order: FAIL: ShippedWasPaid violated$"
	assert_match "$OUT" '^  1\. A new order is created and has not been paid \(Init\): '
	assert_match "$OUT" '^  2\. A paid order is shipped \(ship\): everShipped = TRUE, status = "shipped"$'
	assert_match "$OUT" "^blueprint: 1 problem\\(s\\)$"
	sw approve product
	approve_blueprint
	assert_eq "$RC" 1 "approve blueprint exit code"
	assert_no_match "$REPO/.softwary/config/approvals.conf" "^blueprint"
	sw verify
	assert_eq "$RC" 1 "verify exit code"
	assert_match "$OUT" "^model_check +FAIL "
}

# AC-V5-13: each variant of the fixture fails exactly its invariant: both
# invariants have one, and the record says which.
test_ac_v5_13_each_variant_fails_its_invariant() {
	need_tlc || return 0
	setup_repo
	add_product
	add_blueprint
	add_formal
	for v in shipunpaid:ShippedWasPaid shipcancelled:CancelledNeverShipped; do
		sed "s/Bug = \"none\"/Bug = \"${v%%:*}\"/" "$FORMALFIX/architecture/formal/order.cfg" >"$REPO/$F/order.cfg"
		sw formal check order
		assert_eq "$RC" 1 "exit code with the variant ${v%%:*} as the model"
		assert_match "$OUT" "^formal order: FAIL: ${v#*:} violated$"
	done
}

run_tests "$0"
