#!/bin/sh
# End to end: three slices with concurrency 3 (V4).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOBS_REL=.softwary/state/jobs

job_state() {
	sed -n 's/^state=//p' "$REPO/$JOBS_REL/$1/job"
}

# AC-V4-15: S1 and S2 cross nothing and run together, both reaching `approving`
# before either is merged; S3 crosses S1 and starts only when S1 is merged; in
# the end all three are merged, the queue is empty, the worktrees are gone and
# run next says none.
test_ac_v4_15_three_slices_parallel() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	add_product
	add_blueprint
	write_adr 0001 accepted "$MODEL_REL"
	sw approve product
	sw approve blueprint
	add_parallel_plan
	fm_set "$REPO/specs/001-login/spec.md" status draft
	digest=$(git -C "$REPO" hash-object "specs/001-login/spec.md")
	printf -- '---\nspec: 001\ndigest: %s\ndecision: pass\n---\n\n# Analysis of 001\n' "$digest" >"$REPO/specs/001-login/analysis.md"
	sw plan approve 001
	assert_eq "$RC" 0 "plan approve"
	loop_set concurrency 3
	add_eval
	add_origin
	fake_gh
	sw run start
	assert_eq "$RC" 0 "run start"

	sw run next
	assert_eq "$(cat "$OUT")" "start 001-S1
start 001-S2" "run next: two slices that cross nothing"
	approve_job 001-S1
	approve_job 001-S2
	assert_eq "$(job_state 001-S1)/$(job_state 001-S2)" "approving/approving" "both reach approving before either merges"
	sw job start 001-S3
	assert_eq "$RC" 1 "S3 crosses S1"
	assert_contains "$OUT" "touches overlap with 001-S1"
	sw run next
	assert_eq "$(cat "$OUT")" "resume 001-S1 approving
resume 001-S2 approving" "run next while S1 and S2 wait for the approver"

	sw merge 001-S1
	assert_eq "$RC" 0 "merge S1"
	sw run next
	assert_eq "$(cat "$OUT")" "resume 001-S2 approving
start 001-S3" "S3 can start once S1 is merged"
	approve_job 001-S3
	sw merge 001-S2
	assert_eq "$RC" 0 "merge S2"
	sw merge 001-S3
	assert_eq "$RC" 0 "merge S3"

	for j in 001-S1 001-S2 001-S3; do
		assert_eq "$(job_state $j)" merged "state of $j"
	done
	assert_eq "$(cat "$REPO/.softwary/state/queue")" "" "queue"
	assert_eq "$(git -C "$REPO" worktree list | grep -c .)" 1 "worktrees"
	assert_eq "$(find "$REPO/.softwary/worktrees" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" 0 "worktree directories"
	assert_eq "$(git -C "$REPO" branch --list 'softwary/*' | wc -l | tr -d ' ')" 0 "job branches"
	assert_eq "$(git -C "$REPO" status --porcelain)" "" "main checkout"
	sw run next
	assert_eq "$(cat "$OUT")" none "run next at the end"
	for n in 1 2 3; do
		assert_eq "$(git -C "$REPO" show "origin/main:specs/001-login/slices/S$n.md" | sed -n 's/^status: //p')" "done" "S$n on the integration branch"
	done
	assert_eq "$(jq -r 'select(.event == "merged") | .job' "$REPO/.softwary/state/events.log" | paste -sd' ' -)" "001-S1 001-S2 001-S3" "merge order"
	sw queue
	assert_eq "$(cat "$OUT")" "queue: empty
drainer: none" "queue"
}

run_tests "$0"
