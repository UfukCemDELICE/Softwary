#!/bin/sh
# Tests for ./softwary status (M2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# add_adr ID STATUS TITLE: writes architecture/decisions/ID-x.md.
add_adr() {
	mkdir -p "$REPO/architecture/decisions"
	printf -- '---\nid: %s\ntitle: %s\nstatus: %s\naffects: api\n---\n\n# %s\n' "$1" "$3" "$2" "$3" \
		>"$REPO/architecture/decisions/$1-x.md"
}

# AC-M2-09: one line per spec with id, status, risk and slice counts by status.
test_ac_m2_09_specs_and_slices() {
	setup_repo
	conf_all true
	add_specs
	mkdir -p "$REPO/specs/002-export"
	sed 's/^id: 001$/id: 002/; s/^title: Login$/title: Export/; s/^status: approved$/status: draft/; s/^risk: R1$/risk: R3/' \
		"$REPO/specs/001-login/spec.md" >"$REPO/specs/002-export/spec.md"
	snapshot >"$T/before"
	sw status
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^001 +approved +R1 +Login +slices: 1 done, 1 planned$"
	assert_match "$OUT" "^002 +draft +R3 +Export +slices: none$"
	snapshot >"$T/after"
	cmp -s "$T/before" "$T/after" || fail "status wrote files: $(changed_paths "$T/before" "$T/after")"
}

# AC-M2-09: ADRs waiting for a decision are listed; others are not.
test_ac_m2_09_proposed_adrs() {
	setup_repo
	add_adr 0001 accepted 'Use CALM'
	add_adr 0002 proposed 'Use Postgres'
	sw status
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^no specs$"
	assert_match "$OUT" "^ADR 0002 +proposed +Use Postgres$"
	assert_no_match "$OUT" "Use CALM"
}

# AC-M2-09: an unreadable artifact is shown, not hidden.
test_ac_m2_09_unreadable_spec() {
	setup_repo
	mkdir -p "$REPO/specs/003-broken"
	printf 'no front matter\n' >"$REPO/specs/003-broken/spec.md"
	sw status
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^003 +\? +\? +\? +slices: none \(run \./softwary trace\)$"
}

run_tests "$0"
