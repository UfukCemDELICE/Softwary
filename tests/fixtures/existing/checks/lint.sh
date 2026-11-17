#!/bin/sh
# Reports every line of the given files (or of app, tests and checks) that
# holds the marker of three capital X. Exit 1 when there is one.
[ $# -gt 0 ] || set -- app tests checks
bad=0
for target in "$@"; do
	if [ -d "$target" ]; then
		files=$(find "$target" -type f -name '*.sh')
	else
		files=$target
	fi
	for f in $files; do
		# the pattern is built so that this file does not report itself
		grep -n "X""XX" "$f" /dev/null && bad=1
	done
done
exit $bad
