#!/bin/sh
# Tests for ./softwary trace (M2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

SPEC=specs/001-login/spec.md
S1=specs/001-login/slices/S1.md
S2=specs/001-login/slices/S2.md

setup_trace() {
	setup_repo
	conf_all true
	add_specs
}

# expect_problem PATTERN: trace exits 1 and prints a line matching PATTERN.
expect_problem() {
	sw trace
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "$1"
	assert_match "$OUT" "^trace: [0-9]+ problem\(s\)$"
}

# AC-M2-05: a consistent spec with slices passes.
test_ac_m2_05_consistent_specs_pass() {
	setup_trace
	sw trace
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^trace: 1 spec\(s\), 2 slice\(s\), 3 criteria$"
}

# AC-M2-05: a repo without specs has nothing to trace.
test_ac_m2_05_no_specs() {
	setup_repo
	sw trace
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^trace: 0 spec\(s\), 0 slice\(s\), 0 criteria$"
}

# AC-M2-05: missing front matter and missing fields are reported.
test_ac_m2_05_missing_front_matter_and_fields() {
	setup_trace
	fm_del "$REPO/$SPEC" title
	expect_problem "^$SPEC: title: missing$"
	printf '# no front matter\n' >"$REPO/$S2"
	expect_problem "^$S2: missing front matter \(the first line must be ---\)$"
}

# AC-M2-05: invalid, unknown and UNSET field values are reported.
test_ac_m2_05_invalid_fields() {
	setup_trace
	fm_set "$REPO/$SPEC" status ready
	fm_set "$REPO/$SPEC" risk R5
	fm_set "$REPO/$S1" owner me
	fm_set "$REPO/$S2" goal UNSET
	fm_set "$REPO/$S2" status started
	sw trace
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$SPEC: status: 'ready' must be one of draft, approved, done$"
	assert_match "$OUT" "^$SPEC: risk: 'R5' must be one of R1, R2, R3$"
	assert_match "$OUT" "^$S1: unknown field 'owner'$"
	assert_match "$OUT" "^$S2: goal: is UNSET$"
	assert_match "$OUT" "^$S2: status: 'started' must be one of planned, in-progress, review, done$"
}

# AC-M2-05: ids must match the directory and file names.
test_ac_m2_05_ids_match_names() {
	setup_trace
	fm_set "$REPO/$SPEC" id 002
	fm_set "$REPO/$S1" id S3
	expect_problem "^$SPEC: id: '002' does not match the directory 001-login$"
	assert_match "$OUT" "^$S1: id: 'S3' does not match the file name S1\.md$"
	fm_set "$REPO/$SPEC" id 001
	fm_set "$REPO/$S1" id S1
	fm_set "$REPO/$S2" spec 007
	expect_problem "^$S2: spec: '007' is not this slice's spec \(001\)$"
	mkdir "$REPO/specs/login"
	expect_problem "^specs/login: directory name must be NNN-name$"
}

# AC-M2-05: every criterion belongs to exactly one slice.
test_ac_m2_05_criterion_in_exactly_one_slice() {
	setup_trace
	fm_set "$REPO/$S2" acs AC-001-01
	sw trace
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$SPEC: AC-001-03: in no slice$"
	assert_match "$OUT" "^$SPEC: AC-001-01: in more than one slice \(S1, S2\)$"
}

# AC-M2-05: a slice may not name a criterion that the spec does not have.
test_ac_m2_05_unknown_criterion() {
	setup_trace
	fm_set "$REPO/$S2" acs "AC-001-03, AC-001-09, AC-1"
	sw trace
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$S2: acs: AC-001-09 is not in the spec$"
	assert_match "$OUT" "^$S2: acs: 'AC-1' is not a criterion id of spec 001$"
}

# AC-M2-05: depends_on must name slices of the same spec.
test_ac_m2_05_depends_on() {
	setup_trace
	fm_set "$REPO/$S2" depends_on "S1, S9"
	expect_problem "^$S2: depends_on: unknown slice 'S9'$"
	fm_set "$REPO/$S2" depends_on S2
	expect_problem "^$S2: depends_on: a slice cannot depend on itself$"
}

# AC-M2-05: a spec that is not approved may not have slices.
test_ac_m2_05_slices_need_approved_spec() {
	setup_trace
	fm_set "$REPO/$SPEC" status draft
	expect_problem "^$S1: spec 001 is not approved$"
}

# AC-M2-05: model components and contract files named by the spec must exist.
test_ac_m2_05_model_and_contracts_exist() {
	setup_trace
	fm_set "$REPO/$SPEC" model "api, ghost"
	fm_set "$REPO/$SPEC" contracts architecture/contracts/login.yaml
	sw trace
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$SPEC: model: unknown component 'ghost'$"
	assert_match "$OUT" "^$SPEC: contracts: 'architecture/contracts/login\.yaml' not found$"
	mkdir -p "$REPO/architecture/contracts"
	: >"$REPO/architecture/contracts/login.yaml"
	fm_set "$REPO/$SPEC" model api
	sw trace
	assert_eq "$RC" 0 "exit code once both exist"
}

# AC-M2-05: a spec without slices is not checked for coverage.
test_ac_m2_05_spec_without_slices() {
	setup_trace
	rm -r "$REPO/specs/001-login/slices" "$REPO/specs/001-login/reviews"
	sw trace
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^trace: 1 spec\(s\), 0 slice\(s\), 3 criteria$"
}

# AC-M2-06: criteria of review and done slices must appear under test_paths.
test_ac_m2_06_done_slice_needs_tests() {
	setup_trace
	printf '# AC-001-01\n' >"$REPO/tests/test_login.py"
	expect_problem "^$S1: AC-001-02: not found under test_paths \(tests\)$"
	fm_set "$REPO/$S1" status review
	expect_problem "^$S1: AC-001-02: not found under test_paths"
	fm_set "$REPO/$S1" status in-progress
	sw trace
	assert_eq "$RC" 0 "exit code for an in-progress slice"
}

# AC-M2-06: a longer id is not a match (AC-001-010 does not count for AC-001-01).
test_ac_m2_06_longer_id_is_not_a_match() {
	setup_trace
	printf '# AC-001-010\n# AC-001-02\n' >"$REPO/tests/test_login.py"
	expect_problem "^$S1: AC-001-01: not found under test_paths"
	assert_no_match "$OUT" "AC-001-02: not found"
}

# AC-M2-06: test_paths may list several directories.
test_ac_m2_06_several_test_paths() {
	setup_trace
	mkdir "$REPO/more"
	printf '# AC-001-02\n' >"$REPO/more/b.sh"
	printf '# AC-001-01\n' >"$REPO/tests/test_login.py"
	conf_set test_paths 'tests more'
	sw trace
	assert_eq "$RC" 0 "exit code"
}

# AC-M2-06: test_paths must be set when a slice is in review or done.
test_ac_m2_06_test_paths_required() {
	setup_trace
	conf_del test_paths
	sw trace
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "test_paths is not set"
	conf_set test_paths missing-dir
	sw trace
	assert_eq "$RC" 2 "exit code for a missing directory"
	assert_match "$OUT" "test_paths: 'missing-dir' not found"
	conf_del test_paths
	fm_set "$REPO/$S1" status planned
	sw trace
	assert_eq "$RC" 0 "exit code when no slice needs tests"
}

# AC-M2-07: an approved spec has no open questions.
test_ac_m2_07_no_open_questions() {
	setup_trace
	printf -- '- Which hash function?\n' >>"$REPO/$SPEC"
	expect_problem "^$SPEC: open questions: an approved spec must have none$"
	rm -r "$REPO/specs/001-login/slices" "$REPO/specs/001-login/reviews"
	fm_set "$REPO/$SPEC" status draft
	sw trace
	assert_eq "$RC" 0 "exit code for a draft spec"
}

# AC-M2-07: an approved spec is at most 600 words.
test_ac_m2_07_word_limit() {
	setup_trace
	i=0
	while [ $i -lt 60 ]; do
		printf 'one two three four five six seven eight nine ten\n'
		i=$((i + 1))
	done >"$T/words"
	awk -v f="$T/words" '/^## Open questions/ { while ((getline l < f) > 0) print l; print "" } { print }' \
		"$REPO/$SPEC" >"$T/spec" && mv "$T/spec" "$REPO/$SPEC"
	expect_problem "^$SPEC: [0-9]+ words; an approved spec must be at most 600$"
	rm -r "$REPO/specs/001-login/slices" "$REPO/specs/001-login/reviews"
	fm_set "$REPO/$SPEC" status draft
	sw trace
	assert_eq "$RC" 0 "exit code for a draft spec"
}

R1=specs/001-login/reviews/S1.md

# AC-M4-05: a done slice needs a review whose decision is approve.
test_ac_m4_05_done_slice_needs_approving_review() {
	setup_trace
	rm "$REPO/$R1"
	expect_problem "^$S1: done without a review that approves it \\(specs/001-login/reviews/S1\\.md\\)$"
	add_specs
	fm_set "$REPO/$R1" decision changes
	expect_problem "^$S1: done without a review that approves it"
	# A slice that is not done needs no review.
	fm_set "$REPO/$S1" status review
	sw trace
	assert_eq "$RC" 0 "exit code for a slice in review"
}

# AC-M4-05: missing and invalid review fields, a slice that does not match the
# file name and a review of a slice that does not exist are reported.
test_ac_m4_05_review_fields() {
	setup_trace
	fm_set "$REPO/$R1" decision maybe
	expect_problem "^$R1: decision: 'maybe' must be one of approve, changes$"
	add_specs
	fm_del "$REPO/$R1" slice
	expect_problem "^$R1: slice: missing$"
	add_specs
	fm_set "$REPO/$R1" slice S2
	expect_problem "^$R1: slice: 'S2' does not match the file name S1\\.md$"
	add_specs
	cp "$REPO/$R1" "$REPO/specs/001-login/reviews/S9.md"
	fm_set "$REPO/specs/001-login/reviews/S9.md" slice S9
	expect_problem "^specs/001-login/reviews/S9\\.md: no slice S9 in specs/001-login/slices/$"
	rm "$REPO/specs/001-login/reviews/S9.md"
	printf 'x\n' >"$REPO/specs/001-login/reviews/notes.md"
	expect_problem "^specs/001-login/reviews/notes\\.md: file name must be S<n>\\.md$"
}

run_tests "$0"
