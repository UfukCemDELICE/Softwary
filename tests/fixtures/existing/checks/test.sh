#!/bin/sh
# Runs the test scripts it is given (other files are not tests and are left
# out), or every script of tests/. Prints one line per test; exit 1 when one
# fails.
if [ $# -eq 0 ]; then
	set -- tests/*.sh
else
	given=
	for f in "$@"; do
		case $f in
		tests/*.sh | ./tests/*.sh) given="$given $f" ;;
		esac
	done
	# shellcheck disable=SC2086 # the paths are words
	set -- $given
fi
failed=0
for t in "$@"; do
	[ -f "$t" ] || continue
	if sh "$t" >/dev/null 2>&1; then
		printf 'ok    %s\n' "$t"
	else
		printf 'FAIL  %s\n' "$t"
		failed=1
	fi
done
exit $failed
