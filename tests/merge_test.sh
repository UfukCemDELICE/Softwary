#!/bin/sh
# Tests for ./softwary merge: the script recomputes every condition itself (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
JOBS_REL=.softwary/state/jobs
EVENTS_REL=.softwary/state/events.log
REVIEW_REL=specs/001-login/reviews/S1.md
SLICE_REL=specs/001-login/slices/S1.md

job_get() {
	sed -n "s/^$1=//p" "$REPO/$JOBS_REL/$JOB/job"
}

last_event() {
	tail -n 1 "$REPO/$EVENTS_REL"
}

# write_decision DECISION: the approver's decision file.
write_decision() {
	printf -- '---\ndecision: %s\n---\n\nLooks right.\n' "$1" >"$REPO/$JOBS_REL/$JOB/decision.md"
}

# merge_repo: a job in `approving` on its pushed branch, with a PR, a green CI,
# an approving review and a decision to merge. The world is then copied, so
# each refusal starts from the same place (see restore).
merge_repo() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_plan
	conf_set test_paths tests
	mkdir -p "$REPO/tests"
	printf '# covers AC-001-01\n' >"$REPO/tests/test_login.py"
	add_origin
	open_run
	fake_gh
	sw job start $JOB
	sw job event $JOB implemented
	sw job gate $JOB
	sw job pr $JOB
	sw job ci $JOB
	mkdir -p "$REPO/specs/001-login/reviews"
	printf -- '---\nslice: S1\ndecision: approve\n---\n\n# Review of S1\n' >"$REPO/$REVIEW_REL"
	sw job review $JOB
	assert_eq "$(job_get state)" approving "state before merge"
	write_decision merge
	: >"$T/gh.log"
	rm -rf "$T/world"
	mkdir "$T/world"
	cp -R "$REPO" "$T/world/repo"
	cp -R "$T/origin.git" "$T/world/origin.git"
	cp -R "$T/gh" "$T/world/gh"
}

# restore: puts the world of merge_repo back.
restore() {
	rm -rf "$REPO" "$T/origin.git" "$T/gh"
	cp -R "$T/world/repo" "$REPO"
	cp -R "$T/world/origin.git" "$T/origin.git"
	cp -R "$T/world/gh" "$T/gh"
	: >"$T/gh.log"
	git -C "$REPO" checkout -q softwary/$JOB
}

# other_push FILE TEXT: someone else pushes FILE with TEXT to origin's main.
other_push() {
	rm -rf "$T/other"
	git clone -q "$T/origin.git" "$T/other"
	git -C "$T/other" config user.name o
	git -C "$T/other" config user.email o@example.com
	mkdir -p "$(dirname "$T/other/$1")"
	printf '%s\n' "$2" >"$T/other/$1"
	git -C "$T/other" add "$1"
	git -C "$T/other" commit -q -m other
	git -C "$T/other" push -q --no-verify origin main >/dev/null 2>&1
}

# refused TEXT: merge refused with TEXT, the job escalated, gh never merged.
refused() {
	sw merge $JOB
	assert_eq "$RC" 1 "exit code: $1"
	assert_eq "$(job_get state)" escalated "state: $1"
	assert_contains "$REPO/$JOBS_REL/$JOB/escalation" "merge refused: $1"
	assert_eq "$(last_event | jq -r .event)" escalate "event: $1"
	! grep -F "pr merge" "$T/gh.log" >/dev/null || fail "gh pr merge was called: $1"
}

# AC-V2-12: all conditions hold: merge bound to the SHA, back on the updated
# integration branch, the slice done there, the job merged.
test_ac_v2_12_merge_happy_path() {
	merge_repo
	sha=$(git -C "$REPO" rev-parse HEAD)
	sw merge $JOB
	assert_eq "$RC" 0 "exit code"
	assert_contains "$T/gh.log" "pr merge 1 --squash --match-head-commit $sha"
	assert_eq "$(git -C "$REPO" branch --show-current)" main "branch"
	assert_eq "$(sed -n 's/^status: //p' "$REPO/$SLICE_REL")" "done" "slice status on main"
	assert_eq "$(job_get state)" merged "state"
	assert_eq "$(last_event | jq -r .event)" merged "event"
	assert_match "$REPO/$JOBS_REL/$JOB/decision.md" "^merged: [0-9a-f]{40}$"
	[ -s "$REPO/$JOBS_REL/$JOB/merge.log" ] || fail "merge.log missing"
}

# AC-V2-12: the job must be approving with a decision to merge; the tree clean.
test_ac_v2_12_merge_preconditions() {
	merge_repo
	rm "$REPO/$JOBS_REL/$JOB/decision.md"
	sw merge $JOB
	assert_eq "$RC" 1 "exit code without a decision"
	write_decision escalate
	sw merge $JOB
	assert_eq "$RC" 1 "exit code with an escalate decision"
	write_decision merge
	touch "$REPO/junk"
	sw merge $JOB
	assert_eq "$RC" 2 "exit code with a dirty tree"
	rm "$REPO/junk"
	sed 's/^state=.*/state=ci/' "$REPO/$JOBS_REL/$JOB/job" >"$T/j" && mv "$T/j" "$REPO/$JOBS_REL/$JOB/job"
	sw merge $JOB
	assert_eq "$RC" 1 "exit code in another state"
	assert_eq "$(job_get state)" ci "state"
	sw merge 009-S9
	assert_eq "$RC" 2 "exit code for an unknown job"
	[ ! -s "$T/gh.log" ] || fail "gh was called"
}

# AC-V2-12: each condition, recomputed by the script, has its own refusal.
test_ac_v2_12_each_refusal() {
	merge_repo
	sed "s/^started=.*/started=$(($(date +%s) - 3000))/" "$REPO/$JOBS_REL/$JOB/job" >"$T/j" && mv "$T/j" "$REPO/$JOBS_REL/$JOB/job"
	refused "budget: max_job_minutes 45"

	restore
	other_push "$SLICE_REL" "conflicting"
	refused "conflict with main"
	[ -z "$(git -C "$REPO" status --porcelain)" ] || fail "the aborted merge left the tree dirty"

	restore
	printf '\n' >>"$REPO/product/PRODUCT.md"
	commit_all "product edited"
	refused "product approval is stale"

	restore
	printf -- '---\nslice: S1\ndecision: changes\n---\n' >"$REPO/$REVIEW_REL"
	commit_all "review changed"
	refused "the slice is not done with an approving review"

	restore
	risk_set 'specs/*' R3
	commit_all "risky"
	refused "risk tier is R3"

	restore
	conf_set test false
	commit_all "red test"
	refused "verify fails"
	[ -s "$REPO/$JOBS_REL/$JOB/merge.log" ] || fail "merge.log missing"

	restore
	echo 0000000000000000000000000000000000000000 >"$T/gh/head"
	refused "PR head is not"

	restore
	echo 1 >"$T/gh/checks"
	refused "CI checks are not green"

	restore
	echo 1 >"$T/gh/merge"
	sw merge $JOB
	assert_eq "$RC" 1 "exit code when gh pr merge fails"
	assert_eq "$(job_get state)" escalated "state"
	assert_contains "$REPO/$JOBS_REL/$JOB/escalation" "merge refused: gh pr merge failed"
	assert_contains "$T/gh.log" "pr merge 1 --squash --match-head-commit"
}

# AC-V2-12: a sync with a moved integration branch makes a new commit; verify,
# the PR head and CI are checked on that commit, and the merge is bound to it.
test_ac_v2_12_sync_creates_new_sha() {
	merge_repo
	old=$(git -C "$REPO" rev-parse HEAD)
	other_push news.txt "news"
	sw merge $JOB
	assert_eq "$RC" 0 "exit code"
	new=$(grep -o -e '--match-head-commit [0-9a-f]*' "$T/gh.log" | cut -d' ' -f2)
	[ -n "$new" ] && [ "$new" != "$old" ] || fail "the merge was not bound to a new commit ($old, $new)"
	assert_eq "$(git --git-dir="$T/origin.git" log -1 --format=%H refs/heads/softwary/$JOB)" "$new" "pushed branch"
	assert_contains "$T/gh.log" "pr checks 1 --watch"
	[ -f "$REPO/news.txt" ] || fail "main does not have the news"
	assert_eq "$(job_get state)" merged "state"
}

run_tests "$0"
