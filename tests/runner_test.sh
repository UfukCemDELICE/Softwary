#!/bin/sh
# Tests for tests/run.sh running several test files at a time (V11).
# shellcheck disable=SC2329 # tests are called by run_tests
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# runner: a copy of tests/run.sh in $T/tests, where the tests put their files.
runner() {
	mkdir -p "$T/tests"
	cp "$PKG_ROOT/tests/run.sh" "$T/tests/"
}

# meet NAME OTHER: a test file that marks NAME as started and passes only if
# OTHER starts within 5 seconds, that is, if the two run at the same time.
meet() {
	cat >"$T/tests/$1_test.sh" <<EOF
touch "$T/started-$1"
i=0
while [ \$i -lt 5 ]; do
	[ -e "$T/started-$2" ] && exit 0
	sleep 1
	i=\$((i + 1))
done
exit 1
EOF
}

# run_runner ARGS...: runs the copy with ARGS; RC and OUT.
run_runner() {
	RC=0
	sh "$T/tests/run.sh" "$@" >"$OUT" 2>&1 || RC=$?
}

# AC-V11-01: -j 2 runs two files at the same time; -j 1 runs them one after
# the other.
test_ac_v11_01_files_run_at_the_same_time() {
	runner
	meet a b
	meet b a
	run_runner -j 2
	assert_eq "$RC" 0 "exit code with -j 2"
	assert_contains "$OUT" "all 2 test files passed (2 at a time"
	rm -f "$T"/started-*
	run_runner -j 1
	assert_eq "$RC" 1 "exit code with -j 1 (a cannot meet b)"
	assert_contains "$OUT" "1 of 2 test files failed (1 at a time"
}

# AC-V11-02: every file runs once, a file's output is printed in one piece
# under its header, and the failed files are listed by name.
test_ac_v11_02_output_in_one_piece_and_failures_named() {
	runner
	for n in a b c d; do
		printf 'echo %s-1\nsleep 1\necho %s-2 >&2\necho ran >>"%s/ran-%s"\n' "$n" "$n" "$T" "$n" >"$T/tests/${n}_test.sh"
	done
	printf 'exit 1\n' >>"$T/tests/b_test.sh"
	printf 'exit 1\n' >>"$T/tests/d_test.sh"
	run_runner -j 3
	assert_eq "$RC" 1 "exit code"
	for n in a b c d; do
		assert_eq "$(wc -l <"$T/ran-$n" | tr -d ' ')" 1 "times $n ran"
		assert_eq "$(grep -A2 "^== ${n}_test.sh$" "$OUT" | tail -n 2 | tr '\n' ' ')" "$n-1 $n-2 " "output of $n"
	done
	assert_eq "$(grep '^FAILED' "$OUT" | tr -s ' ' | tr '\n' ' ')" "FAILED b_test.sh FAILED d_test.sh " "failed files"
	assert_contains "$OUT" "2 of 4 test files failed (3 at a time"
}

# AC-V11-03: without -j, as many at a time as the machine has processors, but
# never more than there are files.
test_ac_v11_03_default_is_the_processors() {
	runner
	printf 'exit 0\n' >"$T/tests/a_test.sh"
	printf 'exit 0\n' >"$T/tests/b_test.sh"
	n=$(getconf _NPROCESSORS_ONLN)
	[ "$n" -le 2 ] || n=2
	run_runner
	assert_eq "$RC" 0 "exit code"
	assert_contains "$OUT" "all 2 test files passed ($n at a time"
	run_runner -j 9
	assert_contains "$OUT" "all 2 test files passed (2 at a time"
	run_runner -j3
	assert_contains "$OUT" "all 2 test files passed (2 at a time"
}

# AC-V11-04: a -j that is not a positive whole number, or another argument, is
# refused with the usage line and exit 2, and no file runs.
test_ac_v11_04_bad_arguments_refused() {
	runner
	printf 'touch "%s/ran"\n' "$T" >"$T/tests/a_test.sh"
	for args in "-j 0" "-j x" "-j 02" "-j -1" "-j" "-j=" "--fast" "a_test.sh"; do
		# shellcheck disable=SC2086 # the arguments are split on purpose
		run_runner $args
		assert_eq "$RC" 2 "exit code for: $args"
		assert_contains "$OUT" "usage: sh tests/run.sh [-j N]"
	done
	run_runner -j ""
	assert_eq "$RC" 2 "exit code for an empty -j"
	[ ! -e "$T/ran" ] || fail "a file ran despite a refused argument"
}

# AC-V11-05: stopping the runner (SIGTERM, or Ctrl-C) stops the files it is
# running; they do not go on in the background.
test_ac_v11_05_stopping_stops_the_files() {
	runner
	for n in a b; do
		printf 'touch "%s/started-%s"\nsleep 4\ntouch "%s/done-%s"\n' "$T" "$n" "$T" "$n" >"$T/tests/${n}_test.sh"
	done
	sh "$T/tests/run.sh" -j 2 >"$OUT" 2>&1 &
	pid=$!
	i=0
	until [ -e "$T/started-a" ] && [ -e "$T/started-b" ]; do
		i=$((i + 1))
		[ "$i" -le 10 ] || fail "the files did not start"
		sleep 1
	done
	kill -TERM "$pid"
	RC=0
	wait "$pid" || RC=$?
	assert_eq "$RC" 143 "exit code after SIGTERM"
	sleep 6
	[ ! -e "$T/done-a" ] && [ ! -e "$T/done-b" ] || fail "a file went on after the runner was stopped"
}

# mini_pkg: a package in $T/pkg whose tests/lib.sh is the real one and whose
# install.sh counts its runs in $T/installs before running the real one; the
# tests there (cache_test.sh) use setup_repo. Its lines are indented here
# (<<- removes the tabs) so that run_tests does not take them for tests of
# this file; SW_TEST_ONLY is cleared when it runs.
mini_pkg() {
	mkdir -p "$T/pkg/tests"
	cp "$PKG_ROOT/tests/lib.sh" "$T/pkg/tests/"
	ln -s "$PKG_ROOT/src" "$T/pkg/src"
	ln -s "$PKG_ROOT/tests/fixtures" "$T/pkg/tests/fixtures"
	printf 'echo run >>"%s/installs"\nexec sh "%s/install.sh" "$@"\n' "$T" "$PKG_ROOT" >"$T/pkg/install.sh"
	cat >"$T/pkg/tests/cache_test.sh" <<-'EOF2'
	. "$(dirname "$0")/lib.sh"
	test_a_build() {
		setup_repo
	}
	test_b_dirty() {
		setup_repo
		echo dirty >"$REPO/dirty"
		git -C "$REPO" add dirty
	}
	test_c_clean() {
		setup_repo
		[ ! -e "$REPO/dirty" ] || fail "a test saw what another one wrote"
		! git -C "$REPO" status --porcelain | grep -q dirty || fail "git saw what another test staged"
		[ -x "$REPO/softwary" ] || fail "the copy lost the executable bit"
	}
	test_d_no_sync() {
		setup_repo --no-sync
		[ ! -e "$REPO/CLAUDE.md" ] || fail "--no-sync got the synced setup"
	}
	test_e_spoil() {
		setup_repo
		case ${SPOIL:-} in
		file) mkdir -p "$SW_SETUP_CACHE/111/.softwary/state" && echo x >"$SW_SETUP_CACHE/111/.softwary/state/spoiled" ;;
		git) git -C "$SW_SETUP_CACHE/111" config --local sw.spoiled yes ;;
		esac
	}
	test_f_again() {
		setup_repo
	}
	run_tests "$0"
	EOF2
}

# AC-V11-10: setup_repo builds the setup once per test file and options and
# copies it to the next tests; every test gets its own clean copy.
test_ac_v11_10_setup_is_built_once_per_file() {
	mini_pkg
	RC=0
	SW_TEST_ONLY= sh "$T/pkg/tests/cache_test.sh" >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(wc -l <"$T/installs" | tr -d ' ')" 2 "install.sh runs (default and --no-sync)"
	rm -f "$T/installs"
	RC=0
	SW_TEST_NO_CACHE=1 SW_TEST_ONLY= sh "$T/pkg/tests/cache_test.sh" >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code with SW_TEST_NO_CACHE"
	assert_eq "$(wc -l <"$T/installs" | tr -d ' ')" 6 "install.sh runs with SW_TEST_NO_CACHE"
}

# AC-V11-11: SW_SETUP_CACHE_CHECK=1 fails a test whose copy differs from a
# fresh setup; the cache is removed when the file is done.
test_ac_v11_11_check_catches_a_spoiled_cache() {
	mini_pkg
	mkdir "$T/tmp"
	RC=0
	SW_SETUP_CACHE_CHECK=1 TMPDIR=$T/tmp SW_TEST_ONLY= sh "$T/pkg/tests/cache_test.sh" >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code with an intact cache"
	# a file git ignores (only the file comparison sees it), and a git setting
	# (only the git comparison sees it)
	for spoil in file git; do
		RC=0
		SPOIL=$spoil SW_SETUP_CACHE_CHECK=1 TMPDIR=$T/tmp SW_TEST_ONLY= sh "$T/pkg/tests/cache_test.sh" >"$OUT" 2>&1 || RC=$?
		assert_eq "$RC" 1 "exit code with a spoiled cache ($spoil)"
		assert_contains "$OUT" "FAIL  test_f_again"
		assert_contains "$OUT" "the cached setup differs"
	done
	assert_eq "$(ls -A "$T/tmp")" "" "what is left in TMPDIR"
}

run_tests "$0"
