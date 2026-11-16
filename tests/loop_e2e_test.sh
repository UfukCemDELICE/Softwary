#!/bin/sh
# End to end: an empty repository to two merged slices (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

EVENTS_REL=.softwary/state/events.log

# implement N: what the implementer does for slice S<N> of spec 001: the
# slice in progress, a test that names the criterion, the code, the slice in
# review, one commit on the job branch.
implement() {
	slice=specs/001-login/slices/S$1.md
	fm_set "$REPO/$slice" status in-progress
	mkdir -p "$REPO/tests" "$REPO/src/api"
	printf '# covers AC-001-0%s\n' "$1" >"$REPO/tests/test_login_$1.py"
	printf 'code %s\n' "$1" >"$REPO/src/api/login_$1.py"
	fm_set "$REPO/$slice" status review
	commit_all "implement S$1"
}

# AC-V2-16: product, blueprint and plan approved; two slices (S2 depends on
# S1) go through the loop, one after the other, and merge.
test_ac_v2_16_empty_repo_to_two_merged_slices() {
	setup_repo --no-model
	conf_all true
	conf_set test_paths tests
	add_product
	add_blueprint
	write_adr 0001 accepted "$MODEL_REL"
	sw approve product
	assert_eq "$RC" 0 "approve product"
	sw approve blueprint
	assert_eq "$RC" 0 "approve blueprint"
	add_plan
	rm -r "$REPO/specs/002-tasks"
	for n in 1 2; do
		fm_set "$REPO/specs/001-login/slices/S$n.md" touches "src/api, tests"
	done
	fm_set "$REPO/specs/001-login/spec.md" status draft
	digest=$(git -C "$REPO" hash-object "specs/001-login/spec.md")
	printf -- '---\nspec: 001\ndigest: %s\ndecision: pass\n---\n\n# Analysis of 001\n' "$digest" >"$REPO/specs/001-login/analysis.md"
	sw plan approve 001
	assert_eq "$RC" 0 "plan approve"
	add_eval
	add_origin
	fake_gh
	sw run start
	assert_eq "$RC" 0 "run start"
	for n in 1 2; do
		job=001-S$n
		sw run next
		assert_eq "$(cat "$OUT")" "start $job" "run next before slice $n"
		sw job start $job
		assert_eq "$RC" 0 "job start $job"
		implement $n
		sw job event $job implemented
		assert_eq "$RC" 0 "implemented $job"
		sw job gate $job
		assert_eq "$RC" 0 "gate $job"
		sw job pr $job
		assert_eq "$RC" 0 "pr $job"
		sw job ci $job
		assert_eq "$RC" 0 "ci $job"
		mkdir -p "$REPO/specs/001-login/reviews"
		printf -- '---\nslice: S%s\ndecision: approve\n---\n\n# Review of S%s\n' "$n" "$n" >"$REPO/specs/001-login/reviews/S$n.md"
		sw job review $job
		assert_eq "$RC" 0 "review $job"
		printf -- '---\ndecision: merge\n---\n\nReady.\n' >"$REPO/.softwary/state/jobs/$job/decision.md"
		sw merge $job
		assert_eq "$RC" 0 "merge $job"
		assert_eq "$(git -C "$REPO" branch --show-current)" main "branch after merging $job"
	done
	sw run next
	assert_eq "$(cat "$OUT")" none "run next at the end"
	for n in 1 2; do
		assert_eq "$(git -C "$REPO" show "origin/main:specs/001-login/slices/S$n.md" | sed -n 's/^status: //p')" "done" "S$n on the integration branch"
		assert_eq "$(sed -n 's/^state=//p' "$REPO/.softwary/state/jobs/001-S$n/job")" merged "state of 001-S$n"
	done
	each='start implemented gate_pass pr_opened ci_pass review_approve merged'
	want="approve_product approve_blueprint plan_approve run_start"
	for n in 1 2; do want="$want $each"; done
	assert_eq "$(jq -r .event "$REPO/$EVENTS_REL" | paste -sd' ' -)" "$want" "event sequence"
	assert_eq "$(jq -r 'select(.event == "merged") | .job' "$REPO/$EVENTS_REL" | paste -sd' ' -)" "001-S1 001-S2" "merged jobs"
	sw status
	assert_match "$OUT" "^approval product: approved$"
	assert_match "$OUT" "^job 001-S2 +merged +round 1"
}

run_tests "$0"
