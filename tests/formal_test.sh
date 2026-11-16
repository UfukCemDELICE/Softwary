#!/bin/sh
# Tests for the TLA+ model of the merge protocol (V4): the model passes under
# TLC, and every broken variant fails the property it breaks.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

FORMAL=$PKG_ROOT/docs/formal

# formal_ready: TLC can be run (java and the pinned jar). With SW_SKIP_FORMAL
# set to a reason the tests are skipped, visibly; without java or the jar they
# fail.
formal_ready() {
	if [ -n "${SW_SKIP_FORMAL:-}" ]; then
		printf 'SKIP (%s)\n' "$SW_SKIP_FORMAL"
		return 1
	fi
	sh "$PKG_ROOT/tests/tlc.sh" --check >"$OUT" 2>&1 || fail "TLC is not available (set SW_SKIP_FORMAL=<reason> to skip)"
}

# tlc CONFIG: runs TLC on a config of docs/formal; sets RC and OUT.
tlc() {
	RC=0
	sh "$PKG_ROOT/tests/tlc.sh" "$FORMAL/$1" >"$OUT" 2>&1 || RC=$?
}

# AC-V4-13: the protocol as built satisfies every invariant and Progress.
test_ac_v4_13_model_passes() {
	formal_ready || return 0
	tlc merge.cfg
	assert_eq "$RC" 0 "TLC exit code"
	assert_match "$OUT" "^Model checking completed\\. No error has been found\\."
	for name in TypeOK GateBeforeMerge NoMergeWhileHalted NoOverlap SingleMerger QueueKept QueueOwned MergedOnce; do
		assert_match "$FORMAL/merge.cfg" "^  $name\$"
	done
	assert_match "$FORMAL/merge.cfg" "^  Progress\$"
}

# AC-V4-13: each broken variant fails exactly the property it breaks.
test_ac_v4_13_each_variant_fails() {
	formal_ready || return 0
	for pair in nogate:GateBeforeMerge nooverlap:NoOverlap nolock:SingleMerger racyrelease:QueueOwned \
		nostale:Progress haltignored:NoMergeWhileHalted splitdequeue:QueueKept norecover:MergedOnce; do
		variant=${pair%%:*}
		prop=${pair#*:}
		tlc "merge-$variant.cfg"
		if [ "$prop" = Progress ]; then
			assert_eq "$RC" 13 "TLC exit code for $variant"
			assert_match "$OUT" "^Error: Temporal propert(y Progress was|ies were) violated"
		else
			assert_eq "$RC" 12 "TLC exit code for $variant"
			assert_match "$OUT" "^Error: Invariant $prop is violated\\."
		fi
		assert_contains "$FORMAL/merge-$variant.cfg" "Bug = \"$variant\""
	done
	assert_eq "$(find "$FORMAL" -name 'merge-*.cfg' | wc -l | tr -d ' ')" 8 "variant configs"
}

# AC-V4-13: without java the tests fail; only SW_SKIP_FORMAL=<reason> skips
# them, and says so.
test_ac_v4_13_skip_is_visible() {
	RC=0
	(
		SW_SKIP_FORMAL="no java on this machine"
		export SW_SKIP_FORMAL
		formal_ready
	) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 1 "formal_ready under a skip"
	assert_eq "$(cat "$OUT")" "SKIP (no java on this machine)" "what is printed"
	RC=0
	(
		unset SW_SKIP_FORMAL
		PATH=$(path_without java)
		export PATH
		formal_ready
	) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 1 "formal_ready without java"
	assert_contains "$OUT" "TLC is not available"
	RC=0
	(
		unset SW_SKIP_FORMAL
		PATH=$(path_without java)
		export PATH
		sh "$PKG_ROOT/tests/tlc.sh" --check
	) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "tlc.sh without java"
	assert_contains "$OUT" "java is not installed"
	RC=0
	printf 'not a jar\n' >"$T/other.jar"
	SW_TLA2TOOLS=$T/other.jar sh "$PKG_ROOT/tests/tlc.sh" --check >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "tlc.sh with another jar"
	assert_contains "$OUT" "is not tla2tools 1.8.0"
}

run_tests "$0"
