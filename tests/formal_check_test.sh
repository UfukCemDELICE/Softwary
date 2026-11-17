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
	assert_match "$OUT" "^$MD: '## Last verified' must be never, a 40-digit commit, or a commit and compatible or updated$"
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

# trace_of LOG: the trace of a TLC log in the order record's sentences, as
# the package's sw_formal_trace prints it.
trace_of() {
	sh -c '. "$1" && sw_formal_trace "$2" "$3"' sh "$PKG_ROOT/src/lib/formal.sh" "$1" "$REPO/$MD"
}

# cfg_put FILE: variant cfg FILE gets the stdin as its content.
cfg_put() {
	cat >"$REPO/$F/$1"
}

# AC-V5-04: the good model passes (with its state count) and every variant
# fails on the invariant the record says it breaks.
test_ac_v5_04_good_and_variants() {
	need_tlc || return 0
	ready
	sw formal check
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg fails on ShippedWasPaid$"
	assert_match "$OUT" "^formal order: variant order-shipcancelled\\.cfg fails on CancelledNeverShipped$"
	assert_match "$OUT" "^formal order: PASS \\([0-9]+ states\\)$"
	[ -s "$REPO/.softwary/state/logs/formal-order.log" ] || fail "no log of the good model"
	[ -s "$REPO/.softwary/state/logs/formal-order-shipunpaid.log" ] || fail "no log of a variant"
	[ -z "$(find "$REPO/$F" -name '*TTrace*' -o -name states)" ] || fail "TLC left files in architecture/formal"
	sw formal check order
	assert_eq "$RC" 0 "exit code for one specification"
}

# AC-V5-04: a model that really breaks an invariant: FAIL, the shortest path in
# the record's own sentences, with the variables that changed.
test_ac_v5_04_violation_path() {
	need_tlc || return 0
	ready
	cp "$FORMALFIX/broken/order.cfg" "$REPO/$F/order.cfg"
	sw formal check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: FAIL: ShippedWasPaid violated$"
	assert_match "$OUT" '^  1\. A new order is created and has not been paid \(Init\): everShipped = FALSE, paid = FALSE, status = "created"$'
	assert_match "$OUT" '^  2\. A paid order is shipped \(ship\): everShipped = TRUE, status = "shipped"$'
	assert_no_match "$OUT" "^  3\\."
	assert_no_match "$OUT" "PASS"
}

# AC-V5-04: the trace is read from TLC's real output (a model of the fixture,
# run with 1 worker); no Java is needed for this one.
test_ac_v5_04_trace_from_real_tlc_output() {
	ready
	trace_of "$FORMALFIX/tlc-violation.out" >"$OUT" 2>&1 || fail "sw_formal_trace failed"
	assert_eq "$(wc -l <"$OUT" | tr -d ' ')" 2 "steps"
	assert_match "$OUT" '^  1\. A new order is created and has not been paid \(Init\): '
	assert_match "$OUT" '^  2\. A paid order is shipped \(ship\): everShipped = TRUE, status = "shipped"$'
}

# AC-V5-04: an action the record does not describe is printed by its name; a
# liveness counter-example loops back; a step that changes nothing says so.
test_ac_v5_04_trace_odd_shapes() {
	ready
	printf 'State 1: <Initial predicate>\nx = 0\n\nState 2: <Tick line 5, col 9 to line 5, col 24 of module l>\nx = 1\n\nState 3: <Idle line 6, col 1 to line 6, col 9 of module l>\nx = 1\n\nBack to state 1: <Tick line 5, col 9 to line 5, col 24 of module l>\n\n3 states generated\n' >"$T/tlc.out"
	trace_of "$T/tlc.out" >"$OUT" 2>&1 || fail "sw_formal_trace failed"
	assert_match "$OUT" '^  1\. A new order is created and has not been paid \(Init\): x = 0$'
	assert_match "$OUT" '^  2\. Tick \(Tick\): x = 1$'
	assert_match "$OUT" '^  3\. Idle \(Idle\): no variable changed$'
	assert_match "$OUT" '^  then it goes back to step 1 \(Tick\)$'
}

# AC-V5-04: a variant that does not fail; and (separately) one that fails on
# another invariant. Each alone makes the check fail.
test_ac_v5_04_variant_did_not_fail() {
	need_tlc || return 0
	ready
	cfg_put order-shipunpaid.cfg <<'CFG'
SPECIFICATION Spec
CHECK_DEADLOCK FALSE
CONSTANTS
  Bug = "none"
INVARIANTS
  TypeOK
  ShippedWasPaid
CFG
	sw formal check
	assert_eq "$RC" 1 "exit code with a variant that does not fail"
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg did not fail \\(expected ShippedWasPaid\\)$"
	assert_match "$OUT" "^formal order: variant order-shipcancelled\\.cfg fails on CancelledNeverShipped$"
	assert_no_match "$OUT" "PASS"
	ready
	cfg_put order-shipcancelled.cfg <<'CFG'
SPECIFICATION Spec
CHECK_DEADLOCK FALSE
CONSTANTS
  Bug = "shipunpaid"
INVARIANTS
  TypeOK
  ShippedWasPaid
CFG
	sw formal check
	assert_eq "$RC" 1 "exit code with a variant that fails on another invariant"
	assert_match "$OUT" "^formal order: variant order-shipcancelled\\.cfg failed on ShippedWasPaid \\(expected CancelledNeverShipped\\)$"
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg fails on ShippedWasPaid$"
	assert_no_match "$OUT" "PASS"
}

# AC-V5-04: the environment, not the model, is wrong: exit 2 with what to do.
test_ac_v5_04_environment_problems() {
	ready
	RC=0
	(PATH=$(path_without java) && export PATH && cd "$REPO" && ./softwary formal check) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code without java"
	assert_match "$OUT" "^formal: java not found"
	assert_contains "$OUT" "install"
	RC=0
	(cd "$REPO" && SW_TLA2TOOLS=$T/none.jar ./softwary formal check) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code without the jar"
	assert_contains "$OUT" "$T/none.jar not found"
	assert_contains "$OUT" "./softwary formal install"
	printf 'not a jar\n' >"$T/other.jar"
	RC=0
	(cd "$REPO" && SW_TLA2TOOLS=$T/other.jar ./softwary formal check) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code with another jar"
	assert_contains "$OUT" "is not tla2tools 1.8.0"
	assert_contains "$OUT" "./softwary formal install"
}

# AC-V5-04: no specification: nothing to do; an unknown name is a usage error;
# a record with problems is not run.
test_ac_v5_04_no_specs_unknown_and_broken_record() {
	setup_repo
	sw formal check
	assert_eq "$RC" 0 "exit code without specs"
	assert_match "$OUT" "^formal: no specs$"
	ready
	sw formal check ghost
	assert_eq "$RC" 2 "exit code for an unknown specification"
	assert_match "$OUT" "^formal: no specification 'ghost'"
	md_drop '^## Variants'
	sw formal check
	assert_eq "$RC" 1 "exit code with a broken record"
	assert_match "$OUT" "^$MD: missing section '## Variants'$"
	assert_match "$OUT" "^formal order: FAIL: the record has problems \\(./softwary blueprint check\\)$"
}

# AC-V5-05: install downloads from the pinned address (overridden here by a
# local file), checks the SHA-256, prints the path, and does not download a
# jar that is already right.
test_ac_v5_05_install() {
	need_tlc || return 0
	jar=${SW_TLA2TOOLS:-$HOME/.cache/softwary/tla2tools-1.8.0.jar}
	ready
	RC=0
	(cd "$REPO" && SW_TLA2TOOLS=$T/dest/tla2tools.jar SW_TLA2TOOLS_URL=file://$jar ./softwary formal install) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code"
	assert_contains "$OUT" "$T/dest/tla2tools.jar"
	cmp -s "$jar" "$T/dest/tla2tools.jar" || fail "the jar was not installed"
	RC=0
	(cd "$REPO" && SW_TLA2TOOLS=$T/dest/tla2tools.jar SW_TLA2TOOLS_URL=file://$T/nothing ./softwary formal install) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code when the jar is already right"
	assert_contains "$OUT" "already"
}

# AC-V5-05: a download with the wrong SHA-256 is deleted and is exit 2.
test_ac_v5_05_install_digest_mismatch() {
	ready
	printf 'not a jar\n' >"$T/bad.jar"
	RC=0
	(cd "$REPO" && SW_TLA2TOOLS=$T/dest/tla2tools.jar SW_TLA2TOOLS_URL=file://$T/bad.jar ./softwary formal install) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "SHA-256"
	[ ! -e "$T/dest/tla2tools.jar" ] || fail "the wrong jar was kept"
	[ ! -e "$T/dest/tla2tools.jar.part" ] || fail "the partial download was kept"
	RC=0
	(cd "$REPO" && SW_TLA2TOOLS=$T/dest/tla2tools.jar SW_TLA2TOOLS_URL=file://$T/missing ./softwary formal install) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code when the download fails"
	assert_contains "$OUT" "could not download"
}

# AC-V5-05: the CI template installs Java and the jar for a project with specs.
test_ac_v5_05_ci_template() {
	f=$PKG_ROOT/src/templates/github/softwary.yml
	assert_contains "$f" "hashFiles('architecture/formal/*.tla')"
	assert_contains "$f" "actions/setup-java"
	assert_contains "$f" "./softwary formal install"
}

# AC-V5-06: with a specification and model_check not set (or NONE), verify and
# doctor report FAIL; without one, verify skips it.
test_ac_v5_06_model_check_required() {
	ready
	conf_all true
	sw verify
	assert_eq "$RC" 1 "verify exit code"
	assert_match "$OUT" "^model_check +FAIL \\(required: architecture/formal has specs\\)$"
	conf_set model_check "NONE: not now"
	sw verify
	assert_eq "$RC" 1 "verify exit code with NONE"
	assert_match "$OUT" "^model_check +FAIL \\(required"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "^model_check +FAIL \\(required: architecture/formal has specs\\)$"
}

# AC-V5-06: a waiver turns the required check's failure into WAIVED.
test_ac_v5_06_model_check_waiver() {
	ready
	conf_all true
	printf 'model_check = 2099-01-01: models are being written\n' >"$REPO/.softwary/config/waivers.conf"
	sw verify
	assert_eq "$RC" 0 "verify exit code"
	assert_match "$OUT" "^model_check +WAIVED \\(models are being written, until 2099-01-01\\)$"
}

# AC-V5-06: without specs the key is skipped, and doctor says nothing about it.
test_ac_v5_06_skip_without_specs() {
	setup_repo
	conf_all true
	sw verify
	assert_eq "$RC" 0 "verify exit code"
	assert_match "$OUT" "^model_check +SKIP \\(no specs\\)$"
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_no_match "$OUT" "^model_check"
}

# AC-V5-06: configured, verify runs it (and the model passes); doctor reports
# Java and the jar on lines of their own.
test_ac_v5_06_model_check_runs() {
	need_tlc || return 0
	ready
	conf_all true
	conf_set model_check "./softwary formal check"
	sw verify
	assert_eq "$RC" 0 "verify exit code"
	assert_match "$OUT" "^model_check +PASS "
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_match "$OUT" "^model_check +PASS \\(configured, not run\\)$"
	assert_match "$OUT" "^java +PASS"
	assert_match "$OUT" "^tla2tools +PASS"
}

# AC-V5-06: doctor reports a missing Java and a missing jar, each on its own line.
test_ac_v5_06_doctor_java_and_jar() {
	ready
	conf_all true
	conf_set model_check "./softwary formal check"
	RC=0
	(PATH=$(path_without java) && export PATH && cd "$REPO" && SW_TLA2TOOLS=$T/none.jar ./softwary doctor) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "^java +FAIL \\(not found"
	assert_match "$OUT" "^tla2tools +FAIL \\($T/none.jar not found"
}

# AC-V5-06: the commands template carries model_check as a comment.
test_ac_v5_06_template() {
	assert_contains "$PKG_ROOT/src/templates/commands.conf" "# model_check = ./softwary formal check"
}

run_tests "$0"
