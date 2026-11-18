#!/bin/sh
# End to end for the upkeep of a model (V8), on the existing repository of V6
# (tests/fixtures/existing) and with real TLC: a job that changes the code a
# model covers is stopped by the gate until the model is checked again and a
# verdict is recorded; a job that changes the model records `updated`; a job
# that changes an invariant, or deletes the code a record covers, fails the
# gate; the tests a state machine owes and the finding's counter-example are
# drift until a test names them. The tests need Java and the pinned jar
# (SW_SKIP_FORMAL=<reason> skips them, visibly).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOBS_REL=.softwary/state/jobs
WAIVERS_REL=.softwary/config/waivers.conf
EVENTS_REL=.softwary/state/events.log
ORDER_MD=architecture/formal/order.md
FAR=2999-12-31

job_get() {
	sed -n "s/^$2=//p" "$REPO/$JOBS_REL/$1/job"
}

# shop: the existing repository with softwary installed, its commands set and
# its red lint and test waived with their scoped commands.
shop() {
	setup_repo --no-model
	add_existing
	existing_conf
	conf_set test_files 'sh checks/test.sh {files}'
	conf_set lint_files 'sh checks/lint.sh {files}'
	printf 'lint = %s: legacy lint debt\ntest = %s: legacy report test\n' "$FAR" "$FAR" >"$REPO/$WAIVERS_REL"
	tools_set claude-code on
	tools_set codex on
	models_translate codex
	sw sync
	assert_eq "$RC" 0 "sync"
	commit_all "softwary installed"
}

# add_spec NNN NAME TOUCHES: a spec with one criterion bound to the example
# EX-F4-01 and a slice that touches TOUCHES (and the tests), approved by the
# analyst's record.
add_spec() {
	d=$REPO/specs/$1-$2
	mkdir -p "$d/slices"
	cat >"$d/spec.md" <<SPEC
---
id: $1
title: Change $2
status: draft
risk: R1
model: orders
contracts:
---

# Change $2

## Scope

\`app/order.sh\` and its model.

## Acceptance criteria

- **AC-$1-01:** The change is made. Covers EX-F4-01.

## Open questions
SPEC
	cat >"$d/slices/S1.md" <<SLICE
---
id: S1
spec: $1
goal: Change $2
acs: AC-$1-01
depends_on:
touches: $3, tests
status: planned
---

# S1: Change $2
SLICE
	printf -- '---\nspec: %s\ndigest: %s\ndecision: pass\n---\n\n# Analysis of %s\n' "$1" "$(git -C "$REPO" hash-object "$d/spec.md")" "$1" >"$d/analysis.md"
}

# loop_shop: the shop, its product and blueprint drawn from the code, the
# order model verified against the code, three slices that change it (the
# code, the model, an invariant) and one that deletes the covered file, all
# approved; an origin with both branches, a fake gh, an evaluation, an open run.
loop_shop() {
	shop
	add_existing_artifacts
	add_spec 002 model "architecture/formal"
	add_spec 003 invariant "architecture/formal/order.md"
	add_spec 004 delete "app/order.sh, architecture/formal/order.md"
	commit_all "the product and the blueprint, drawn from the code, and slices"
	existing_verified
	sw approve product
	assert_eq "$RC" 0 "approve product"
	approve_blueprint
	assert_eq "$RC" 0 "approve blueprint: $(cat "$OUT")"
	for n in 001 002 003 004; do
		[ "$n" != 001 ] || printf -- '---\nspec: 001\ndigest: %s\ndecision: pass\n---\n\n# Analysis of 001\n' "$(git -C "$REPO" hash-object specs/001-ship-paid/spec.md)" >"$REPO/specs/001-ship-paid/analysis.md"
		sw plan approve $n
		assert_eq "$RC" 0 "plan approve $n: $(cat "$OUT")"
	done
	loop_conf
	add_eval
	add_origin
	add_production
	fake_gh
	sw run start
	assert_eq "$RC" 0 "run start: $(cat "$OUT")"
}

# a_test JOB: a test that names the criterion of the job's slice, committed
# with the slice in review.
a_test() {
	wt=$(job_wt "$1")
	n=${1%%-*}
	d=$(ls -d "$wt/specs/$n"-*)
	fm_set "$d/slices/S1.md" status review
	mkdir -p "$wt/tests"
	printf '#!/bin/sh\n# covers AC-%s-01\ntrue\n' "$n" >"$wt/tests/test_change_$n.sh"
}

# verified JOB VERDICT: the job's worktree is checked against its model; sets
# RC and OUT like sw.
verified() {
	RC=0
	(cd "$(job_wt "$1")" && ./softwary formal verified order "$2") >"$OUT" 2>&1 || RC=$?
}

# gate_log JOB: the log of the first gate of the job.
gate_log() {
	printf '%s/%s/%s/gate-1.log' "$REPO" "$JOBS_REL" "$1"
}

# AC-V8-12: a job that changes the code of a covered file: the gate stops at
# the model (stale), the job checks the model again and records `compatible`
# with the record's commit, and the gate, the pull request, the review and
# the merge go through.
test_ac_v8_12_code_change_needs_a_verdict() {
	need_tlc || return 0
	loop_shop
	job=001-S1
	sw job start $job
	assert_eq "$RC" 0 "job start"
	wt=$(job_wt $job)
	fm_set "$wt/specs/001-ship-paid/slices/S1.md" status review
	sed 's/paid | created) order_put/paid) order_put/' "$wt/app/order.sh" >"$T/order.sh" && cp "$T/order.sh" "$wt/app/order.sh"
	cat >"$wt/tests/test_ship_paid_only.sh" <<'TEST'
#!/bin/sh
# covers AC-001-01 AC-001-02
. "$(dirname "$0")/../app/order.sh"
ORDER_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$ORDER_DIR"' EXIT
order_create 7 || exit 1
! order_ship 7 || exit 1
order_pay 7 && order_ship 7 || exit 1
[ "$(order_state 7)" = shipped ] || exit 1
TEST
	commit_in "$wt" "ship only paid orders"
	sw job event $job implemented
	sw job gate $job
	assert_eq "$RC" 0 "gate exit code"
	assert_eq "$(job_get $job state)" implementing "state after a gate that finds the model stale"
	assert_match "$(gate_log $job)" "^model_check +FAIL "
	assert_match "$(gate_log $job)" "^ +formal order: stale since [0-9a-f]{7}: app/order\\.sh changed; check the model and record a verdict "
	# the model still describes the code (the shop's rule is a rule of the code, not of the model)
	verified $job compatible
	assert_eq "$RC" 0 "formal verified: $(cat "$OUT")"
	commit_in "$wt" "the order model is verified against the code"
	verified_sha=$(git -C "$wt" rev-parse HEAD~1)
	assert_match "$wt/$ORDER_MD" "^$verified_sha compatible [0-9a-f]{40} [0-9a-f]{40}$"
	assert_eq "$(jq -r 'select(.event == "formal_verified") | .detail' "$REPO/$EVENTS_REL" | tail -n 1)" "order compatible $(git -C "$wt" rev-parse --short=7 HEAD~1)" "formal_verified event"
	sw job event $job implemented
	sw job gate $job
	assert_eq "$RC" 0 "second gate exit code"
	assert_eq "$(job_get $job state)" pr "state after the gate"
	assert_match "$REPO/$JOBS_REL/$job/gate-2.log" "^model_check +PASS "
	sw job pr $job
	assert_eq "$RC" 0 "pr"
	sw job ci $job
	assert_eq "$RC" 0 "ci"
	mkdir -p "$wt/specs/001-ship-paid/reviews"
	printf -- '---\nslice: S1\ndecision: approve\n---\n\n# Review of S1\n' >"$wt/specs/001-ship-paid/reviews/S1.md"
	sw job review $job
	assert_eq "$RC" 0 "review"
	write_decision $job merge
	sw merge $job
	assert_eq "$RC" 0 "merge exit code: $(cat "$OUT")"
	assert_match "$OUT" "^merged: $job [0-9a-f]{40}$"
	assert_eq "$(job_get $job state)" merged "state"
	# main holds the verdict and the model is not stale
	sw formal check order
	assert_eq "$RC" 0 "formal check on main: $(cat "$OUT")"
	assert_no_match "$OUT" "stale"
	# a fresh clone of the integration branch has not got the job's commit (the
	# merge was a squash and the job's branch is gone): the model is not stale
	git -C "$T/origin.git" branch -q -D "softwary/$job"
	git -C "$T/origin.git" gc -q --prune=now
	git clone -q "$T/origin.git" "$T/fresh" || fail "clone failed"
	git -C "$T/fresh" cat-file -e "$verified_sha^{commit}" 2>/dev/null && fail "the clone has the verified commit"
	RC=0
	(cd "$T/fresh" && ./softwary formal check order) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "formal check in a fresh clone: $(cat "$OUT")"
	assert_match "$OUT" "^formal order: PASS "
	assert_no_match "$OUT" "unknown|stale"
}

# AC-V8-12: a job that changes the model cannot say the model is unchanged:
# `compatible` is refused, `updated` is recorded, and the gate passes.
test_ac_v8_12_model_change_is_updated() {
	need_tlc || return 0
	loop_shop
	job=002-S1
	sw job start $job
	assert_eq "$RC" 0 "job start"
	wt=$(job_wt $job)
	a_test $job
	printf '\\* the model follows the code: a comment\n' >>"$wt/architecture/formal/order.tla"
	commit_in "$wt" "the model changes"
	verified $job compatible
	assert_eq "$RC" 1 "compatible with a changed model"
	assert_match "$OUT" "^formal verified: compatible needs the model to be unchanged since [0-9a-f]{7}, but architecture/formal/order\\.tla changed; use updated$"
	verified $job updated
	assert_eq "$RC" 0 "updated: $(cat "$OUT")"
	commit_in "$wt" "the order model is verified against the code"
	assert_match "$wt/$ORDER_MD" "^[0-9a-f]{40} updated [0-9a-f]{40} [0-9a-f]{40}$"
	sw job event $job implemented
	sw job gate $job
	assert_eq "$RC" 0 "gate exit code"
	assert_eq "$(job_get $job state)" pr "state after the gate"
	assert_match "$REPO/$JOBS_REL/$job/gate-1.log" "^model_check +PASS "
}

# AC-V8-12: a job that changes an invariant's sentence fails the gate: it is a
# protected path, the human's.
test_ac_v8_12_invariant_change_is_protected() {
	need_tlc || return 0
	loop_shop
	job=003-S1
	sw job start $job
	assert_eq "$RC" 0 "job start"
	wt=$(job_wt $job)
	a_test $job
	sed 's/has been paid for\./has been paid for!/' "$wt/$ORDER_MD" >"$T/md" && cp "$T/md" "$wt/$ORDER_MD"
	commit_in "$wt" "an invariant is reworded"
	sw job event $job implemented
	sw job gate $job
	assert_eq "$RC" 0 "gate exit code (the failure is recorded)"
	assert_eq "$(job_get $job state)" implementing "state after a protected change"
	assert_match "$(gate_log $job)" "^guard: protected: $ORDER_MD$"
	last=$(tail -n 1 "$REPO/$EVENTS_REL")
	assert_eq "$(printf '%s' "$last" | jq -r .event)" gate_fail "event"
	assert_eq "$(printf '%s' "$last" | jq -r .detail)" "guard: protected: $ORDER_MD" "detail"
}

# AC-V8-12: a job that deletes the file a record covers fails the gate: the
# model describes code that is not there.
test_ac_v8_12_deleting_covered_code_fails_the_coverage() {
	need_tlc || return 0
	loop_shop
	job=004-S1
	sw job start $job
	assert_eq "$RC" 0 "job start"
	wt=$(job_wt $job)
	a_test $job
	git -C "$wt" rm -q app/order.sh
	commit_in "$wt" "the order code is deleted"
	sw job event $job implemented
	sw job gate $job
	assert_eq "$RC" 0 "gate exit code (the failure is recorded)"
	assert_eq "$(job_get $job state)" implementing "state after deleting covered code"
	assert_match "$(gate_log $job)" "^model_check +FAIL "
	assert_match "$(gate_log $job)" "^ +formal order: coverage path app/order\\.sh does not exist$"
}

# AC-V8-12: the shop's state machine owes a test for each state and event and
# the finding a replay: until a test names them, drift lists them; named in a
# test, or decided, they are not.
test_ac_v8_12_untested_and_unreplayed_drift() {
	shop
	add_existing_artifacts
	commit_all "the product and the blueprint, drawn from the code"
	sw drift
	assert_eq "$RC" 1 "exit code"
	assert_eq "$(grep -c '^drift: untested ST-order-' "$OUT")" 12 "untested"
	assert_match "$OUT" "^drift: untested ST-order-created-ship: undecided$"
	assert_match "$OUT" "^drift: unreplayed CE-order-ShippedWasPaid: undecided$"
	sw formal trace order ShippedWasPaid
	assert_eq "$RC" 0 "formal trace: $(cat "$OUT")"
	assert_eq "$(sed -n 1p "$OUT")" "CE-order-ShippedWasPaid" "first line of the trace"
	assert_match "$OUT" '^  2\. An order is shipped \(ship\): everShipped = TRUE, status = "shipped"$'
	# a test that replays the finding and tests the transitions of the machine
	sw states tests
	{
		printf '#!/bin/sh\n'
		printf '# replays CE-order-ShippedWasPaid: a created order is shipped (the old import path)\n'
		sed -n 's/^\(ST-[^ ]*\) allowed.*/# covers \1/p' "$OUT"
		printf 'true\n'
	} >"$REPO/tests/test_order_machine.sh"
	commit_all "a test that replays the finding and covers the transitions"
	sw drift
	assert_no_match "$OUT" "unreplayed"
	assert_eq "$(grep -c '^drift: untested ST-order-' "$OUT")" 8 "untested after the test"
	assert_no_match "$OUT" "^drift: untested ST-order-paid-ship:"
	# the refused ones are decided: accept, with a date and a reason
	{
		printf '# Drift decisions\n\n| Item | Decision | Until | Reason |\n| --- | --- | --- | --- |\n'
		sed -n "s/^drift: \\(.*\\): undecided\$/| \\1 | accept | $FAR | the shop checks it by hand |/p" "$OUT"
	} >"$REPO/architecture/drift.md"
	sw drift
	assert_eq "$RC" 0 "drift exit code with a decision for each: $(cat "$OUT")"
	assert_match "$OUT" "^drift: untested ST-order-created-ship: decided \\(accept, until $FAR\\)$"
}

run_tests "$0"
