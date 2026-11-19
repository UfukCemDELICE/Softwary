#!/bin/sh
# Runs every tests/*_test.sh file, several at a time. Exits 1 if any of them
# fails.
# Usage: sh tests/run.sh [-j N]
#   -j N  run N files at once. Without -j, as many as the machine has
#         processors; -j 1 runs them one after another with live output.
# With more than one at a time, a file's output is printed in one piece when
# the file is done, so the files come in the order they finish. The failed
# files are listed by name at the end.

dir=$(cd "$(dirname "$0")" && pwd -P)

usage() {
	printf 'usage: sh tests/run.sh [-j N]   (N: a positive whole number)\n' >&2
	exit 2
}

jobs=
given=
while [ $# -gt 0 ]; do
	case $1 in
	-j)
		[ $# -ge 2 ] || usage
		jobs=$2
		given=1
		shift 2
		;;
	-j*)
		jobs=${1#-j}
		given=1
		shift
		;;
	*) usage ;;
	esac
done
if [ -n "$given" ]; then
	case $jobs in '' | *[!0-9]* | 0*) usage ;; esac
else
	jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || jobs=1
	case $jobs in '' | *[!0-9]* | 0*) jobs=1 ;; esac
fi

set --
for f in "$dir"/*_test.sh; do
	[ -f "$f" ] && set -- "$@" "$f"
done
total=$#
if [ "$total" -eq 0 ]; then
	printf 'no test files found in %s\n' "$dir"
	exit 1
fi
[ "$jobs" -le "$total" ] || jobs=$total

work=$(mktemp -d "${TMPDIR:-/tmp}/softwary-run.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
start=$(date +%s)

# worker FILE...: takes each file no other worker has taken (mkdir either
# creates the directory or fails, for exactly one taker), runs it with its
# output in a file, and prints that output under a lock so that the outputs of
# two files are never mixed. A worker runs in the background, where the shell
# ignores Ctrl-C (SIGINT), so the main shell stops it with SIGTERM, and it
# stops the file it is running.
worker() {
	_c=
	trap '[ -z "$_c" ] || kill "$_c" 2>/dev/null; exit 143' TERM
	for _f in "$@"; do
		_n=${_f##*/}
		mkdir "$work/take.$_n" 2>/dev/null || continue
		sh "$_f" >"$work/out.$_n" 2>&1 &
		_c=$!
		wait "$_c" || : >"$work/failed.$_n"
		_c=
		until mkdir "$work/print" 2>/dev/null; do sleep 1; done
		printf '== %s\n' "$_n"
		cat "$work/out.$_n"
		rmdir "$work/print"
	done
}

if [ "$jobs" -eq 1 ]; then
	for f in "$@"; do
		printf '== %s\n' "${f##*/}"
		sh "$f" || : >"$work/failed.${f##*/}"
	done
else
	pids=
	trap 'kill $pids 2>/dev/null; exit 130' INT
	trap 'kill $pids 2>/dev/null; exit 143' TERM
	i=0
	while [ "$i" -lt "$jobs" ]; do
		worker "$@" &
		pids="$pids $!"
		i=$((i + 1))
	done
	wait
fi

failed=0
for f in "$@"; do
	[ -e "$work/failed.${f##*/}" ] || continue
	[ "$failed" -gt 0 ] || printf '\n'
	printf 'FAILED  %s\n' "${f##*/}"
	failed=$((failed + 1))
done
took=$(($(date +%s) - start))
if [ "$failed" -ne 0 ]; then
	printf '\n%d of %d test files failed (%d at a time, %ds)\n' "$failed" "$total" "$jobs" "$took"
	exit 1
fi
printf '\nall %d test files passed (%d at a time, %ds)\n' "$total" "$jobs" "$took"
