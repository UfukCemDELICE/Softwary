#!/bin/sh
# Runs every tests/*_test.sh of the sample: each test_* function in its own
# subshell. Exits 1 if one fails. only_* functions, when there are any, run
# instead of the test_* ones.
dir=$(cd "$(dirname "$0")" && pwd -P)
root=$(cd "$dir/.." && pwd -P)
export root

# assert_eq ACTUAL EXPECTED: ends the test when they differ.
assert_eq() {
	if [ "$1" != "$2" ]; then
		printf 'expected [%s], got [%s]\n' "$2" "$1" >&2
		exit 1
	fi
}

# skip_test REASON: ends the test without checking anything.
skip_test() {
	printf 'skipped: %s\n' "$1" >&2
	exit 0
}

failed=0
count=0
for f in "$dir"/*_test.sh; do
	[ -f "$f" ] || continue
	names=$(sed -n 's/^\(only_[a-z0-9_]*\)() {$/\1/p' "$f")
	[ -n "$names" ] || names=$(sed -n 's/^\(test_[a-z0-9_]*\)() {$/\1/p' "$f")
	for t in $names; do
		count=$((count + 1))
		# shellcheck disable=SC1090 # the test files are found at run time
		if ( . "$f" && "$t" ); then
			printf 'ok    %s\n' "$t"
		else
			printf 'FAIL  %s\n' "$t"
			failed=$((failed + 1))
		fi
	done
done
[ "$count" -gt 0 ] || { echo "no tests found"; exit 1; }
[ "$failed" -eq 0 ]
