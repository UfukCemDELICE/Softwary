#!/bin/sh
# End to end on an existing repository (V6): a small shop's order scripts with
# a red lint, a failing test, an order that is shipped without being paid, and
# no softwary. The example is tests/fixtures/existing. The tests need Java and
# the pinned jar (SW_SKIP_FORMAL=<reason> skips them, visibly).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
WAIVERS_REL=.softwary/config/waivers.conf
ORDER_MD=architecture/formal/order.md

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

# shop: the existing repository with softwary installed and configured, its
# own files and AGENTS.md kept; both tools on, generated files committed.
shop() {
	setup_repo --no-model
	add_existing
	existing_conf
	tools_set claude-code on
	tools_set codex on
	sw sync
	assert_eq "$RC" 0 "sync"
	commit_all "softwary installed"
}

# waive: the debt of the shop, as the setup skill records it once the human
# has said so: lint and test are waived until DATE, each with its scoped command.
waive() {
	printf 'lint = %s: legacy lint debt, fixed file by file\ntest = %s: legacy report test\n' "$1" "$1" >"$REPO/$WAIVERS_REL"
	conf_set lint_files 'sh checks/lint.sh {files}'
	conf_set test_files 'sh checks/test.sh {files}'
}

# AC-V6-14: setup in an existing repository: the shop keeps its own files, the
# red checks are found and waived with a scoped command, and nothing else is
# left but the model.
test_ac_v6_14_setup_and_waivers() {
	shop
	assert_contains "$REPO/AGENTS.md" "Plain \`sh\` only."
	assert_contains "$REPO/AGENTS.md" "Never edit a file under \`orders-data/\`"
	assert_contains "$REPO/README.md" "Shop orders"
	[ -n "$(block_of "$REPO/AGENTS.md")" ] || fail "AGENTS.md has no softwary block"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code before the model"
	assert_match "$OUT" "^model +FAIL "
	assert_match "$OUT" "^doctor: 1 problem\\(s\\) found$"
	# there is no model yet: verify stops at it; the static checks run, the red lint is found
	sw verify
	assert_eq "$RC" 2 "verify exit code without a model"
	assert_match "$OUT" "^model: architecture/model/system.calm.json not found"
	sw verify --fast
	assert_eq "$RC" 1 "verify --fast exit code"
	assert_match "$OUT" "^lint +FAIL "
	assert_match "$OUT" "app/report.sh:3:"
	assert_match "$OUT" "^typecheck +PASS "
	(cd "$REPO" && sh checks/test.sh) >"$OUT" 2>&1 && fail "the shop's tests pass"
	assert_match "$OUT" "^FAIL  tests/test_order_report.sh$"
	# the waivers need their scoped commands
	printf 'lint = 2999-12-31: legacy lint debt\ntest = 2999-12-31: legacy report test\n' >"$REPO/$WAIVERS_REL"
	sw doctor
	assert_match "$OUT" "^lint_files +FAIL \\(required: lint has a waiver\\)$"
	assert_match "$OUT" "^test_files +FAIL \\(required: test has a waiver\\)$"
	waive 2999-12-31
	sw doctor
	assert_eq "$RC" 2 "doctor exit code with the waivers"
	assert_match "$OUT" "^doctor: 1 problem\\(s\\) found$"
	sw verify --fast
	assert_eq "$RC" 0 "verify --fast exit code with the waiver"
	assert_match "$OUT" "^lint +WAIVED \\(legacy lint debt, fixed file by file, until 2999-12-31\\)$"
	assert_match "$OUT" "^lint \\(changed files\\) +SKIP \\(no base\\)$|^lint \\(changed files\\) +SKIP \\(no changed files\\)$"
}

# AC-V6-14: define, blueprint and plan on the existing code: the checks, the
# finding, the critic and the approvals; the waivers are shown.
test_ac_v6_14_product_blueprint_plan() {
	need_tlc || return 0
	shop
	waive 2999-12-31
	commit_all "waivers"
	add_existing_artifacts
	commit_all "the product and the blueprint, drawn from the code"
	sw verify --base main
	assert_eq "$RC" 0 "verify exit code"
	assert_match "$OUT" "^lint +WAIVED "
	assert_match "$OUT" "^lint \\(changed files\\) +SKIP \\(no changed files\\)$"
	assert_match "$OUT" "^test +WAIVED "
	assert_match "$OUT" "^test \\(changed files\\) +SKIP \\(no changed files\\)$"
	assert_match "$OUT" "^model_check +PASS "
	sw product check
	assert_eq "$RC" 0 "product check exit code"
	sw blueprint check
	assert_eq "$RC" 0 "blueprint check exit code"
	assert_match "$OUT" "^formal order: FINDING: ShippedWasPaid violated \\(until 2999-12-31: The old import path ships a created order that is not paid; feature F5 removes it\\.\\)$"
	assert_match "$OUT" '^  2\. An order is shipped \(ship\): everShipped = TRUE, status = "shipped"$'
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg fails on ShippedWasPaid$"
	assert_match "$OUT" "^formal order: PASS "
	assert_match "$OUT" "^blueprint: valid "
	sw next
	assert_match "$OUT" "^next: approve product \\(human\\)"
	sw approve product
	assert_eq "$RC" 0 "approve product exit code"
	sw next
	assert_match "$OUT" "^next: critique "
	approve_blueprint
	assert_eq "$RC" 0 "approve blueprint exit code"
	sw status
	assert_match "$OUT" "^approval product: approved$"
	assert_match "$OUT" "^approval blueprint: approved$"
	assert_match "$OUT" "^  waiver lint: until 2999-12-31 "
	assert_match "$OUT" "^  waiver test: until 2999-12-31 "
	assert_match "$OUT" "^  finding order/ShippedWasPaid: until 2999-12-31 .*: The old import path "
	# the finding is bound by the approval: a changed date makes it stale
	sed 's/2999-12-31 | The old/2999-12-30 | The old/' "$REPO/$ORDER_MD" >"$T/md" && cp "$T/md" "$REPO/$ORDER_MD"
	sw status
	assert_match "$OUT" "^approval blueprint: stale$"
	sed 's/2999-12-30 | The old/2999-12-31 | The old/' "$REPO/$ORDER_MD" >"$T/md" && cp "$T/md" "$REPO/$ORDER_MD"
	sw status
	assert_match "$OUT" "^approval blueprint: approved$"
	# plan: the analyst's pass for this version of the spec, then the approval
	digest=$(git -C "$REPO" hash-object "specs/001-ship-paid/spec.md")
	printf -- '---\nspec: 001\ndigest: %s\ndecision: pass\n---\n\n# Analysis of 001\n' "$digest" >"$REPO/specs/001-ship-paid/analysis.md"
	sw plan approve 001
	assert_eq "$RC" 0 "plan approve exit code"
	sw plan check
	assert_eq "$RC" 0 "plan check exit code"
}

# implement ROUND: what the implementer does in the job's worktree for the
# slice: the shop's rule (an order that is not paid is not shipped) in
# app/order.sh and a test that names both criteria. In round 1 it also leaves
# a marker the lint of the shop reports.
implement() {
	wt=$(job_wt $JOB)
	fm_set "$wt/specs/001-ship-paid/slices/S1.md" status in-progress
	sed 's/paid | created) order_put/paid) order_put/' "$wt/app/order.sh" >"$T/order.sh" && cp "$T/order.sh" "$wt/app/order.sh"
	cat >"$wt/tests/test_ship_paid_only.sh" <<'TEST'
#!/bin/sh
# covers AC-001-01 AC-001-02
. "$(dirname "$0")/../app/order.sh"
ORDER_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$ORDER_DIR"' EXIT
order_create 7 || exit 1
! order_ship 7 || exit 1
[ "$(order_state 7)" = created ] || exit 1
order_pay 7 && order_ship 7 || exit 1
[ "$(order_state 7)" = shipped ] || exit 1
TEST
	[ "$1" -ne 1 ] || printf '# X%s: remove before the merge\n' XX >>"$wt/app/order.sh"
	fm_set "$wt/specs/001-ship-paid/slices/S1.md" status review
	commit_in "$wt" "ship only paid orders (round $1)"
}

# AC-V6-14: a job that puts a lint error in the file it changes fails the gate
# although the repository's lint is red anyway; the corrected round passes, the
# PR is opened and the job merges.
test_ac_v6_14_job_gate_and_merge() {
	need_tlc || return 0
	shop
	waive 2999-12-31
	add_existing_artifacts
	commit_all "the product and the blueprint, drawn from the code"
	sw approve product
	approve_blueprint
	assert_eq "$RC" 0 "approve blueprint exit code"
	digest=$(git -C "$REPO" hash-object "specs/001-ship-paid/spec.md")
	printf -- '---\nspec: 001\ndigest: %s\ndecision: pass\n---\n\n# Analysis of 001\n' "$digest" >"$REPO/specs/001-ship-paid/analysis.md"
	sw plan approve 001
	assert_eq "$RC" 0 "plan approve exit code"
	loop_conf
	add_eval
	add_origin
	fake_gh
	sw run start
	assert_eq "$RC" 0 "run start exit code"
	sw run next
	assert_eq "$(cat "$OUT")" "start $JOB" "run next"
	sw job start $JOB
	assert_eq "$RC" 0 "job start exit code"
	implement 1
	sw job event $JOB implemented
	assert_eq "$RC" 0 "implemented"
	sw job gate $JOB
	assert_eq "$RC" 0 "gate exit code"
	assert_eq "$(job_get state)" implementing "state after a failing gate"
	assert_eq "$(job_get round)" 2 "round"
	log=$REPO/$JOBS_REL/$JOB/gate-1.log
	assert_match "$log" "^lint +WAIVED "
	assert_match "$log" "^lint \\(changed files\\) +FAIL "
	assert_match "$log" "^ +app/order\\.sh:[0-9]+:"
	assert_match "$log" "^test \\(changed files\\) +PASS "
	# round 2: the marker is gone
	wt=$(job_wt $JOB)
	grep -v 'remove before the merge' "$wt/app/order.sh" >"$T/order.sh" && cp "$T/order.sh" "$wt/app/order.sh"
	commit_in "$wt" "round 2: remove the marker"
	sw job event $JOB implemented
	assert_eq "$RC" 0 "implemented again"
	sw job gate $JOB
	assert_eq "$RC" 0 "second gate exit code"
	assert_eq "$(job_get state)" pr "state after the gate"
	log=$REPO/$JOBS_REL/$JOB/gate-2.log
	assert_match "$log" "^lint \\(changed files\\) +PASS "
	assert_match "$log" "^test \\(changed files\\) +PASS "
	assert_match "$log" "^model_check +PASS "
	sw job pr $JOB
	assert_eq "$RC" 0 "pr"
	sw job ci $JOB
	assert_eq "$RC" 0 "ci"
	mkdir -p "$wt/specs/001-ship-paid/reviews"
	printf -- '---\nslice: S1\ndecision: approve\n---\n\n# Review of S1\n' >"$wt/specs/001-ship-paid/reviews/S1.md"
	sw job review $JOB
	assert_eq "$RC" 0 "review"
	write_decision $JOB merge
	sw merge $JOB
	assert_eq "$RC" 0 "merge exit code"
	assert_match "$OUT" "^merged: $JOB [0-9a-f]{40}$"
	assert_eq "$(job_get state)" merged "state"
	assert_match "$REPO/$JOBS_REL/$JOB/merge.log" "^lint \\(changed files\\) +PASS "
	assert_eq "$(git -C "$REPO" branch --show-current)" main "branch"
	! grep -F 'paid | created' "$REPO/app/order.sh" >/dev/null || fail "the merged code still ships an unpaid order"
	[ -f "$REPO/tests/test_ship_paid_only.sh" ] || fail "the merged test is missing"
	# the shop's own debt is still waived: lint and test are red as a whole
	sw verify --base main
	assert_eq "$RC" 0 "verify exit code after the merge"
	assert_match "$OUT" "^lint +WAIVED "
}

# AC-V6-14: when the dates pass, the waivers and the finding turn red again.
test_ac_v6_14_dates_pass() {
	need_tlc || return 0
	shop
	waive 2999-12-31
	add_existing_artifacts
	commit_all "the product and the blueprint, drawn from the code"
	sw verify --base main
	assert_eq "$RC" 0 "verify exit code before the dates"
	waive 2000-01-01
	sed 's/2999-12-31 | The old/2000-01-01 | The old/' "$REPO/$ORDER_MD" >"$T/md" && cp "$T/md" "$REPO/$ORDER_MD"
	sw verify --base main
	assert_eq "$RC" 1 "verify exit code after the dates"
	assert_match "$OUT" "^lint +FAIL \\([0-9]+s, waiver expired 2000-01-01\\)$"
	assert_match "$OUT" "^test +FAIL \\([0-9]+s, waiver expired 2000-01-01\\)$"
	assert_match "$OUT" "^model_check +FAIL "
	assert_no_match "$OUT" "changed files"
	sw formal check
	assert_eq "$RC" 1 "formal check exit code"
	assert_match "$OUT" "^formal order: FAIL: ShippedWasPaid violated \\(finding expired 2000-01-01\\)$"
	sw doctor
	assert_match "$OUT" "^waiver lint +FAIL \\(expired 2000-01-01: legacy lint debt, fixed file by file\\)$"
	sw status
	assert_match "$OUT" "^  waiver lint: until 2000-01-01 \\(expired\\): "
	assert_match "$OUT" "^  finding order/ShippedWasPaid: until 2000-01-01 \\(expired\\): "
}

run_tests "$0"
