#!/bin/sh
# Tests for the findings of a specification (V6): `## Findings` in a record,
# `formal check` on a model that describes code which breaks an invariant, and
# the blueprint approval that binds the table. The tests that run TLC need Java
# and the pinned jar (SW_SKIP_FORMAL=<reason> skips them, visibly).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

F=architecture/formal
MD=$F/order.md
# The blueprint digest of the V5 order fixture (before V6): a record without a
# findings table binds what it bound in V5.
V5_DIGEST=76e37829768b9d677c9c09872d7a71440def7b21

# ready: a repo whose blueprint has the order's state machine and TLA+ model.
ready() {
	setup_repo
	add_product
	add_blueprint
	add_formal
}

# legacy_model: the model describes code that ships an unpaid order (the
# variant ShippedWasPaid has, as the model).
legacy_model() {
	cp "$FORMALFIX/broken/order.cfg" "$REPO/$F/order.cfg"
}

# findings ROW...: appends a `## Findings` table with the rows to the record.
findings() {
	{
		printf '\n## Findings\n\n| Invariant | Until | Reason |\n| --- | --- | --- |\n'
		for _r in "$@"; do
			printf '%s\n' "$_r"
		done
	} >>"$REPO/$MD"
}

LEGACY='| `ShippedWasPaid` | 2999-12-31 | The old order code ships a created order. |'

# no_trace_files: TLC leaves nothing next to the model or in the repo.
no_trace_files() {
	[ -z "$(find "$REPO" -path "$REPO/.git" -prune -o \( -name '*_TTrace_*' -o -name '*.bin' \) -print)" ] ||
		fail "TLC left trace files: $(find "$REPO" -path "$REPO/.git" -prune -o \( -name '*_TTrace_*' -o -name '*.bin' \) -print)"
}

# AC-V6-06: every problem of the findings table is a line of its own: an
# invariant that is not in the invariants table, a date that is not a date, a
# missing reason, a finding that is there twice.
test_ac_v6_06_finding_problems() {
	ready
	findings '| `Ghost` | 2999-01-01 | no such invariant |' \
		'| `ShippedWasPaid` | 2026-02-30 | the date is not one |' \
		'| `CancelledNeverShipped` | 2999-01-01 | |' \
		'| `CancelledNeverShipped` | 2999-01-02 | again |'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MD: finding 'Ghost' is not in the invariants table$"
	assert_match "$OUT" "^$MD: finding 'ShippedWasPaid' has an invalid date '2026-02-30' \\(use YYYY-MM-DD\\)$"
	assert_match "$OUT" "^$MD: finding 'CancelledNeverShipped' has no reason$"
	assert_match "$OUT" "^$MD: duplicate finding 'CancelledNeverShipped'$"
	assert_match "$OUT" "^blueprint: 4 problem\\(s\\)$"
}

# AC-V6-06: the table has the three columns.
test_ac_v6_06_finding_columns() {
	ready
	{
		printf '\n## Findings\n\n| Name | Date |\n| --- | --- |\n| `ShippedWasPaid` | 2999-01-01 |\n'
	} >>"$REPO/$MD"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MD: '## Findings' table must have the columns Invariant, Until, Reason$"
}

# AC-V6-06: the template of a record explains the table without having one
# (the section is optional, and a record without it is as it was in V5).
test_ac_v6_06_template_explains_findings() {
	t=$PKG_ROOT/src/templates/artifacts/formal.md
	assert_contains "$t" "Findings"
	assert_contains "$t" "| Invariant | Until | Reason |"
	assert_no_match "$t" "^## Findings"
	assert_no_match "$t" "^[[:space:]]*[|][[:space:]]*Invariant "
}

# AC-V6-07: a model that shows the code breaking an invariant that is recorded
# as a finding: the model without the finding passes, the finding is reported
# with its date, its reason and the shortest path; the exit code is 0 and the
# variants are checked as before.
test_ac_v6_07_finding_reported() {
	need_tlc || return 0
	ready
	legacy_model
	findings "$LEGACY"
	sw formal check order
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^formal order: FINDING: ShippedWasPaid violated \\(until 2999-12-31: The old order code ships a created order\\.\\)$"
	assert_match "$OUT" '^  1\. A new order is created and has not been paid \(Init\): '
	assert_match "$OUT" '^  2\. A paid order is shipped \(ship\): everShipped = TRUE, status = "shipped"$'
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg fails on ShippedWasPaid$"
	assert_match "$OUT" "^formal order: variant order-shipcancelled\\.cfg fails on CancelledNeverShipped$"
	assert_match "$OUT" "^formal order: PASS \\([0-9]+ states\\)$"
	assert_no_match "$OUT" "^formal order: FAIL"
	no_trace_files
	# the record and the configuration are as they were
	assert_eq "$(cat "$REPO/$F/order.cfg")" "$(cat "$FORMALFIX/broken/order.cfg")" "order.cfg"
	[ "$(find "$REPO/$F" -type f | wc -l | tr -d ' ')" -eq 5 ] || fail "files in $F: $(find "$REPO/$F" -type f)"
}

# AC-V6-07: blueprint check shows the finding and is clean.
test_ac_v6_07_blueprint_check_with_finding() {
	need_tlc || return 0
	ready
	legacy_model
	findings "$LEGACY"
	sw blueprint check
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^formal order: FINDING: ShippedWasPaid violated "
	assert_match "$OUT" "^blueprint: valid "
}

# AC-V6-07: past its date a finding is a failure, with its path; blueprint
# check counts it.
test_ac_v6_07_expired_finding_fails() {
	need_tlc || return 0
	ready
	legacy_model
	findings '| `ShippedWasPaid` | 2000-01-01 | The old order code ships a created order. |'
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: FAIL: ShippedWasPaid violated \\(finding expired 2000-01-01\\)$"
	assert_match "$OUT" '^  2\. A paid order is shipped \(ship\): '
	assert_no_match "$OUT" "FINDING"
	assert_no_match "$OUT" "^formal order: PASS"
	sw blueprint check
	assert_eq "$RC" 1 "blueprint check exit code"
	assert_match "$OUT" "^blueprint: 1 problem\\(s\\)$"
}

# AC-V6-07: a finding that the model no longer shows says so, and passes.
test_ac_v6_07_finding_no_longer_reproduces() {
	need_tlc || return 0
	ready
	findings "$LEGACY"
	sw formal check order
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^formal order: finding ShippedWasPaid no longer reproduces \\(remove it\\)$"
	assert_match "$OUT" "^formal order: PASS "
	assert_no_match "$OUT" "FINDING"
}

# AC-V6-07, review focus 3: a finding does not cover another invariant: a
# model that breaks an invariant that is not recorded fails.
test_ac_v6_07_other_invariant_still_fails() {
	need_tlc || return 0
	ready
	sed 's/Bug = "none"/Bug = "shipcancelled"/' "$FORMALFIX/architecture/formal/order.cfg" >"$REPO/$F/order.cfg"
	findings "$LEGACY"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: FAIL: CancelledNeverShipped violated$"
	assert_no_match "$OUT" "^formal order: PASS"
	no_trace_files
}

# AC-V6-07: the variants are checked as before for every invariant, a finding's
# too: a variant that does not fail is a failure.
test_ac_v6_07_variant_rule_holds() {
	need_tlc || return 0
	ready
	legacy_model
	findings "$LEGACY"
	cp "$FORMALFIX/architecture/formal/order.cfg" "$REPO/$F/order-shipunpaid.cfg"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg did not fail \\(expected ShippedWasPaid\\)$"
	assert_match "$OUT" "^formal order: FINDING: ShippedWasPaid violated "
	assert_no_match "$OUT" "^formal order: PASS"
	# the finding and its path are not problems: only the variant is
	sw blueprint check
	assert_eq "$RC" 1 "blueprint check exit code"
	assert_match "$OUT" "^blueprint: 1 problem\\(s\\)$"
}

# AC-V6-07, review focus 3: the invariants may be listed on one line, after
# the keyword, with a comment, or one per line; the finding is taken out of
# each way, and is still checked on its own.
test_ac_v6_07_cfg_shapes() {
	need_tlc || return 0
	for shape in oneline mixed; do
		rm -rf "$T/repo"
		ready
		findings "$LEGACY"
		case $shape in
		oneline)
			printf 'SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\nCONSTANTS\n  Bug = "shipunpaid"\nINVARIANT TypeOK ShippedWasPaid CancelledNeverShipped \\* all three\n' ;;
		mixed)
			printf 'SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\nINVARIANT ShippedWasPaid\nCONSTANTS\n  Bug = "shipunpaid"\nINVARIANTS\n  TypeOK \\* the types\n  CancelledNeverShipped\n' ;;
		esac >"$REPO/$F/order.cfg"
		sw formal check order
		assert_eq "$RC" 0 "exit code ($shape)"
		assert_match "$OUT" "^formal order: FINDING: ShippedWasPaid violated "
		assert_match "$OUT" "^formal order: PASS "
		no_trace_files
	done
}

# AC-V6-08: the approval binds the findings table: a finding added, its date or
# its reason changed makes the digest, and so the approval, stale.
test_ac_v6_08_findings_change_stales() {
	ready
	sw blueprint digest
	plain=$(cat "$OUT")
	findings "$LEGACY"
	sw blueprint digest
	with=$(cat "$OUT")
	[ "$with" != "$plain" ] || fail "a finding does not change the digest"
	sed 's/2999-12-31/2999-12-30/' "$REPO/$MD" >"$T/md" && cp "$T/md" "$REPO/$MD"
	sw blueprint digest
	[ "$(cat "$OUT")" != "$with" ] || fail "a changed date does not change the digest"
	sed 's/2999-12-30/2999-12-31/' "$REPO/$MD" >"$T/md" && cp "$T/md" "$REPO/$MD"
	sw blueprint digest
	assert_eq "$(cat "$OUT")" "$with" "the digest is back when the table is"
	sed 's/ships a created order/ships a paid order/' "$REPO/$MD" >"$T/md" && cp "$T/md" "$REPO/$MD"
	sw blueprint digest
	[ "$(cat "$OUT")" != "$with" ] || fail "a changed reason does not change the digest"
	# only that table: other text of the record, outside the invariants, does not
	sed 's/ships a paid order/ships a created order/' "$REPO/$MD" >"$T/md" && cp "$T/md" "$REPO/$MD"
	printf '\nNotes after the table.\n' >>"$REPO/$MD"
	sw blueprint digest
	assert_eq "$(cat "$OUT")" "$with" "text outside the tables"
}

# AC-V6-08: a record with no findings table binds what it bound in V5.
test_ac_v6_08_no_findings_digest_unchanged() {
	ready
	sw blueprint digest
	assert_eq "$(cat "$OUT")" "$V5_DIGEST" "digest of the V5 fixture"
}

run_tests "$0"
