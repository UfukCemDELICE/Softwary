#!/bin/sh
# AC-M0-09: the same behaviour in two sample repos on different stacks, and
# no stack-specific code under src/.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck disable=SC2329 # test functions are called by run_tests

STACKS="python node"

# Makes the sample's unit test fail.
break_python() { printf 'def add(a, b):\n    return a - b\n' >"$REPO/calc.py"; }
break_node() { printf 'module.exports = { add: (a, b) => a - b };\n' >"$REPO/calc.js"; }

# Status lines only, without durations or failure details, so stacks compare.
normalise() {
	grep -E '^[a-z_]+ +(PASS|FAIL|SKIP)|^UNSET ' "$OUT" | sed -E 's/\([0-9]+s\)/(Ns)/'
}

# run_scenarios STACK: runs the shared scenarios in a fresh sample repo and
# writes a transcript (exit codes and status lines) to $T/STACK.transcript.
run_scenarios() {
	_stack=$1
	_tr=$T/$_stack.transcript
	REPO=$T/$_stack
	cp -R "$PKG_ROOT/tests/fixtures/$_stack-sample" "$REPO"
	git -C "$REPO" init -q || fail "git init failed"
	sh "$PKG_ROOT/install.sh" "$REPO" >/dev/null 2>&1 || fail "$_stack: install failed"
	: >"$_tr"

	sw verify
	{ echo "== fresh: $RC"; normalise; } >>"$_tr"
	cp "$REPO/fixture.conf" "$REPO/.softwary/config/commands.conf"

	sw doctor
	{ echo "== doctor: $RC"; } >>"$_tr"
	sw verify
	{ echo "== configured: $RC"; normalise; } >>"$_tr"
	sw verify --fast
	{ echo "== fast: $RC"; normalise; } >>"$_tr"

	"break_$_stack"
	sw verify
	{ echo "== broken: $RC"; normalise; } >>"$_tr"
	[ -s "$REPO/.softwary/state/logs/verify-test.log" ] || fail "$_stack: test log missing"
}

# AC-M0-09: python sample behaves as expected.
test_ac_m0_09_python_sample() {
	command -v python3 >/dev/null || fail "python3 is required for this test"
	run_scenarios python
	tr=$T/python.transcript
	assert_match "$tr" "^== fresh: 2$"
	assert_match "$tr" "^== doctor: 0$"
	assert_match "$tr" "^== configured: 0$"
	assert_match "$tr" "^== fast: 0$"
	assert_match "$tr" "^== broken: 1$"
	assert_match "$tr" "^test +FAIL \(Ns\)$"
	assert_match "$tr" "^build +PASS \(Ns\)$"
	assert_match "$tr" "^security +SKIP \(sample has no dependencies\)$"
}

# AC-M0-09: both stacks produce identical exit codes and status lines.
test_ac_m0_09_same_behaviour_on_two_stacks() {
	command -v python3 >/dev/null || fail "python3 is required for this test"
	command -v node >/dev/null || fail "node is required for this test"
	command -v npm >/dev/null || fail "npm is required for this test"
	for s in $STACKS; do
		run_scenarios "$s"
	done
	OUT=$T/node.transcript
	cmp -s "$T/python.transcript" "$T/node.transcript" ||
		fail "transcripts differ: $(diff "$T/python.transcript" "$T/node.transcript")"
	assert_match "$OUT" "^== broken: 1$"
}

# AC-M0-09: src/ and install.sh contain no language, framework or package manager specifics.
test_ac_m0_09_no_stack_specific_code() {
	words='npm|npx|yarn|pnpm|node|nodejs|deno|bun|python|python3|pip|poetry|pytest|ruby|gem|bundler|rake|cargo|rustc|golang|java|javac|maven|mvn|gradle|kotlin|dotnet|nuget|php|composer|swift|make|cmake|docker|django|rails|react|spring'
	hits=$(cd "$PKG_ROOT" && grep -R -n -i -w -E "$words" src install.sh)
	[ -z "$hits" ] || fail "stack-specific references found: $hits"
}

run_tests "$0"
