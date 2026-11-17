#!/bin/sh
# End to end on the existing repository of V6 (tests/fixtures/existing), for
# delivery and operation (V7): a bug report becomes a slice with a repro that
# the gate proves and the merge works out again, a repro that does not
# reproduce the bug fails the gate, undecided drift stops `ship prepare` and
# decisions let it through, and the release note becomes a pull request to the
# production branch that nobody merges and nothing deploys. The tests need Java
# and the pinned jar (SW_SKIP_FORMAL=<reason> skips them, visibly).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOBS_REL=.softwary/state/jobs
WAIVERS_REL=.softwary/config/waivers.conf
EVENTS_REL=.softwary/state/events.log
FAR=2999-12-31

job_get() {
	sed -n "s/^$2=//p" "$REPO/$JOBS_REL/$1/job"
}

# shop: the existing repository with softwary installed, its commands set, its
# red lint and test waived with their scoped commands (the test one also runs
# the repro tests) and a deploy command that would leave a mark.
shop() {
	setup_repo --no-model
	add_existing
	existing_conf
	conf_set test_files 'sh checks/test.sh {files}'
	conf_set lint_files 'sh checks/lint.sh {files}'
	conf_set deploy "touch $T/deployed"
	printf 'lint = %s: legacy lint debt\ntest = %s: legacy report test\n' "$FAR" "$FAR" >"$REPO/$WAIVERS_REL"
	tools_set claude-code on
	tools_set codex on
	sw sync
	assert_eq "$RC" 0 "sync"
	commit_all "softwary installed"
}

# bug: the bug of the report: a shipped order can be cancelled (EX-F4-02 says
# it is refused).
bug() {
	sed 's/created | paid)/created | paid | shipped)/' "$REPO/app/order.sh" >"$T/order.sh" && cp "$T/order.sh" "$REPO/app/order.sh"
	grep -q 'created | paid | shipped)' "$REPO/app/order.sh" || fail "the bug was not put in"
}

# add_fix_spec NNN EX NAME TEST: a spec with one criterion bound to the example
# EX and a slice with the repro TEST, approved by the analyst's record.
add_fix_spec() {
	d=$REPO/specs/$1-$3
	mkdir -p "$d/slices"
	cat >"$d/spec.md" <<SPEC
---
id: $1
title: Fix $3
status: draft
risk: R1
model: orders
contracts:
---

# Fix $3

Reported by the clerk.

## Scope

\`app/order.sh\`.

## Acceptance criteria

- **AC-$1-01:** The reported behaviour is as $2 says. Covers $2.

## Open questions
SPEC
	cat >"$d/slices/S1.md" <<SLICE
---
id: S1
spec: $1
goal: Fix the reported behaviour
acs: AC-$1-01
depends_on:
touches: app/order.sh, architecture/formal/order.md, tests
status: planned
repro: $4
---

# S1: Fix the reported behaviour
SLICE
	printf -- '---\nspec: %s\ndigest: %s\ndecision: pass\n---\n\n# Analysis of %s\n' "$1" "$(git -C "$REPO" hash-object "$d/spec.md")" "$1" >"$d/analysis.md"
}

# loop_shop: the shop with the bug, its product and blueprint approved, the
# slices that fix the two reports planned and approved, an origin with both
# branches, a fake gh, an evaluation and an open run.
loop_shop() {
	shop
	bug
	commit_all "the shop as the clerk found it"
	add_existing_artifacts
	add_fix_spec 002 EX-F4-02 cancel-shipped tests/test_cancel_shipped.sh
	add_fix_spec 003 EX-F4-01 cancel-created tests/test_cancel_created.sh
	commit_all "the product and the blueprint, drawn from the code, and two fixes"
	existing_verified
	sw approve product
	assert_eq "$RC" 0 "approve product"
	approve_blueprint
	assert_eq "$RC" 0 "approve blueprint"
	for n in 002 003; do
		sw plan approve $n
		assert_eq "$RC" 0 "plan approve $n"
	done
	loop_conf
	add_eval
	add_origin
	add_production
	fake_gh
	sw run start
	assert_eq "$RC" 0 "run start: $(cat "$OUT")"
}

# AC-V7-12: a bug report becomes a slice with a repro: the gate proves that
# the test fails on the base and passes on the job, the merge works it out
# again and the job merges; a second slice whose test passes on the base too
# does not reproduce a bug and fails the gate.
test_ac_v7_12_bug_report_to_merge_and_a_repro_that_proves_nothing() {
	need_tlc || return 0
	loop_shop
	sw plan check
	assert_eq "$RC" 0 "plan check: $(cat "$OUT")"
	job=002-S1
	sw job start $job
	assert_eq "$RC" 0 "job start"
	wt=$(job_wt $job)
	cat >"$wt/tests/test_cancel_shipped.sh" <<'TEST'
#!/bin/sh
# covers AC-002-01: a shipped order is not cancelled
. "$(dirname "$0")/../app/order.sh"
ORDER_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$ORDER_DIR"' EXIT
order_create 7 && order_pay 7 && order_ship 7 || exit 1
! order_cancel 7 || exit 1
[ "$(order_state 7)" = shipped ] || exit 1
TEST
	# the test alone is red on the base: that is the point of it
	(cd "$wt" && sh tests/test_cancel_shipped.sh) && fail "the test passes with the bug"
	sed 's/created | paid | shipped)/created | paid)/' "$wt/app/order.sh" >"$T/order.sh" && cp "$T/order.sh" "$wt/app/order.sh"
	fm_set "$wt/specs/002-cancel-shipped/slices/S1.md" status review
	commit_in "$wt" "a shipped order is not cancelled"
	(cd "$wt" && ./softwary formal verified order compatible) >"$OUT" 2>&1 || fail "formal verified in the job: $(cat "$OUT")"
	commit_in "$wt" "the order model is verified against the code"
	sw job event $job implemented
	assert_eq "$RC" 0 "implemented"
	sw job gate $job
	assert_eq "$RC" 0 "gate exit code"
	assert_eq "$(job_get $job state)" pr "state after the gate"
	log=$REPO/$JOBS_REL/$job/repro-1.log
	assert_match "$log" "^repro: tests/test_cancel_shipped\\.sh fails on the base$"
	assert_match "$log" "^repro: tests/test_cancel_shipped\\.sh passes on the job$"
	sw job pr $job
	assert_eq "$RC" 0 "pr"
	sw job ci $job
	assert_eq "$RC" 0 "ci"
	mkdir -p "$wt/specs/002-cancel-shipped/reviews"
	printf -- '---\nslice: S1\ndecision: approve\n---\n\n# Review of S1\n' >"$wt/specs/002-cancel-shipped/reviews/S1.md"
	sw job review $job
	assert_eq "$RC" 0 "review"
	write_decision $job merge
	sw merge $job
	assert_eq "$RC" 0 "merge exit code: $(cat "$OUT")"
	assert_match "$OUT" "^merged: $job [0-9a-f]{40}$"
	assert_eq "$(job_get $job state)" merged "state"
	! grep -F 'created | paid | shipped' "$REPO/app/order.sh" >/dev/null || fail "the merged code still cancels a shipped order"
	[ -f "$REPO/tests/test_cancel_shipped.sh" ] || fail "the merged test is missing"
	# the second report: its test passes on the base, so it proves nothing
	job=003-S1
	sw job start $job
	assert_eq "$RC" 0 "job start $job"
	wt=$(job_wt $job)
	cat >"$wt/tests/test_cancel_created.sh" <<'TEST'
#!/bin/sh
# covers AC-003-01: a created order is cancelled
. "$(dirname "$0")/../app/order.sh"
ORDER_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$ORDER_DIR"' EXIT
order_create 7 && order_cancel 7 || exit 1
[ "$(order_state 7)" = cancelled ] || exit 1
TEST
	fm_set "$wt/specs/003-cancel-created/slices/S1.md" status review
	commit_in "$wt" "a test that passes without a fix"
	sw job event $job implemented
	sw job gate $job
	assert_eq "$RC" 0 "gate exit code (the failure is recorded)"
	assert_eq "$(job_get $job state)" implementing "state after a repro that proves nothing"
	last=$(tail -n 1 "$REPO/$EVENTS_REL")
	assert_eq "$(printf '%s' "$last" | jq -r .event)" gate_fail "event"
	assert_eq "$(printf '%s' "$last" | jq -r .detail)" "repro: tests/test_cancel_created.sh passes on the base (it does not reproduce the bug)" "detail"
	assert_no_match "$REPO/$JOBS_REL/$job/gate-1.log" "^sync "
	# the gate and the merge never touched the production branch
	! grep -E '^pr merge [^1]' "$T/gh.log" >/dev/null || fail "gh pr merge was called for another pull request"
	[ ! -e "$T/deployed" ] || fail "the deploy command was run"
}

# AC-V7-12: the examples nobody tests are drift: `ship prepare` stops at them
# and says why; with a decision for each it goes through and writes the note;
# the note is filled in, checks clean and becomes a pull request from main to
# master, which nobody merges and which deploys nothing.
test_ac_v7_12_drift_stops_ship_then_the_note_becomes_a_pull_request() {
	need_tlc || return 0
	shop
	add_existing_artifacts
	commit_all "the product and the blueprint, drawn from the code"
	existing_verified
	add_origin
	add_production
	fake_gh
	printf 'A line the release is made of.\n' >>"$REPO/README.md"
	commit_all "more of the shop"
	git -C "$REPO" push -q --no-verify origin main
	master=$(git -C "$T/origin.git" rev-parse master)
	sw ship prepare
	assert_eq "$RC" 1 "ship prepare with undecided drift"
	assert_contains "$OUT" "ship: drift has undecided or expired items (./softwary drift)"
	[ ! -e "$REPO/.softwary/state/releases" ] || [ -z "$(ls "$REPO/.softwary/state/releases")" ] || fail "a note was written"
	sw drift
	assert_eq "$RC" 1 "drift exit code"
	assert_match "$OUT" "^drift: unexercised EX-F1-01: undecided$"
	assert_match "$OUT" "^drift: unexercised EX-F5-01: undecided$"
	assert_no_match "$OUT" "^drift: (uncovered|missing|empty|planned-with-code)"
	{
		printf '# Drift decisions\n\n| Item | Decision | Until | Reason |\n| --- | --- | --- | --- |\n'
		sed -n "s/^drift: \\(.*\\): undecided\$/| \\1 | accept | $FAR | the shop checks it by hand |/p" "$OUT"
	} >"$REPO/architecture/drift.md"
	sw drift
	assert_eq "$RC" 0 "drift exit code with a decision for each"
	commit_all "the drift is decided"
	git -C "$REPO" push -q --no-verify origin main
	sw ship prepare
	assert_eq "$RC" 0 "ship prepare: $(cat "$OUT")"
	f=$REPO/.softwary/state/releases/$(git -C "$REPO" rev-parse --short=7 main).md
	[ -f "$f" ] || fail "no note at $f"
	assert_eq "$(grep '^## ' "$f" | paste -sd, -)" "## Range,## Specs,## Decisions,## Risk,## Waivers and findings,## Drift,## Observability,## Rollout,## Rollback" "headings of the note"
	assert_match "$f" "^- 0001: The model, drawn from the code \\(proposed\\)$"
	assert_match "$f" "^- waiver lint: until $FAR "
	assert_match "$f" "^- finding order/ShippedWasPaid: until $FAR "
	assert_match "$f" "^- unexercised EX-F1-01: accept \\(until $FAR\\): the shop checks it by hand$"
	sw ship check
	assert_eq "$RC" 1 "ship check with the sections unwritten"
	assert_eq "$(grep -c '^ship: ## ' "$OUT")" 3 "problems"
	sed -e '/^## Observability$/,/^## Rollout$/ s/^UNSET$/Watch the share of orders shipped unpaid: it must stay at zero./' \
		-e '/^## Rollout$/,/^## Rollback$/ s/^UNSET$/One shop first, the rest a day later./' \
		-e '/^## Rollback$/,$ s/^UNSET$/Revert the merge; the order files are not migrated./' "$f" >"$T/note" && cp "$T/note" "$f"
	sw ship check
	assert_eq "$RC" 0 "ship check: $(cat "$OUT")"
	sw ship pr
	assert_eq "$RC" 0 "ship pr: $(cat "$OUT")"
	assert_contains "$OUT" "https://github.com/o/r/pull/1"
	assert_eq "$(cat "$T/gh/base-1")" master "base of the pull request"
	assert_eq "$(cat "$T/gh/branch-1")" main "head of the pull request"
	cmp -s "$T/gh/body-1" "$f" || fail "the body of the pull request is not the note"
	assert_eq "$(jq -r 'select(.event == "ship_pr") | .detail' "$REPO/$EVENTS_REL")" "https://github.com/o/r/pull/1" "ship_pr event"
	# nobody merged it and nothing deployed
	! grep -F "pr merge" "$T/gh.log" >/dev/null || fail "gh pr merge was called"
	[ ! -e "$T/deployed" ] || fail "the deploy command was run"
	assert_eq "$(git -C "$T/origin.git" rev-parse master)" "$master" "master in origin"
	sw ship pr
	assert_eq "$RC" 1 "a second ship pr"
	assert_contains "$OUT" "is already open: https://github.com/o/r/pull/1"
}

run_tests "$0"
