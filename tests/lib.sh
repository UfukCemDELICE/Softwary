# shellcheck shell=sh
# shellcheck disable=SC2034 # T, OUT, RC, REPO are read by the *_test.sh files
# Shared helpers for softwary tests. Sourced by every *_test.sh file.
#
# Each test is a function named test_<something>() and runs in its own
# subshell with a fresh temporary directory $T. $OUT holds the captured
# output of the last `sw` call and $RC its exit code.

PKG_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
REQUIRED_KEYS="format_check lint typecheck test build security"
T=
OUT=
RC=
REPO=

fail() {
	printf '    assertion failed: %s\n' "$*"
	if [ -n "$OUT" ] && [ -f "$OUT" ]; then
		printf '    --- last output ---\n'
		sed 's/^/    | /' "$OUT"
	fi
	exit 1
}

assert_eq() {
	[ "$1" = "$2" ] || fail "${3:-value}: expected [$2], got [$1]"
}

# assert_match FILE ERE
assert_match() {
	grep -E -e "$2" "$1" >/dev/null || fail "no line matches /$2/ in ${1##*/}"
}

# assert_no_match FILE ERE
assert_no_match() {
	! grep -E -e "$2" "$1" >/dev/null || fail "unexpected line matches /$2/ in ${1##*/}"
}

# assert_contains FILE TEXT
assert_contains() {
	grep -F -e "$2" "$1" >/dev/null || fail "${1##*/} does not contain [$2]"
}

# setup_repo [--no-git] [--no-sync]: creates $T/repo, initialises git and
# installs softwary. Unless --no-sync is given, every tool is set to off and
# ./softwary sync runs, so the repo starts in a synced state.
setup_repo() {
	_git=1
	_sync=1
	for _a in "$@"; do
		case $_a in
		--no-git) _git=0 ;;
		--no-sync) _sync=0 ;;
		*) fail "setup_repo: unknown option $_a" ;;
		esac
	done
	REPO=$T/repo
	mkdir -p "$REPO"
	if [ "$_git" -eq 1 ]; then
		git -C "$REPO" init -q || fail "git init failed"
	fi
	sh "$PKG_ROOT/install.sh" "$REPO" >"$T/install.out" 2>&1 || fail "install.sh failed: $(cat "$T/install.out")"
	if [ "$_sync" -eq 1 ]; then
		tools_all off
		(cd "$REPO" && ./softwary sync) >"$T/sync.out" 2>&1 || fail "sync failed: $(cat "$T/sync.out")"
	fi
}

# write_conf: replaces the repo's commands.conf with stdin.
write_conf() {
	cat >"$REPO/.softwary/config/commands.conf"
}

# conf_all VALUE: every required key gets VALUE ("%k" is replaced by the key).
conf_all() {
	for _k in $REQUIRED_KEYS; do
		printf '%s = %s\n' "$_k" "$(printf '%s' "$1" | sed "s/%k/$_k/g")"
	done | write_conf
}

# file_set FILE KEY VALUE: replaces KEY's line in FILE, or appends it.
file_set() {
	awk -v k="$2" -v v="$3" '
		$1 == k && $2 == "=" { print k " = " v; done = 1; next }
		{ print }
		END { if (!done) print k " = " v }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

# conf_set KEY VALUE: sets KEY in commands.conf.
conf_set() {
	file_set "$REPO/.softwary/config/commands.conf" "$1" "$2"
}

# conf_del KEY: removes KEY's line from commands.conf.
conf_del() {
	_c=$REPO/.softwary/config/commands.conf
	awk -v k="$1" '!($1 == k && $2 == "=")' "$_c" >"$_c.tmp" && mv "$_c.tmp" "$_c"
}

TOOLS="claude-code codex cursor"

# tools_set TOOL VALUE: sets TOOL in tools.conf.
tools_set() {
	file_set "$REPO/.softwary/config/tools.conf" "$1" "$2"
}

# tools_all VALUE: sets every tool to VALUE.
tools_all() {
	for _t in $TOOLS; do
		tools_set "$_t" "$1"
	done
}

# add_sources: copies the sample skills and agents into the repo's .softwary/.
add_sources() {
	cp -R "$PKG_ROOT/tests/fixtures/sources/skills" "$PKG_ROOT/tests/fixtures/sources/agents" "$REPO/.softwary/"
}

# snapshot: prints "cksum size path" for every file in the repo except .git.
snapshot() {
	(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sort | while IFS= read -r _f; do
		printf '%s %s\n' "$(cksum <"$_f")" "$_f"
	done)
}

# changed_paths BEFORE AFTER: paths whose snapshot lines differ.
changed_paths() {
	diff "$1" "$2" | sed -n 's/^[<>] [0-9]* [0-9]* \.\///p' | sort -u
}

# block_of FILE: prints the lines between the softwary markers.
block_of() {
	awk '/^<!-- softwary:end -->$/ { on = 0 } on { print } /^<!-- softwary:begin/ { on = 1 }' "$1"
}

# outside_block FILE: prints the lines outside the softwary block.
outside_block() {
	awk '/^<!-- softwary:begin/ { on = 1 } !on { print } /^<!-- softwary:end -->$/ { on = 0 }' "$1"
}

# sw ARGS...: runs ./softwary ARGS in the repo, capturing output and exit code.
sw() {
	RC=0
	(cd "$REPO" && ./softwary "$@") >"$OUT" 2>&1 || RC=$?
}

# path_without TOOL: prints a directory usable as PATH that has every
# executable from the current PATH except TOOL.
path_without() {
	_d=$T/path-without-$1
	mkdir -p "$_d"
	_old_ifs=$IFS
	IFS=:
	# shellcheck disable=SC2086 # split PATH on ':' on purpose
	set -- "$1" $PATH
	IFS=$_old_ifs
	_tool=$1
	shift
	for _p in "$@"; do
		[ -d "$_p" ] || continue
		for _f in "$_p"/*; do
			_n=${_f##*/}
			[ "$_n" = "$_tool" ] && continue
			[ -x "$_f" ] && [ ! -e "$_d/$_n" ] && ln -s "$_f" "$_d/$_n"
		done
	done
	printf '%s\n' "$_d"
}

# run_tests FILE: runs every test_* function defined in FILE.
run_tests() {
	_failed=0
	_count=0
	# shellcheck disable=SC2013 # test function names contain no whitespace
	for _t in $(sed -n 's/^\(test_[a-z0-9_]*\)() {$/\1/p' "$1"); do
		_count=$((_count + 1))
		T=$(mktemp -d "${TMPDIR:-/tmp}/softwary-test.XXXXXX") || exit 1
		OUT=$T/out
		if ("$_t"); then
			printf 'ok    %s\n' "$_t"
		else
			printf 'FAIL  %s\n' "$_t"
			_failed=$((_failed + 1))
		fi
		rm -rf "$T"
	done
	[ "$_count" -gt 0 ] || { printf 'no tests found in %s\n' "$1"; return 1; }
	[ "$_failed" -eq 0 ]
}
