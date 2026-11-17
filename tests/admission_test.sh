#!/bin/sh
# Tests for the admission of a job: concurrency, touches and loop.conf (V4).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOBS_REL=.softwary/state/jobs

# par_repo [CONCURRENCY]: the parallel plan, an origin, an open run.
par_repo() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	approve_blueprint
	add_parallel_plan
	loop_set concurrency "${1:-3}"
	add_origin
	open_run
	fake_gh
}

# refused JOB TEXT: job start is refused (1) with TEXT and leaves no trace.
refused() {
	sw job start "$1"
	assert_eq "$RC" 1 "exit code: $2"
	assert_contains "$OUT" "$2"
	[ ! -e "$REPO/$JOBS_REL/$1" ] || fail "a job record was made despite: $2"
	[ ! -e "$(job_wt "$1")" ] || fail "a worktree was made despite: $2"
	! git -C "$REPO" rev-parse -q --verify "refs/heads/softwary/$1" >/dev/null || fail "a branch was made despite: $2"
}

# AC-V4-05: no more jobs than `concurrency` that are not final or escalated
# (a job in `ready` or `queued` counts); the refusal names them.
test_ac_v4_05_concurrency_limit() {
	par_repo 2
	sw job start 001-S1
	assert_eq "$RC" 0 "first job"
	sw job start 001-S2
	assert_eq "$RC" 0 "second job"
	refused 001-S3 "job 001-S3: concurrency limit 2 reached (001-S1 001-S2)"
	sw job escalate 001-S1 "a question"
	sw job start 001-S3
	assert_eq "$RC" 1 "an escalated job leaves room but keeps its paths"
	assert_contains "$OUT" "touches overlap with 001-S1"
	loop_set concurrency 1
	refused 001-S3 "concurrency limit 1 reached (001-S2)"
}

# AC-V4-05: a slice whose touches cross those of a job that is not final
# (an escalated one too) does not start; the refusal names the job and the
# two entries. Once the other job is final it starts.
test_ac_v4_05_touches_overlap() {
	par_repo
	sw job start 001-S1
	assert_eq "$RC" 0 "first job"
	refused 001-S3 "job 001-S3: touches overlap with 001-S1 (src/a/deep ~ src/a)"
	sw job start 001-S2
	assert_eq "$RC" 0 "a slice that crosses nothing"
	sw job escalate 001-S1 "a question"
	refused 001-S3 "touches overlap with 001-S1"
	sw job abandon 001-S1 "given up"
	sw job start 001-S3
	assert_eq "$RC" 0 "after the other job is final"
}

# AC-V4-05: the rule for two entries: equal paths, a directory above a path
# (the trailing slash does not matter), globs by their text up to the first
# glob character.
test_ac_v4_05_touches_rule() {
	for pair in "src/a|src/a|y" "src/a|src/a/x.py|y" "src/a/|src/a|y" "src/ab|src/a|n" "src/a/x.py|src/a/y.py|n" \
		"src/*.py|src/x.py|y" "src/*.py|lib/x.py|n" "*.md|docs/x.md|y" "tests/|tests/a_test.sh|y" "src/a*|src/ab/x|y" "./src/a|src/a/b|y"; do
		a=${pair%%|*}
		rest=${pair#*|}
		b=${rest%%|*}
		want=${rest#*|}
		got=n
		sh -c '. "$1/src/lib/admit.sh"; sw_admit_cross "$2" "$3"' sh "$PKG_ROOT" "$a" "$b" && got=y
		assert_eq "$got" "$want" "does $a cross $b"
	done
}

# AC-V4-05: of two job starts at the same time for slices that cross, exactly
# one opens its job.
test_ac_v4_05_parallel_start_one_wins() {
	par_repo
	i=0
	while [ "$i" -lt 3 ]; do
		rm -rf "${REPO:?}/$JOBS_REL" "${REPO:?}/.softwary/worktrees"
		git -C "$REPO" worktree prune
		git -C "$REPO" branch -D softwary/001-S1 softwary/001-S3 >/dev/null 2>&1
		(cd "$REPO" && ./softwary job start 001-S1 >"$T/a.out" 2>&1; echo $? >"$T/a.rc") &
		(cd "$REPO" && ./softwary job start 001-S3 >"$T/b.out" 2>&1; echo $? >"$T/b.rc") &
		wait
		ok=0
		[ "$(cat "$T/a.rc")" -ne 0 ] || ok=$((ok + 1))
		[ "$(cat "$T/b.rc")" -ne 0 ] || ok=$((ok + 1))
		assert_eq "$ok" 1 "jobs opened in round $i (a: $(cat "$T/a.rc"), b: $(cat "$T/b.rc"))"
		assert_eq "$(find "$REPO/$JOBS_REL" -name job | wc -l | tr -d ' ')" 1 "job records"
		i=$((i + 1))
	done
}

# AC-V4-07: concurrency is 1, 2 or 3; anything else is a doctor line with its
# line number, and run start stops with 2. The installed template says 3.
test_ac_v4_07_concurrency_range() {
	setup_repo
	conf_all true
	grep -q '^concurrency = 3$' "$PKG_ROOT/src/templates/loop.conf" || fail "the template does not say 3"
	for v in 1 2 3; do
		loop_set concurrency $v
		sw doctor
		assert_eq "$RC" 0 "doctor with concurrency $v"
	done
	for v in 0 4 03 x -1; do
		loop_set concurrency $v
		sw doctor
		assert_eq "$RC" 2 "doctor with concurrency $v"
		assert_match "$OUT" "^loop\\.conf +FAIL \\(\\.softwary/config/loop\\.conf:4: concurrency must be 1, 2 or 3\\)$"
		sw run start
		assert_eq "$RC" 2 "run start with concurrency $v"
		assert_contains "$OUT" "loop.conf:4: concurrency must be 1, 2 or 3"
	done
}

run_tests "$0"
