#!/bin/sh
# Tests for the upkeep of a specification (V8): the coverage table points at
# real code, a model that is older than the code it covers is stale, and
# `formal verified` records the verdict that brings it up to date. The tests
# that run TLC need Java and the pinned jar (SW_SKIP_FORMAL=<reason> skips
# them, visibly).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

F=architecture/formal
MD=$F/order.md
FNS='order_create, order_pay, order_ship, order_cancel'
EVENTS_REL=.softwary/state/events.log

# covered: a repo whose order model covers app/order.sh (the shop's code), as
# the project's own commit. The record has never been verified.
covered() {
	setup_repo
	add_product
	add_blueprint
	add_formal
	mkdir -p "$REPO/app"
	cp "$EXISTINGFIX/app/order.sh" "$REPO/app/order.sh"
	md_sub '| planned | - |' "| app/order.sh | $FNS |"
	commit_all "the shop's order code and its model"
}

# md_sub FROM TO: replaces the first FROM of each line of the record by TO
# (TO may contain FROM).
md_sub() {
	awk -v f="$1" -v t="$2" '{ if ((i = index($0, f)) > 0) $0 = substr($0, 1, i - 1) t substr($0, i + length(f)); print }' \
		"$REPO/$MD" >"$T/md.tmp"
	mv "$T/md.tmp" "$REPO/$MD"
}

# lv_set VALUE: the first line of `## Last verified` becomes VALUE.
lv_set() {
	awk -v v="$1" '
		/^## / { on = ($0 == "## Last verified"); print; next }
		on && !done && NF { print v; done = 1; next }
		{ print }' "$REPO/$MD" >"$T/md.tmp"
	mv "$T/md.tmp" "$REPO/$MD"
}

# lv_get: the first line of `## Last verified`.
lv_get() {
	awk '/^## / { on = ($0 == "## Last verified"); next } on && NF { print; exit }' "$REPO/$MD"
}

# verified_now: the record says the model was verified at the commit that is
# HEAD now (a bare commit, as V5 wrote it), and that is committed.
verified_now() {
	lv_set "$(git -C "$REPO" rev-parse HEAD)"
	commit_all "verified"
}

# AC-V8-01: a covered path that is not there is a problem of its own, in
# `blueprint check` (the record check) and in `formal check`.
test_ac_v8_01_missing_path() {
	covered
	md_sub 'app/order.sh' 'app/ghost.sh'
	sw blueprint check
	assert_eq "$RC" 1 "blueprint check exit code"
	assert_match "$OUT" "^formal order: coverage path app/ghost\\.sh does not exist$"
	assert_no_match "$OUT" "coverage function"
	assert_match "$OUT" "^blueprint: 1 problem\\(s\\)$"
	need_tlc || return 0
	sw formal check order
	assert_eq "$RC" 1 "formal check exit code"
	assert_match "$OUT" "^formal order: coverage path app/ghost\\.sh does not exist$"
	# the model is checked all the same: a mistake of the model shows too
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg fails on ShippedWasPaid$"
	assert_match "$OUT" "^formal order: FAIL: the model passes \\([0-9]+ states\\) but is not held to the code \\(see above\\)$"
}

# AC-V8-01: every function the table names must be in the file, as a word:
# order_pay is not order_payment. One line for each missing function.
test_ac_v8_01_missing_function() {
	covered
	printf 'order_create() { :; }\norder_payment() { :; }\norder_ship() { :; }\norder_cancelled() { :; }\n' >"$REPO/app/order.sh"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: coverage function order_pay not found in app/order\\.sh$"
	assert_match "$OUT" "^formal order: coverage function order_cancel not found in app/order\\.sh$"
	assert_no_match "$OUT" "function order_create"
	assert_no_match "$OUT" "function order_ship"
	assert_match "$OUT" "^blueprint: 2 problem\\(s\\)$"
}

# AC-V8-01: a name that only occurs inside a longer word does not count, and
# a comment that names it does (a word of the file is a word).
test_ac_v8_01_word_boundary() {
	covered
	printf 'order_payment() { :; }\n' >"$REPO/app/other.sh"
	md_sub "| app/order.sh | $FNS |" '| app/other.sh | order_pay |'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: coverage function order_pay not found in app/other\\.sh$"
	need_tlc || return 0
	printf '# order_pay is in order_payment\n' >>"$REPO/app/other.sh"
	sw blueprint check
	assert_no_match "$OUT" "coverage"
}

# AC-V8-01: a `planned` row is not looked at; a directory is searched as a whole.
test_ac_v8_01_planned_and_directory() {
	need_tlc || return 0
	covered
	md_sub "| app/order.sh | $FNS |" '| planned | - |'
	sw blueprint check
	assert_eq "$RC" 0 "exit code with a planned row"
	md_sub '| planned | - |' "| app | $FNS |"
	sw blueprint check
	assert_no_match "$OUT" "coverage"
	md_sub "| app | $FNS |" "| app | $FNS, order_ghost |"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with a missing function in a directory"
	assert_match "$OUT" "^formal order: coverage function order_ghost not found in app$"
}

# AC-V8-02: a record that has never been verified and covers code fails; one
# whose coverage is only `planned` does not (the model came before the code).
test_ac_v8_02_never_verified() {
	need_tlc || return 0
	covered
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: never verified against app/order\\.sh$"
	assert_no_match "$OUT" "PASS"
	md_sub "| app/order.sh | $FNS |" '| planned | - |'
	commit_all "planned"
	sw formal check order
	assert_eq "$RC" 0 "exit code with planned coverage"
	assert_no_match "$OUT" "never verified"
	assert_no_match "$OUT" "stale"
}

# AC-V8-02: a commit the repository does not have cannot be told from a
# lie: it is reported by its first seven digits.
test_ac_v8_02_unknown_commit() {
	need_tlc || return 0
	covered
	lv_set 1234567890123456789012345678901234567890
	commit_all "verified at a commit nobody has"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: last verified commit 1234567 is unknown$"
}

# AC-V8-02: a bare commit (V5's record) is valid: compatible. Nothing changed
# since, so the check passes; the verdict words are accepted as well.
test_ac_v8_02_commit_and_verdict_forms() {
	need_tlc || return 0
	covered
	verified_now
	sw formal check order
	assert_eq "$RC" 0 "exit code with a bare commit"
	assert_match "$OUT" "^formal order: PASS "
	for v in compatible updated; do
		lv_set "$(git -C "$REPO" rev-parse HEAD) $v"
		commit_all "verified $v"
		sw blueprint check
		assert_eq "$RC" 0 "blueprint check exit code with $v"
	done
	lv_set "$(git -C "$REPO" rev-parse HEAD) bug"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with bug"
	assert_match "$OUT" "^$MD: '## Last verified' must be never, a 40-digit commit, or a commit and compatible or updated$"
}

# AC-V8-02: the covered file changed in a later commit: stale, and the paths
# that changed are named.
test_ac_v8_02_stale_committed() {
	need_tlc || return 0
	covered
	verified_now
	printf '# a change\n' >>"$REPO/app/order.sh"
	commit_all "the code changes"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	sha7=$(git -C "$REPO" rev-parse --short=7 HEAD~2)
	assert_match "$OUT" "^formal order: stale since $sha7: app/order\\.sh changed; check the model and record a verdict \\(./softwary formal verified order compatible\\|updated\\)$"
	assert_no_match "$OUT" "PASS"
	conf_all true
	conf_set model_check "./softwary formal check"
	sw verify
	assert_eq "$RC" 1 "verify exit code"
	assert_match "$OUT" "^model_check +FAIL "
}

# AC-V8-02: a change that is not committed yet counts, and so does a new file
# in a covered directory that git does not track.
test_ac_v8_02_stale_working_tree() {
	need_tlc || return 0
	covered
	md_sub "| app/order.sh | $FNS |" "| app | $FNS |"
	commit_all "the model covers app/"
	verified_now
	sw formal check order
	assert_eq "$RC" 0 "exit code before the changes"
	printf '# edited\n' >>"$REPO/app/order.sh"
	printf 'new() { :; }\n' >"$REPO/app/new.sh"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: app/new\\.sh app/order\\.sh changed; "
}

# AC-V8-02: the model and its configurations are in the set, and so is the
# coverage table: a new row makes it stale, named as `## Coverage`.
test_ac_v8_02_stale_model_and_table() {
	need_tlc || return 0
	covered
	verified_now
	printf '\\* a comment\n' >>"$REPO/$F/order.tla"
	printf '\\* a comment\n' >>"$REPO/$F/order-shipunpaid.cfg"
	commit_all "the model changes"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: architecture/formal/order-shipunpaid\\.cfg architecture/formal/order\\.tla changed; "
	verified_now
	sw formal check order
	assert_eq "$RC" 0 "exit code once verified again"
	printf 'extra() { :; }\n' >"$REPO/app/extra.sh"
	md_sub "| app/order.sh | $FNS |" "| app/order.sh | $FNS |
| app/extra.sh | extra |"
	commit_all "a row of the coverage table"
	sw formal check order
	assert_eq "$RC" 1 "exit code with a new row"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: ## Coverage app/extra\\.sh changed; "
}

# AC-V8-02: the record itself is not in the set: a change to its other
# sections, and the commit of the verdict, keep the model verified.
test_ac_v8_02_record_is_not_in_the_set() {
	need_tlc || return 0
	covered
	verified_now
	md_sub 'One order at a time;' 'One order at a time (said again);'
	commit_all "the record is reworded"
	sw formal check order
	assert_eq "$RC" 0 "exit code"
	assert_no_match "$OUT" "stale"
}

# AC-V8-03: a clean tree and a model that passes: the verdict is written on the
# first line of the section, the event is logged, nothing else of the record
# changes, and after the commit `formal check` is green.
test_ac_v8_03_records_the_verdict() {
	need_tlc || return 0
	covered
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order compatible
	assert_eq "$RC" 0 "exit code"
	head=$(git -C "$REPO" rev-parse HEAD)
	assert_eq "$(lv_get)" "$head compatible" "Last verified"
	diff "$T/before.md" "$REPO/$MD" >"$T/diff" || :
	assert_eq "$(grep -c '^[<>]' "$T/diff")" 2 "changed lines"
	assert_match "$REPO/$EVENTS_REL" '"event":"formal_verified".*"detail":"order compatible '"$(printf '%s' "$head" | cut -c1-7)"'"'
	assert_match "$OUT" "^formal verified: order compatible \\($(printf '%s' "$head" | cut -c1-7)\\)$"
	commit_all "verdict"
	sw formal check order
	assert_eq "$RC" 0 "formal check after the commit"
	assert_no_match "$OUT" "stale"
	assert_no_match "$OUT" "never verified"
}

# AC-V8-03: what is not committed in the set stops it, and nothing is written.
test_ac_v8_03_refuses_uncommitted() {
	covered
	printf '# edited\n' >>"$REPO/app/order.sh"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order compatible
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal verified: uncommitted changes in app/order\\.sh; commit them first$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
	git -C "$REPO" checkout -q app/order.sh
	printf 'extra() { :; }\n' >"$REPO/app/extra.sh"
	md_sub "| app/order.sh | $FNS |" "| app | $FNS |"
	commit_all "the model covers app/"
	printf 'new() { :; }\n' >"$REPO/app/new.sh"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order compatible
	assert_eq "$RC" 1 "exit code with a new file"
	assert_match "$OUT" "^formal verified: uncommitted changes in app/new\\.sh; commit them first$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
}

# AC-V8-03: a model TLC does not pass is not verified, and nothing is written.
test_ac_v8_03_refuses_a_red_model() {
	need_tlc || return 0
	covered
	cp "$FORMALFIX/broken/order.cfg" "$REPO/$F/order.cfg"
	commit_all "a model that breaks an invariant"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order updated
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: FAIL: ShippedWasPaid violated$"
	assert_match "$OUT" "^formal verified: formal check order fails; nothing was written$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
}

# AC-V8-03: `compatible` says the model did not change: it must not have; and
# `updated` says it did.
test_ac_v8_03_verdict_follows_the_model() {
	need_tlc || return 0
	covered
	verified_now
	printf 'x() { :; }\n' >>"$REPO/app/order.sh"
	commit_all "the code changes, the model does not"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order updated
	assert_eq "$RC" 1 "updated with an unchanged model"
	assert_match "$OUT" "^formal verified: updated needs the model to have changed since [0-9a-f]{7}, but architecture/formal/order\\.tla and its configurations are the same; use compatible$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
	printf '\\* a comment\n' >>"$REPO/$F/order.tla"
	commit_all "the model changes"
	sw formal verified order compatible
	assert_eq "$RC" 1 "compatible with a changed model"
	assert_match "$OUT" "^formal verified: compatible needs the model to be unchanged since [0-9a-f]{7}, but architecture/formal/order\\.tla changed; use updated$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
	sw formal verified order updated
	assert_eq "$RC" 0 "updated with a changed model"
	assert_eq "$(lv_get)" "$(git -C "$REPO" rev-parse HEAD) updated" "Last verified"
}

# AC-V8-03: a record that was never verified takes either verdict.
test_ac_v8_03_never_takes_both_verdicts() {
	need_tlc || return 0
	covered
	sw formal verified order updated
	assert_eq "$RC" 0 "updated from never"
	git -C "$REPO" checkout -q "$MD"
	sw formal verified order compatible
	assert_eq "$RC" 0 "compatible from never"
}

# AC-V8-03: bug and blocked are the human's: usage error and where to go; an
# unknown verdict or specification, and a wrong number of words, are too.
test_ac_v8_03_usage_and_human_verdicts() {
	covered
	cp "$REPO/$MD" "$T/before.md"
	for v in bug blocked; do
		sw formal verified order $v
		assert_eq "$RC" 2 "exit code for $v"
		assert_match "$OUT" "^formal verified: bug and blocked go to the human \\(./softwary job escalate <job> <question>\\)$"
	done
	sw formal verified order maybe
	assert_eq "$RC" 2 "exit code for an unknown verdict"
	assert_match "$OUT" "^usage: ./softwary formal verified <spec> compatible\\|updated$"
	sw formal verified ghost compatible
	assert_eq "$RC" 2 "exit code for an unknown specification"
	assert_match "$OUT" "^formal verified: no specification 'ghost' "
	sw formal verified order
	assert_eq "$RC" 2 "exit code for a missing verdict"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
}

# AC-V8-03: a commit that is not there tells nothing about the model, so the
# verdict cannot be checked against it.
test_ac_v8_03_unknown_commit() {
	need_tlc || return 0
	covered
	lv_set 1234567890123456789012345678901234567890
	commit_all "verified at a commit nobody has"
	sw formal verified order compatible
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal verified: last verified commit 1234567 is unknown; write never in '## Last verified' to start again$"
}

run_tests "$0"
