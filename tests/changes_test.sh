#!/bin/sh
# Tests for ./softwary changes (M4): every source change has a spec.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

S2=specs/001-login/slices/S2.md
SPEC=specs/001-login/spec.md

# setup_changes: the sample specs and a src/ file committed on main, a feature
# branch checked out; src_paths = src.
setup_changes() {
	setup_repo
	conf_all true
	add_specs
	printf 'v1\n' >"$REPO/src/app.txt"
	git -C "$REPO" symbolic-ref HEAD refs/heads/main
	commit_all base
	git -C "$REPO" checkout -qb feature
}

# AC-M4-06: a change outside src_paths needs no slice.
test_ac_m4_06_no_source_change() {
	setup_changes
	printf 'x\n' >"$REPO/notes.txt"
	sw changes
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^changes: no changes under src_paths$"
}

# AC-M4-06: a source change without a slice in the change fails and lists the
# paths: committed, uncommitted and untracked ones alike. A done slice that
# only sits on the base does not count.
test_ac_m4_06_source_change_without_slice() {
	setup_changes
	printf 'v2\n' >"$REPO/src/app.txt"
	commit_all "committed change"
	printf 'new\n' >"$REPO/src/new.txt"
	mkdir -p "$REPO/src/sub" && printf 'x\n' >"$REPO/src/sub/x.txt"
	sw changes
	assert_eq "$RC" 1 "exit code"
	for p in src/app.txt src/new.txt src/sub/x.txt; do
		assert_match "$OUT" "^$p: no slice in this change covers it$"
	done
	assert_match "$OUT" "^changes: 3 path\(s\) under src_paths changed without an active slice of an approved spec$"
}

# AC-M4-06: git quotes names with quotes or tabs; such a source file is still gated.
test_ac_m4_06_quoted_source_names() {
	setup_changes
	printf 'x\n' >"$REPO/src/a\"b.txt"
	sw changes
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^changes: 1 path\\(s\\) under src_paths changed"
}

# AC-M4-06: a slice in the change that is in progress, in review or done, of an
# approved or done spec, covers the change.
test_ac_m4_06_active_slice_covers() {
	setup_changes
	printf 'v2\n' >"$REPO/src/app.txt"
	for st in in-progress review "done"; do
		fm_set "$REPO/$S2" status "$st"
		sw changes
		assert_eq "$RC" 0 "exit code with a slice in $st"
		assert_match "$OUT" "^changes: covered by $S2$"
	done
	fm_set "$REPO/$SPEC" status "done"
	sw changes
	assert_eq "$RC" 0 "exit code with a done spec"
}

# AC-M4-06: a planned slice, or a slice of a spec that is not approved, does not cover.
test_ac_m4_06_inactive_slice_does_not_cover() {
	setup_changes
	printf 'v2\n' >"$REPO/src/app.txt"
	printf '\nA note.\n' >>"$REPO/$S2"
	sw changes
	assert_eq "$RC" 1 "exit code with a planned slice"
	fm_set "$REPO/$S2" status in-progress
	fm_set "$REPO/$SPEC" status draft
	sw changes
	assert_eq "$RC" 1 "exit code with a draft spec"
	assert_match "$OUT" "^src/app\.txt: no slice in this change covers it$"
}

# AC-M4-06: src_paths not set, a src_paths entry that does not exist and a
# missing base are configuration problems (2).
test_ac_m4_06_configuration_problems() {
	setup_changes
	conf_del src_paths
	sw changes
	assert_eq "$RC" 2 "exit code without src_paths"
	assert_match "$OUT" "src_paths is not set"
	conf_set src_paths "src nope"
	sw changes
	assert_eq "$RC" 2 "exit code with a missing path"
	assert_match "$OUT" "src_paths: 'nope' not found"
	conf_set src_paths src
	sw changes --base nope
	assert_eq "$RC" 2 "exit code with a missing base"
	assert_match "$OUT" "base 'nope' not found"
	sw changes --bogus
	assert_eq "$RC" 2 "exit code with a bad option"
}

# AC-M4-06: verify --base runs changes after adr, as the last package check.
test_ac_m4_06_verify_base_order() {
	setup_changes
	printf 'v2\n' >"$REPO/src/app.txt"
	sw verify --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^changes +FAIL"
	for c in sync model views trace adr changes; do
		grep -n "^$c " "$OUT" | cut -d: -f1
	done >"$T/order"
	assert_eq "$(paste -sd' ' "$T/order")" "$(sort -n "$T/order" | paste -sd' ' -)" "package check order"
	assert_eq "$(wc -l <"$T/order" | tr -d ' ')" 6 "six package checks"
	fm_set "$REPO/$S2" status in-progress
	sw verify --base main
	assert_eq "$RC" 0 "exit code with a slice"
	assert_match "$OUT" "^changes +PASS"
	# V1: bare verify runs changes too, against the integration branch.
	sw verify
	assert_match "$OUT" "^changes +PASS"
}

run_tests "$0"
