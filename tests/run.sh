#!/bin/sh
# Runs every tests/*_test.sh file. Exits 1 if any of them fails.
# Usage: sh tests/run.sh

dir=$(cd "$(dirname "$0")" && pwd -P)
failed=0
total=0
for f in "$dir"/*_test.sh; do
	[ -f "$f" ] || continue
	total=$((total + 1))
	printf '== %s\n' "${f##*/}"
	sh "$f" || failed=$((failed + 1))
done

if [ "$total" -eq 0 ]; then
	printf 'no test files found in %s\n' "$dir"
	exit 1
fi
if [ "$failed" -ne 0 ]; then
	printf '\n%d of %d test files failed\n' "$failed" "$total"
	exit 1
fi
printf '\nall %d test files passed\n' "$total"
