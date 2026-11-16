#!/bin/sh
# Tests for the merge queue, its drainer and the red integration branch (V4).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log
LOCKS=.softwary/state/locks

job_state() {
	sed -n 's/^state=//p' "$REPO/$JOBS_REL/$1/job"
}

# par_repo [JOBS...]: the parallel plan, a valid evaluation, an origin, an open
# run, a fake gh; each JOB is taken to the approver's decision to merge.
par_repo() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_parallel_plan
	loop_set concurrency 3
	add_eval
	add_origin
	open_run
	fake_gh
	for _j in "$@"; do
		approve_job "$_j"
	done
	: >"$T/gh.log"
}

# hold_merge_lock: the merge lock is held by a live process (sleep).
hold_merge_lock() {
	sleep 60 &
	HOLDER=$!
	mkdir -p "$REPO/$LOCKS/merge"
	printf 'pid=%s host=%s time=%s\n' "$HOLDER" "$(uname -n)" "$(date +%s)" >"$REPO/$LOCKS/merge/owner"
}

release_merge_lock() {
	kill "$HOLDER" 2>/dev/null || :
	rm -rf "${REPO:?}/$LOCKS/merge"
}

merge_calls() {
	grep -c "pr merge" "$T/gh.log" || :
}

# AC-V4-09: with the merge lock free, merge queues the job and drains the
# queue: the job is merged, the queue is empty, the worktree and the local
# branch are gone and the main checkout has the merge.
test_ac_v4_09_merge_enqueues_and_drains() {
	par_repo 001-S1
	sha=$(git -C "$(job_wt 001-S1)" rev-parse HEAD)
	sw merge 001-S1
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^merged: 001-S1 [0-9a-f]{40}$"
	assert_eq "$(job_state 001-S1)" merged "state"
	assert_eq "$(sw_queue_text)" "" "queue"
	[ ! -e "$(job_wt 001-S1)" ] || fail "the worktree is still there"
	! git -C "$REPO" rev-parse -q --verify refs/heads/softwary/001-S1 >/dev/null || fail "the local branch is still there"
	assert_eq "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" main "main checkout"
	[ -f "$REPO/src/a/code_S1.py" ] || fail "the main checkout was not updated"
	assert_eq "$(sed -n 's/^status: //p' "$REPO/specs/001-login/slices/S1.md")" "done" "slice on main"
	assert_contains "$T/gh.log" "pr merge 1 --squash --match-head-commit "
	[ -n "$sha" ] || fail "no sha"
	[ ! -d "$REPO/$LOCKS/merge" ] || fail "the merge lock was not released"
	[ ! -d "$REPO/$LOCKS/state" ] || fail "the state lock was not released"
	assert_eq "$(jq -r 'select(.job == "001-S1") | .event' "$REPO/$EVENTS_REL" | tail -n 3 | paste -sd' ' -)" "review_approve enqueue merged" "events"
}

sw_queue_text() {
	cat "$REPO/.softwary/state/queue" 2>/dev/null | paste -sd' ' -
}

# AC-V4-09: with a live drainer, merge only queues the job: `queued: <job>
# (position n)` and 0; queue drain then merges it.
test_ac_v4_09_merge_waits_for_the_drainer() {
	par_repo 001-S1 001-S2
	hold_merge_lock
	sw merge 001-S1
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(cat "$OUT")" "queued: 001-S1 (position 1)" "output"
	sw merge 001-S2
	assert_eq "$(cat "$OUT")" "queued: 001-S2 (position 2)" "output of the second"
	assert_eq "$(job_state 001-S1)" queued "state"
	assert_eq "$(sw_queue_text)" "001-S1 001-S2" "queue"
	assert_eq "$(merge_calls)" 0 "gh pr merge calls"
	release_merge_lock
	sw queue drain
	assert_eq "$RC" 0 "queue drain"
	assert_match "$OUT" "^merged: 001-S1 [0-9a-f]{40}$"
	assert_match "$OUT" "^merged: 001-S2 [0-9a-f]{40}$"
	assert_eq "$(job_state 001-S2)" merged "state of the second"
	assert_eq "$(sw_queue_text)" "" "queue"
}

# AC-V4-09: a job in the queue whose conditions do not hold goes to the human
# and leaves the queue; the next one is merged; queue drain says 1, and the
# merge of a job that is itself refused says 1.
test_ac_v4_09_refusal_in_queue() {
	par_repo 001-S1 001-S2
	review_job 001-S1 changes
	git -C "$(job_wt 001-S1)" add -A
	git -C "$(job_wt 001-S1)" -c user.name=t -c user.email=t@example.com commit -q --no-verify -m "review changed"
	hold_merge_lock
	sw merge 001-S1
	sw merge 001-S2
	release_merge_lock
	sw queue drain
	assert_eq "$RC" 1 "queue drain with a refusal"
	assert_contains "$OUT" "merge 001-S1: refused: the slice is not done with an approving review"
	assert_match "$OUT" "^merged: 001-S2 [0-9a-f]{40}$"
	assert_eq "$(job_state 001-S1)" escalated "state of the refused job"
	assert_contains "$REPO/$JOBS_REL/001-S1/escalation" "merge refused: the slice is not done with an approving review"
	assert_eq "$(job_state 001-S2)" merged "state of the next job"
	assert_eq "$(sw_queue_text)" "" "queue"
	[ ! -d "$REPO/$LOCKS/merge" ] || fail "the merge lock was not released"
}

test_ac_v4_09_own_refusal_is_1() {
	par_repo 001-S1
	echo 1 >"$T/gh/checks"
	sw merge 001-S1
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "merge 001-S1: refused: CI checks are not green"
	assert_eq "$(job_state 001-S1)" escalated "state"
	assert_eq "$(sw_queue_text)" "" "queue"
}

# AC-V4-09: merge wants an approving job with a decision to merge; queue and
# queue drain print and drain.
test_ac_v4_09_queue_command() {
	par_repo 001-S1
	sw queue
	assert_eq "$RC" 0 "queue"
	assert_eq "$(cat "$OUT")" "queue: empty
drainer: none" "empty queue"
	sw queue drain
	assert_eq "$RC" 0 "queue drain of an empty queue"
	assert_eq "$(cat "$OUT")" "queue: empty" "output"
	sw queue bogus
	assert_eq "$RC" 2 "usage"
	write_decision 001-S1 escalate
	sw merge 001-S1
	assert_eq "$RC" 1 "merge without a decision to merge"
	write_decision 001-S1 merge
	hold_merge_lock
	sw merge 001-S1
	sw queue
	assert_match "$OUT" "^queue: 001-S1$"
	assert_match "$OUT" "^drainer: pid $HOLDER on $(uname -n) since "
	sw queue drain
	assert_eq "$RC" 0 "queue drain with a live drainer"
	assert_eq "$(cat "$OUT")" "queue: draining by pid $HOLDER" "output"
	sw merge 001-S1
	assert_eq "$RC" 1 "merge of a queued job"
	release_merge_lock
	sw merge 009-S9
	assert_eq "$RC" 2 "unknown job"
}

# AC-V4-10: two merges at the same time never run gh pr merge at the same
# time; the second job is synced with the integration branch after the first
# is merged, and the commit it merges has the first one's change.
test_ac_v4_10_merges_never_overlap() {
	par_repo 001-S1 001-S2
	echo 2 >"$T/gh/merge-sleep"
	(cd "$REPO" && ./softwary merge 001-S1 >"$T/m1.out" 2>&1; echo $? >"$T/m1.rc") &
	(cd "$REPO" && ./softwary merge 001-S2 >"$T/m2.out" 2>&1; echo $? >"$T/m2.rc") &
	wait
	assert_eq "$(cat "$T/m1.rc")$(cat "$T/m2.rc")" 00 "exit codes ($(cat "$T/m1.out" "$T/m2.out"))"
	assert_eq "$(awk '{ print $1 }' "$T/gh/merge-log" | paste -sd' ' -)" "start end start end" "gh pr merge calls"
	assert_eq "$(awk '{ print $2 }' "$T/gh/merge-log" | sed -n '1p;3p' | sort | paste -sd' ' -)" "1 2" "both jobs"
	second=$(sed -n '3p' "$T/gh/merge-log" | cut -d' ' -f2)
	first=$((3 - second))
	sha=$(grep -o "pr merge $second --squash --match-head-commit [0-9a-f]*" "$T/gh.log" | awk '{ print $NF }')
	git --git-dir="$T/origin.git" cat-file -e "$sha:src/$(if [ "$first" -eq 1 ]; then echo a/code_S1.py; else echo b/code_S2.py; fi)" ||
		fail "the second commit does not have the first one's change"
	assert_eq "$(job_state 001-S1)$(job_state 001-S2)" mergedmerged "states"
}

# AC-V4-11: a drainer killed after gh pr merge leaves the lock of a dead
# process and the job queued: run next says drain, queue drain goes on from
# where it was, gh pr merge is not called again and the event says so.
test_ac_v4_11_drainer_dies() {
	par_repo 001-S1
	: >"$T/gh/merge-then-die"
	sw merge 001-S1 2>/dev/null
	[ "$RC" -ne 0 ] || fail "the drainer was not killed"
	assert_eq "$(job_state 001-S1)" queued "state after the crash"
	assert_eq "$(cat "$T/gh/state-1")" MERGED "the PR"
	rm "$T/gh/merge-then-die"
	sw run next
	assert_match "$OUT" "^drain$"
	sw queue drain
	assert_eq "$RC" 0 "queue drain"
	assert_match "$OUT" "^merged: 001-S1 [0-9a-f]{40}$"
	assert_eq "$(job_state 001-S1)" merged "state"
	assert_eq "$(merge_calls)" 1 "gh pr merge calls"
	assert_eq "$(jq -r 'select(.event == "merged") | .detail' "$REPO/$EVENTS_REL")" "recovered: PR #1 already merged" "event detail"
	assert_match "$REPO/$EVENTS_REL" '"event":"lock_broken"'
	[ ! -e "$(job_wt 001-S1)" ] || fail "the worktree is still there"
}

# ext_push CMD: somebody else changes origin's main: CMD runs in a clone.
ext_push() {
	rm -rf "$T/ext"
	git clone -q "$T/origin.git" "$T/ext"
	git -C "$T/ext" config user.name o
	git -C "$T/ext" config user.email o@example.com
	(cd "$T/ext" && sh -c "$1") >/dev/null 2>&1
	git -C "$T/ext" push -q --no-verify origin main >/dev/null 2>&1
}

# red_repo: two jobs queued in order; somebody pushes a commit that breaks the
# test command just before the first one is merged. The queue is drained.
red_repo() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	conf_set test "test ! -e BROKEN"
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_parallel_plan
	loop_set concurrency 3
	add_eval
	add_origin
	open_run
	fake_gh
	approve_job 001-S1
	approve_job 001-S2
	cat >"$T/gh/pre-merge" <<HOOK
[ ! -f "$T/ext-done" ] || exit 0
touch "$T/ext-done"
rm -rf "$T/hook"
git clone -q "$T/origin.git" "$T/hook"
cd "$T/hook"
git config user.name o
git config user.email o@example.com
touch BROKEN
git add BROKEN
git commit -q -m "break the tests"
git push -q origin main
HOOK
	hold_merge_lock
	sw merge 001-S1
	sw merge 001-S2
	release_merge_lock
	sw queue drain
}

# AC-V4-12: when the integration branch has the tree that was verified, nothing
# more is checked.
test_ac_v4_12_same_tree_no_verify() {
	par_repo 001-S1
	sw merge 001-S1
	assert_eq "$RC" 0 "exit code"
	[ ! -e "$REPO/.softwary/state/logs/integration.log" ] || fail "the integration branch was verified"
	[ ! -e "$(job_wt _integration)" ] || fail "an integration worktree was made"
	assert_no_match "$REPO/.softwary/state/run" "^halted="
}

# AC-V4-12: a merge that leaves the integration branch red (somebody else's
# commit came in before it) is reverted by a PR, the run is halted, the rest
# of the queue stays queued, run next says stop, job start and merge refuse.
test_ac_v4_12_red_integration() {
	red_repo
	assert_eq "$RC" 0 "queue drain"
	assert_contains "$OUT" "merged: 001-S1 "
	assert_contains "$OUT" "is red after 001-S1; the run is halted (integration red after 001-S1 (revert PR #3))"
	assert_eq "$(job_state 001-S1)" merged "state of the merged job"
	assert_eq "$(job_state 001-S2)" queued "state of the next job"
	assert_eq "$(sw_queue_text)" 001-S2 "queue"
	assert_eq "$(sed -n 's/^halted=//p' "$REPO/.softwary/state/run")" "integration red after 001-S1 (revert PR #3)" "halted"
	assert_match "$REPO/$EVENTS_REL" '"event":"integration_red"'
	git --git-dir="$T/origin.git" rev-parse -q --verify refs/heads/softwary/revert-001-S1 >/dev/null || fail "no revert branch"
	assert_eq "$(cat "$T/gh/base-3")" main "base of the revert PR"
	assert_eq "$(cat "$T/gh/branch-3")" softwary/revert-001-S1 "head of the revert PR"
	[ -s "$REPO/.softwary/state/logs/integration.log" ] || fail "no integration log"
	[ ! -d "$REPO/$LOCKS/merge" ] || fail "the merge lock was not released"
	assert_eq "$(merge_calls)" 1 "gh pr merge calls"
	sw run next
	assert_eq "$RC" 1 "run next"
	assert_eq "$(cat "$OUT")" "stop: integration red after 001-S1 (revert PR #3)" "run next output"
	sw job start 001-S3
	assert_eq "$RC" 1 "job start"
	assert_contains "$OUT" "run is halted: integration red after 001-S1"
	sw queue drain
	assert_eq "$RC" 1 "queue drain"
	assert_contains "$OUT" "queue: run is halted: integration red after 001-S1"
	assert_eq "$(merge_calls)" 1 "gh pr merge calls after the drain"
}

# AC-V4-12: run start on a halted run checks the tip of the integration branch
# again: red, it says so (1); green, the halt is lifted and the run goes on.
test_ac_v4_12_run_start_clears_halt() {
	red_repo
	sw run start
	assert_eq "$RC" 1 "run start while red"
	assert_contains "$OUT" "run start: integration is still red (see .softwary/state/logs/integration.log)"
	assert_match "$REPO/.softwary/state/run" "^halted="
	ext_push "git rm -q BROKEN && git commit -q -m fix"
	sw run start
	assert_eq "$RC" 0 "run start after the fix"
	assert_match "$OUT" "^run: resuming \(started "
	assert_no_match "$REPO/.softwary/state/run" "^halted="
	assert_match "$REPO/$EVENTS_REL" '"event":"integration_green"'
	sw run next
	assert_eq "$RC" 0 "run next"
	assert_match "$OUT" "^drain$"
	sw queue drain
	assert_eq "$RC" 0 "queue drain"
	assert_eq "$(job_state 001-S2)" merged "the job that waited"
}

run_tests "$0"
