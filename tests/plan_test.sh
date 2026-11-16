#!/bin/sh
# Tests for ./softwary plan check and plan approve (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

S1=specs/001-login/slices/S1.md
S2=specs/001-login/slices/S2.md
SPEC1=specs/001-login/spec.md
SPEC2=specs/002-tasks/spec.md
T1=specs/002-tasks/slices/S1.md
EVENTS_REL=.softwary/state/events.log

# ready: a repo with an approved product and blueprint and the sample plan.
ready() {
	setup_repo
	add_product
	add_blueprint
	sw approve product
	assert_eq "$RC" 0 "approve product"
	sw approve blueprint
	assert_eq "$RC" 0 "approve blueprint"
	add_plan
}

# write_analysis SPECDIR DECISION [DIGEST]: the analyst's record for a spec;
# the digest defaults to the spec's current one.
write_analysis() {
	_id=${1#specs/}
	_id=${_id%%-*}
	_dg=${3:-$(git -C "$REPO" hash-object "$1/spec.md")}
	printf -- '---\nspec: %s\ndigest: %s\ndecision: %s\n---\n\n# Analysis of %s\n' "$_id" "$_dg" "$2" "$_id" >"$REPO/$1/analysis.md"
}

# AC-V2-05: approved inputs and a linked, acyclic plan are clean.
test_ac_v2_05_clean_plan_passes() {
	ready
	sw plan check
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^plan: clean \(2 specs\)$"
}

# AC-V2-05: a missing or stale approval is a line of its own.
test_ac_v2_05_approvals_required() {
	ready
	rm "$REPO/.softwary/config/approvals.conf"
	sw plan check
	assert_eq "$RC" 1 "exit code with no approvals"
	assert_match "$OUT" "^product: approval is missing \(run \./softwary approve product\)$"
	assert_match "$OUT" "^blueprint: approval is missing \(run \./softwary approve blueprint\)$"
	sw approve product
	sw approve blueprint
	printf '\n' >>"$REPO/product/PRODUCT.md"
	sw plan check
	assert_eq "$RC" 1 "exit code with a stale approval"
	assert_match "$OUT" "^product: approval is stale \(run \./softwary approve product\)$"
	assert_no_match "$OUT" "^blueprint:"
}

# AC-V2-05: every criterion of a draft or approved spec links to an example
# of PRODUCT.md; a done spec is not checked.
test_ac_v2_05_criterion_example_links() {
	ready
	sed 's/ Covers EX-F1-01\.//' "$REPO/$SPEC1" >"$T/s" && cp "$T/s" "$REPO/$SPEC1"
	sed 's/EX-F2-01/EX-F2-09/' "$REPO/$SPEC2" >"$T/s" && cp "$T/s" "$REPO/$SPEC2"
	sw plan check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$SPEC1: AC-001-01: no example link"
	assert_match "$OUT" "^$SPEC2: AC-002-01: unknown example EX-F2-09$"
	assert_no_match "$OUT" "AC-001-02"
	fm_set "$REPO/$SPEC1" status "done"
	fm_set "$REPO/$SPEC2" status "done"
	sw plan check
	assert_eq "$RC" 0 "exit code with done specs"
}

# AC-V2-05: a slice may depend on a slice of another spec; an unknown one is
# reported by plan check and by trace.
test_ac_v2_05_cross_spec_dependency() {
	ready
	sw trace
	assert_eq "$RC" 0 "trace exit code with a cross-spec dependency"
	fm_set "$REPO/$T1" depends_on "001-S2, 001-S9, 007-S1"
	sw plan check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$T1: depends_on: unknown slice '001-S9'$"
	assert_match "$OUT" "^$T1: depends_on: unknown slice '007-S1'$"
	sw trace
	assert_eq "$RC" 1 "trace exit code"
	assert_match "$OUT" "^$T1: depends_on: unknown slice '001-S9'$"
	fm_set "$REPO/$T1" depends_on "002-S1"
	sw trace
	assert_match "$OUT" "^$T1: depends_on: a slice cannot depend on itself$"
}

# AC-V2-05: a dependency cycle lists the slices that cannot be ordered.
test_ac_v2_05_cycle_lists_members() {
	ready
	fm_set "$REPO/$S1" depends_on "002-S1"
	sw plan check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^plan: dependency cycle among: 001-S1 001-S2 002-S1$"
	fm_set "$REPO/$S1" depends_on ""
	fm_set "$REPO/$S2" depends_on "S1, 002-S1"
	sw plan check
	assert_eq "$RC" 1 "exit code with another cycle"
	assert_match "$OUT" "^plan: dependency cycle among: 001-S2 002-S1$"
}

# AC-V2-05: trace's problems are part of plan check's result.
test_ac_v2_05_includes_trace() {
	ready
	fm_set "$REPO/$S1" acs "AC-001-01, AC-001-09"
	sw plan check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$S1: acs: AC-001-09 is not in the spec$"
	assert_match "$OUT" "^plan: [0-9]+ problem\(s\)$"
}

# AC-V2-05: a draft spec needs no open question and at most 600 words, as an
# approved one does.
test_ac_v2_05_draft_spec_is_ready_to_approve() {
	ready
	printf -- '- Which hash?\n' >>"$REPO/$SPEC2"
	sw plan check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$SPEC2: open questions: a spec must have none to be approved$"
}

# AC-V2-05: a malformed approvals.conf is a configuration error.
test_ac_v2_05_bad_approvals_conf_exits_2() {
	ready
	printf 'product = nothex\n' >"$REPO/.softwary/config/approvals.conf"
	sw plan check
	assert_eq "$RC" 2 "exit code"
}

# AC-V2-06: a clean draft spec with a passing, current analysis is approved,
# by id or by directory.
test_ac_v2_06_plan_approve_happy_path() {
	ready
	write_analysis specs/002-tasks pass
	sw plan approve 002
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(sed -n 's/^status: //p' "$REPO/$SPEC2")" approved "status"
	assert_eq "$(jq -r .event "$REPO/$EVENTS_REL" | tail -n 1)" plan_approve "event"
	assert_eq "$(jq -r .detail "$REPO/$EVENTS_REL" | tail -n 1)" "002-tasks" "detail"
	sw plan check
	assert_eq "$RC" 0 "plan check after approving"
	fm_set "$REPO/$SPEC2" status draft
	sw plan approve 002-tasks
	assert_eq "$RC" 0 "exit code with the directory name"
	assert_eq "$(sed -n 's/^status: //p' "$REPO/$SPEC2")" approved "status again"
}

# AC-V2-06: every refusal says why, changes nothing and exits 1.
test_ac_v2_06_refusals() {
	ready
	refuse() {
		cp "$REPO/$SPEC2" "$T/before"
		sw plan approve 002
		assert_eq "$RC" 1 "exit code: $1"
		assert_contains "$OUT" "$1"
		cmp -s "$T/before" "$REPO/$SPEC2" || fail "the spec changed: $1"
	}
	refuse "no analysis"
	write_analysis specs/002-tasks fail
	refuse "decision is fail"
	write_analysis specs/002-tasks pass 0000000000000000000000000000000000000000
	refuse "analysis is of another version"
	write_analysis specs/002-tasks pass
	sed 's/^spec: 002$/spec: 001/' "$REPO/specs/002-tasks/analysis.md" >"$T/a" && cp "$T/a" "$REPO/specs/002-tasks/analysis.md"
	refuse "analysis is of spec 001"
	write_analysis specs/002-tasks pass
	sed 's/ Covers EX-F2-01\.//' "$REPO/$SPEC2" >"$T/s" && cp "$T/s" "$REPO/$SPEC2"
	write_analysis specs/002-tasks pass
	refuse "plan check reports problems"
	assert_contains "$OUT" "AC-002-01: no example link"
	cp "$V2FIX/specs/002-tasks/spec.md" "$REPO/$SPEC2"
	write_analysis specs/002-tasks pass
	printf '\n' >>"$REPO/product/PRODUCT.md"
	refuse "plan check reports problems"
	assert_contains "$OUT" "product: approval is stale"
	sw approve product
	sw approve blueprint
	write_analysis specs/001-login pass
	cp "$REPO/$SPEC1" "$T/before"
	sw plan approve 001
	assert_eq "$RC" 1 "exit code for an approved spec"
	assert_contains "$OUT" "is approved, not draft"
	cmp -s "$T/before" "$REPO/$SPEC1" || fail "the approved spec changed"
}

# AC-V2-06: an unknown spec and a missing argument exit 2.
test_ac_v2_06_usage_and_unknown_spec() {
	ready
	sw plan approve 009
	assert_eq "$RC" 2 "exit code for an unknown spec"
	sw plan approve
	assert_eq "$RC" 2 "exit code without a spec"
	sw plan
	assert_eq "$RC" 2 "exit code without a subcommand"
	assert_contains "$OUT" "usage: ./softwary plan check | plan approve <spec>"
}

run_tests "$0"
