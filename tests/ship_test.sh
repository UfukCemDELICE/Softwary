#!/bin/sh
# Tests for ./softwary ship prepare|check|pr (V7).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

RELEASES_REL=.softwary/state/releases
FAR=2999-12-31

# ship_base: a repository whose integration branch, main, has code that its
# model owns and a test; nothing is committed yet.
ship_base() {
	setup_repo --no-model
	conf_all true
	conf_set test_paths tests
	rm -f "$REPO/src/.gitkeep"
	mkdir -p "$REPO/src" "$REPO/tests"
	printf 'one\n' >"$REPO/src/app.sh"
	printf 't\n' >"$REPO/tests/t.sh"
	core_model '["src/*"]' active
}

# ship_repo: main has three commits and master, the production branch, stands
# at the first one; the drift of the repository is clean.
ship_repo() {
	ship_base
	commit_all "first"
	add_production
	printf 'two\n' >>"$REPO/src/app.sh"
	commit_all "second"
	printf 'three\n' >>"$REPO/src/app.sh"
	commit_all "third"
}

# add_spec NNN STATUS K=STATUS...: a spec with one slice and one criterion for
# each K; a slice that is done has its approving review and a test that names
# its criterion.
add_spec() {
	_n=$1
	_st=$2
	shift 2
	_d=$REPO/specs/$_n-feat$_n
	mkdir -p "$_d/slices" "$_d/reviews"
	{
		printf -- '---\nid: %s\ntitle: Feature %s\nstatus: %s\nrisk: R1\nmodel: core\ncontracts:\n---\n\n# Feature %s\n\n## Acceptance criteria\n\n' "$_n" "$_n" "$_st" "$_n"
		for _s in "$@"; do printf -- '- **AC-%s-0%s:** Behaviour %s.\n' "$_n" "${_s%%=*}" "${_s%%=*}"; done
	} >"$_d/spec.md"
	for _s in "$@"; do
		_k=${_s%%=*}
		printf -- '---\nid: S%s\nspec: %s\ngoal: Goal %s\nacs: AC-%s-0%s\ndepends_on:\ntouches: src\nstatus: %s\n---\n\n# S%s\n' \
			"$_k" "$_n" "$_k" "$_n" "$_k" "${_s#*=}" "$_k" >"$_d/slices/S$_k.md"
		if [ "${_s#*=}" = "done" ]; then
			printf -- '---\nslice: S%s\ndecision: approve\n---\n\n# Review of S%s\n' "$_k" "$_k" >"$_d/reviews/S$_k.md"
			printf '# covers AC-%s-0%s\n' "$_n" "$_k" >"$REPO/tests/test_${_n}_$_k.sh"
		fi
	done
}

# tip7: the short sha of the integration branch's tip, as the note's file name.
tip7() {
	git -C "$REPO" rev-parse --short=7 "${1:-main}"
}

note_of() {
	printf '%s/%s/%s.md' "$REPO" "$RELEASES_REL" "$(tip7 "${1:-main}")"
}

# no_note: no release note was written.
no_note() {
	[ -z "$(ls "$REPO/$RELEASES_REL" 2>/dev/null)" ] || fail "a release note was written: $(ls "$REPO/$RELEASES_REL")"
}

# fill_note FILE: puts a sentence in each of the three written sections.
fill_note() {
	sed 's/^UNSET$/Written by the human./' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

# AC-V7-01: both branches must be set, and the reason is named; exit 2 and no note.
test_ac_v7_01_branches_must_be_set() {
	ship_repo
	conf_set integration_branch UNSET
	sw ship prepare
	assert_eq "$RC" 2 "exit code without integration_branch"
	assert_contains "$OUT" "ship: integration_branch is not set in .softwary/config/commands.conf"
	conf_set integration_branch main
	conf_set production_branch UNSET
	sw ship prepare
	assert_eq "$RC" 2 "exit code without production_branch"
	assert_contains "$OUT" "ship: production_branch is not set in .softwary/config/commands.conf"
	conf_del production_branch
	sw ship prepare
	assert_eq "$RC" 2 "exit code with production_branch absent"
	no_note
}

# AC-V7-01: the production branch must exist, locally or on origin.
test_ac_v7_01_production_must_exist() {
	ship_repo
	git -C "$REPO" branch -D master >/dev/null
	sw ship prepare
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "ship: the production branch 'master' is not there (locally or on origin)"
	no_note
	conf_set production_branch nowhere
	sw ship prepare
	assert_eq "$RC" 2 "exit code for a branch that never was"
	assert_contains "$OUT" "'nowhere'"
}

# AC-V7-01: a production branch that has a commit the integration branch does
# not have is refused: the human brings it in first.
test_ac_v7_01_production_must_be_an_ancestor() {
	ship_repo
	git -C "$REPO" checkout -q master
	printf 'hotfix\n' >"$REPO/hotfix.txt"
	commit_all "a fix made on master"
	git -C "$REPO" checkout -q main
	sw ship prepare
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "ship: master has commits that main does not have; bring them into main first"
	no_note
}

# AC-V7-01: with nothing ahead of production there is nothing to ship.
test_ac_v7_01_nothing_to_ship() {
	ship_repo
	git -C "$REPO" branch -f master main
	sw ship prepare
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "ship: nothing to ship"
	no_note
}

# AC-V7-01: the tip of the integration branch goes through the gate of the
# project: red, nothing is written.
test_ac_v7_01_red_integration_is_refused() {
	ship_repo
	conf_set test false
	commit_all "red"
	sw ship prepare
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "ship: the tip of main does not pass the gate (see .softwary/state/logs/integration.log)"
	assert_match "$REPO/.softwary/state/logs/integration.log" "^test +FAIL"
	no_note
}

# AC-V7-01: an undecided drift item stops ship, a decision lets it through.
test_ac_v7_01_drift_must_be_decided() {
	ship_repo
	conf_set src_paths "src lib"
	mkdir -p "$REPO/lib"
	printf 'x\n' >"$REPO/lib/x.sh"
	commit_all "a file no component owns"
	sw ship prepare
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "ship: drift has undecided or expired items (./softwary drift)"
	no_note
	printf '| Item | Decision | Until | Reason |\n| --- | --- | --- | --- |\n| uncovered lib/x.sh | accept | 2000-01-01 | was fine |\n' >"$REPO/architecture/drift.md"
	commit_all "an expired decision"
	sw ship prepare
	assert_eq "$RC" 1 "exit code with an expired decision"
	no_note
	sed 's/2000-01-01/2999-12-31/' "$REPO/architecture/drift.md" >"$T/d" && cp "$T/d" "$REPO/architecture/drift.md"
	commit_all "decided"
	sw ship prepare
	assert_eq "$RC" 0 "exit code with a decision"
	[ -f "$(note_of)" ] || fail "no note"
}

# AC-V7-01: what the working tree holds does not matter: the tip is what is
# checked, and an uncommitted drift decision is not one.
test_ac_v7_01_the_tip_is_what_counts() {
	ship_repo
	conf_set src_paths "src lib"
	mkdir -p "$REPO/lib"
	printf 'x\n' >"$REPO/lib/x.sh"
	commit_all "a file no component owns"
	printf '| Item | Decision | Until | Reason |\n| --- | --- | --- | --- |\n| uncovered lib/x.sh | accept | %s | decided here |\n' "$FAR" >"$REPO/architecture/drift.md"
	sw ship prepare
	assert_eq "$RC" 1 "exit code with an uncommitted decision"
	no_note
}

# AC-V7-01: the branches are read from origin when it has them, after a fetch:
# what someone pushed is the tip, and a local commit that is not pushed is not.
test_ac_v7_01_origin_tips_after_a_fetch() {
	ship_repo
	add_origin
	add_production
	git -C "$REPO" branch -D master >/dev/null
	printf 'local\n' >>"$REPO/src/app.sh"
	commit_all "a commit that is not pushed"
	git clone -q "$T/origin.git" "$T/other" || fail "clone failed"
	printf 'there\n' >"$T/other/src/other.sh"
	git -C "$T/other" add -A
	git -C "$T/other" -c user.name=t -c user.email=t@example.com commit -q --no-verify -m "pushed by someone else"
	git -C "$T/other" push -q --no-verify origin main
	sw ship prepare
	assert_eq "$RC" 0 "exit code"
	pushed=$(git -C "$T/other" rev-parse --short=7 HEAD)
	[ -f "$REPO/$RELEASES_REL/$pushed.md" ] || fail "the note is not for what was pushed: $(ls "$REPO/$RELEASES_REL")"
	assert_contains "$REPO/$RELEASES_REL/$pushed.md" "integration: $(git -C "$T/other" rev-parse HEAD)"
	assert_contains "$REPO/$RELEASES_REL/$pushed.md" "production: $(git -C "$REPO" rev-parse origin/master)"
}

# AC-V7-02: the note is under releases/ and named for the tip; its path is
# printed; it is headed, carries the two ends and has the nine sections in order.
test_ac_v7_02_note_layout() {
	ship_repo
	sw ship prepare
	assert_eq "$RC" 0 "exit code"
	rel=$RELEASES_REL/$(tip7).md
	assert_contains "$OUT" "$rel"
	f=$REPO/$rel
	assert_eq "$(head -n 1 "$f")" "# Release $(tip7)" "title"
	assert_contains "$f" "production: $(git -C "$REPO" rev-parse master)"
	assert_contains "$f" "integration: $(git -C "$REPO" rev-parse main)"
	assert_eq "$(grep '^## ' "$f" | paste -sd, -)" "## Range,## Specs,## Decisions,## Risk,## Waivers and findings,## Drift,## Observability,## Rollout,## Rollback" "sections"
	assert_match "$f" "^- production: master $(tip7 master)$"
	assert_match "$f" "^- integration: main $(tip7)$"
	assert_match "$f" "^- commits: 2$"
	assert_eq "$(grep -c '^UNSET$' "$f")" 3 "UNSET lines (the three written sections)"
	[ -z "$(git -C "$REPO" status --porcelain)" ] || fail "ship prepare left the working tree dirty: $(git -C "$REPO" status --porcelain)"
}

# AC-V7-02: the computed sections: the slices that are done in the range with
# their specs, the decisions added or changed, the highest risk and the R3
# paths, the waivers and the decisions about drift.
test_ac_v7_02_computed_sections() {
	ship_base
	add_spec 001 "done" "1=done"
	write_adr 0002 accepted architecture/model/system.calm.json
	write_adr 0003 proposed architecture/model/system.calm.json
	commit_all "first"
	add_production
	add_spec 002 approved 1=done 2=done 3=planned
	write_adr 0001 accepted architecture/model/system.calm.json
	write_adr 0003 accepted architecture/model/system.calm.json
	write_adr 0004 proposed architecture/model/system.calm.json
	risk_set 'src/pay/*' R3
	mkdir -p "$REPO/src/pay" "$REPO/lib"
	printf 'pay\n' >"$REPO/src/pay/charge.sh"
	printf 'x\n' >"$REPO/lib/x.sh"
	conf_set src_paths "src lib"
	printf 'lint = %s: legacy lint debt\n' "$FAR" >"$REPO/.softwary/config/waivers.conf"
	printf '| Item | Decision | Until | Reason |\n| --- | --- | --- | --- |\n| uncovered lib/x.sh | accept | %s | a helper nobody owns |\n' "$FAR" >"$REPO/architecture/drift.md"
	commit_all "the release"
	sw ship prepare
	assert_eq "$RC" 0 "exit code"
	f=$(note_of)
	specs=$(awk '/^## Specs$/ { on = 1; next } /^## / { on = 0 } on' "$f")
	printf '%s\n' "$specs" | grep -q '^- 002-S1: Goal 1 (spec 002: Feature 002)$' || fail "S1 of 002 is not listed: $specs"
	printf '%s\n' "$specs" | grep -q '^- 002-S2: Goal 2 (spec 002: Feature 002)$' || fail "S2 of 002 is not listed: $specs"
	printf '%s\n' "$specs" | grep -q '002-S3' && fail "a planned slice is listed: $specs"
	printf '%s\n' "$specs" | grep -q '001-S1' && fail "a slice that was done in production is listed: $specs"
	decisions=$(awk '/^## Decisions$/ { on = 1; next } /^## / { on = 0 } on' "$f")
	printf '%s\n' "$decisions" | grep -q '^- 0001: Decision 0001 (accepted)$' || fail "an added ADR is not listed: $decisions"
	printf '%s\n' "$decisions" | grep -q '^- 0003: Decision 0003 (accepted)$' || fail "an accepted ADR is not listed: $decisions"
	printf '%s\n' "$decisions" | grep -q '^- 0004: Decision 0004 (proposed)$' || fail "an added ADR is not listed: $decisions"
	printf '%s\n' "$decisions" | grep -q '0002' && fail "an ADR that did not change is listed: $decisions"
	risk=$(awk '/^## Risk$/ { on = 1; next } /^## / { on = 0 } on' "$f")
	printf '%s\n' "$risk" | grep -q '^- highest tier: R3$' || fail "the highest tier is not R3: $risk"
	printf '%s\n' "$risk" | grep -q '^  - src/pay/charge.sh (src/pay/\*)$' || fail "the R3 path is not listed: $risk"
	printf '%s\n' "$risk" | grep -q 'lib/x.sh' && fail "a path that is not R3 is listed: $risk"
	waivers=$(awk '/^## Waivers and findings$/ { on = 1; next } /^## / { on = 0 } on' "$f")
	printf '%s\n' "$waivers" | grep -q "^- waiver lint: until $FAR (.* days left): legacy lint debt$" || fail "the waiver is not listed: $waivers"
	drift=$(awk '/^## Drift$/ { on = 1; next } /^## / { on = 0 } on' "$f")
	printf '%s\n' "$drift" | grep -q "^- uncovered lib/x.sh: accept (until $FAR): a helper nobody owns$" || fail "the decision is not listed: $drift"
}

# AC-V7-02: where there is nothing to say a section says (none).
test_ac_v7_02_empty_sections() {
	ship_repo
	sw ship prepare
	f=$(note_of)
	for s in Specs Decisions "Waivers and findings" Drift; do
		body=$(awk -v h="## $s" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$f" | grep . || :)
		assert_eq "$body" "(none)" "section $s"
	done
}

# AC-V7-02: running it again for the same tip keeps what the human wrote in the
# three sections, whatever they wrote, and renews the computed ones; a new tip
# is a new file with the three sections unset again.
test_ac_v7_02_rerun_keeps_what_was_written() {
	ship_repo
	sw ship prepare
	f=$(note_of)
	sed 's/^UNSET$/Watch the error rate./' "$f" >"$T/n"
	{ cat "$T/n"; printf '\n## Notes\n\nA section of my own.\n'; } >"$f"
	sed 's/^- commits: 2$/- commits: 99/' "$f" >"$T/n" && cp "$T/n" "$f"
	sw ship prepare
	assert_eq "$RC" 0 "exit code on the second run"
	assert_eq "$(grep -c '^Watch the error rate\.$' "$f")" 3 "written lines kept"
	assert_contains "$f" "A section of my own."
	assert_match "$f" "^- commits: 2$"
	assert_no_match "$f" "commits: 99"
	assert_no_match "$f" "^UNSET$"
	# a new tip, a new note
	printf 'four\n' >>"$REPO/src/app.sh"
	commit_all "fourth"
	sw ship prepare
	assert_eq "$RC" 0 "exit code for the new tip"
	[ -f "$f" ] || fail "the old note is gone"
	g=$(note_of)
	[ "$g" != "$f" ] || fail "the same file for two tips"
	assert_eq "$(grep -c '^UNSET$' "$g")" 3 "the new note is unset"
	assert_contains "$g" "- commits: 3"
}

# AC-V7-03: a note that has not been written is not ready: each section is a
# line of its own and the exit code is 1.
test_ac_v7_03_unfilled_sections_are_problems() {
	ship_repo
	sw ship prepare
	sw ship check
	assert_eq "$RC" 1 "exit code"
	for s in Observability Rollout Rollback; do
		assert_contains "$OUT" "ship: ## $s is not filled in"
	done
	assert_eq "$(grep -c '^ship: ## ' "$OUT")" 3 "lines for the sections"
	f=$(note_of)
	fill_note "$f"
	sw ship check
	assert_eq "$RC" 0 "exit code when filled"
	assert_match "$OUT" "^ship: release note $RELEASES_REL/$(tip7)\.md is ready$"
}

# AC-V7-03: a section that holds only comments, blank lines or UNSET is not
# filled; one with a line of text is, whatever else it says.
test_ac_v7_03_what_counts_as_filled() {
	ship_repo
	sw ship prepare
	f=$(note_of)
	fill_note "$f"
	awk '
		/^## Rollout$/ { print; print ""; print "<!-- a comment"; print "UNSET in a comment -->"; print ""; skip = 1; next }
		/^## / { skip = 0 }
		skip { next }
		{ print }' "$f" >"$T/n" && cp "$T/n" "$f"
	sw ship check
	assert_eq "$RC" 1 "exit code with a section of comments"
	assert_eq "$(grep -c '^ship: ## ' "$OUT")" 1 "lines for the sections"
	assert_contains "$OUT" "ship: ## Rollout is not filled in"
	fill_note "$f"
	awk '/^## Rollout$/ { print; print ""; print "UNSET and then the rollout"; print ""; skip = 1; next } /^## / { skip = 0 } skip { next } { print }' "$f" >"$T/n" && cp "$T/n" "$f"
	sw ship check
	assert_eq "$RC" 0 "exit code with a section that says more than UNSET"
	# a section that was deleted is not filled in either
	grep -v '^## Rollback$' "$f" >"$T/n" && cp "$T/n" "$f"
	sw ship check
	assert_eq "$RC" 1 "exit code with a missing section"
	assert_contains "$OUT" "ship: ## Rollback is not filled in"
}

# AC-V7-03: the note must be of the tip of the integration branch today: a
# commit after prepare, or a production that moved, makes it stale.
test_ac_v7_03_stale_note() {
	ship_repo
	sw ship prepare
	fill_note "$(note_of)"
	sw ship check
	assert_eq "$RC" 0 "exit code before the tip moves"
	old=$(tip7)
	printf 'four\n' >>"$REPO/src/app.sh"
	commit_all "fourth"
	sw ship check
	assert_eq "$RC" 1 "exit code after a commit"
	assert_contains "$OUT" "ship: there is no release note for the tip $(tip7) of main (the note $old.md is for another tip; run ./softwary ship prepare)"
	git -C "$REPO" reset -q --hard HEAD~1
	sw ship check
	assert_eq "$RC" 0 "exit code with the tip back"
	git -C "$REPO" branch -f master "$(git -C "$REPO" rev-parse main~1)"
	sw ship check
	assert_eq "$RC" 1 "exit code after production moved"
	assert_contains "$OUT" "ship: the note was prepared when master was at $(git -C "$REPO" rev-parse --short=7 main~2)"
	sw ship prepare
	sw ship check
	assert_eq "$RC" 0 "exit code after prepare again (the written sections are kept)"
	# a note that says it is of another tip, whatever its name
	sed 's/^integration: .*$/integration: 0000000000000000000000000000000000000000/' "$(note_of)" >"$T/n" && cp "$T/n" "$(note_of)"
	sw ship check
	assert_eq "$RC" 1 "exit code with a note of another tip under this tip's name"
	assert_contains "$OUT" "ship: the note is of another tip than $(git -C "$REPO" rev-parse main)"
}

# AC-V7-03: without a note there is nothing to check; the same refusals as
# prepare for the branches.
test_ac_v7_03_no_note_and_branches() {
	ship_repo
	sw ship check
	assert_eq "$RC" 1 "exit code without a note"
	assert_contains "$OUT" "ship: there is no release note for the tip"
	git -C "$REPO" branch -f master main
	sw ship check
	assert_eq "$RC" 1 "exit code with nothing to ship"
	assert_contains "$OUT" "ship: nothing to ship"
	conf_set production_branch UNSET
	sw ship check
	assert_eq "$RC" 2 "exit code without production_branch"
}

# AC-V7-03: the command is documented in help and a bad call says how to call it.
test_ac_v7_03_usage() {
	ship_repo
	sw ship
	assert_eq "$RC" 2 "exit code without a subcommand"
	assert_contains "$OUT" "usage: ./softwary ship prepare|check|pr"
	sw ship prepare extra
	assert_eq "$RC" 2 "exit code with an argument"
	sw ship launch
	assert_eq "$RC" 2 "exit code with an unknown subcommand"
	sw help
	assert_match "$OUT" "^  ship prepare[|]check[|]pr"
}

# AC-V7-01: ship prepare does not touch the project: the branches, the files and
# the origin stay as they were, and nothing is deployed.
test_ac_v7_01_changes_nothing_but_the_note() {
	ship_repo
	conf_set deploy "touch $T/deployed"
	commit_all "a deploy command"
	main=$(git -C "$REPO" rev-parse main)
	master=$(git -C "$REPO" rev-parse master)
	sw ship prepare
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(git -C "$REPO" rev-parse main)" "$main" "main"
	assert_eq "$(git -C "$REPO" rev-parse master)" "$master" "master"
	assert_eq "$(git -C "$REPO" branch --show-current)" main "the branch checked out"
	[ -z "$(git -C "$REPO" status --porcelain)" ] || fail "the working tree changed"
	[ ! -e "$T/deployed" ] || fail "the deploy command was run"
}

# pr_repo: ship_repo with an origin that has both branches, a fake gh and a
# note that is ready.
pr_repo() {
	ship_repo
	add_origin
	add_production
	fake_gh
	sw ship prepare
	assert_eq "$RC" 0 "ship prepare"
	fill_note "$(note_of)"
}

# AC-V7-04: with a clean note the pull request is opened from the integration
# branch to the production branch, titled for the tip and with the note as its
# body; its address is printed and the event log has ship_pr.
test_ac_v7_04_opens_the_pull_request() {
	pr_repo
	sw ship pr
	assert_eq "$RC" 0 "exit code"
	assert_contains "$OUT" "https://github.com/o/r/pull/1"
	assert_eq "$(cat "$T/gh/base-1")" master "base"
	assert_eq "$(cat "$T/gh/branch-1")" main "head"
	assert_eq "$(cat "$T/gh/pr-1")" "Release $(tip7)" "title"
	cmp -s "$T/gh/body-1" "$(note_of)" || fail "the body is not the note"
	assert_match "$T/gh.log" "^pr list --base master --head main --state open"
	assert_match "$T/gh.log" "^pr create --base master --head main --title Release $(tip7) --body-file "
	last=$(tail -n 1 "$REPO/.softwary/state/events.log")
	assert_eq "$(printf '%s' "$last" | jq -r .event)" ship_pr "event"
	assert_eq "$(printf '%s' "$last" | jq -r .detail)" "https://github.com/o/r/pull/1" "detail"
}

# AC-V7-04: no pull request while the note is not ready: nothing is asked of gh
# to open one.
test_ac_v7_04_not_with_an_unfinished_note() {
	pr_repo
	sed 's/^Written by the human\.$/UNSET/' "$(note_of)" >"$T/n" && cp "$T/n" "$(note_of)"
	sw ship pr
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "ship: ## Observability is not filled in"
	assert_contains "$OUT" "ship: no pull request: the release note is not ready"
	! grep -F "pr create" "$T/gh.log" >/dev/null || fail "gh pr create was called"
	rm "$(note_of)"
	sw ship pr
	assert_eq "$RC" 1 "exit code without a note"
	! grep -F "pr create" "$T/gh.log" >/dev/null || fail "gh pr create was called"
}

# AC-V7-04: a pull request that is open from the same head to the same base is
# said so and no second one is opened; once it is merged or closed a new one can be.
test_ac_v7_04_not_a_second_one() {
	pr_repo
	sw ship pr
	assert_eq "$RC" 0 "first"
	sw ship pr
	assert_eq "$RC" 1 "exit code for the second"
	assert_contains "$OUT" "ship: a pull request from main to master is already open: https://github.com/o/r/pull/1"
	assert_eq "$(grep -c '^pr create' "$T/gh.log")" 1 "pr create calls"
	echo CLOSED >"$T/gh/state-1"
	sw ship pr
	assert_eq "$RC" 0 "exit code once the first is closed"
	assert_contains "$OUT" "https://github.com/o/r/pull/2"
}

# AC-V7-04: ship never merges the pull request and never deploys: gh pr merge
# is not called, the branches stand where they were and the deploy command
# does not run.
test_ac_v7_04_never_merges_or_deploys() {
	ship_repo
	conf_set deploy "touch $T/deployed"
	commit_all "a deploy command"
	add_origin
	add_production
	fake_gh
	sw ship prepare
	fill_note "$(note_of)"
	prod=$(git -C "$REPO" rev-parse origin/master)
	main=$(git -C "$REPO" rev-parse origin/main)
	sw ship pr
	assert_eq "$RC" 0 "exit code"
	! grep -F "pr merge" "$T/gh.log" >/dev/null || fail "gh pr merge was called"
	grep -E -e "deploy" "$T/gh.log" >/dev/null && fail "something deployed through gh"
	[ ! -e "$T/deployed" ] || fail "the deploy command was run"
	git -C "$REPO" fetch -q origin
	assert_eq "$(git -C "$REPO" rev-parse origin/master)" "$prod" "origin's master"
	assert_eq "$(git -C "$REPO" rev-parse origin/main)" "$main" "origin's main"
	assert_eq "$(git -C "$T/origin.git" rev-parse master)" "$prod" "master in origin.git"
	# and the code of ship neither pushes, merges nor reads the deploy command
	! grep -n -E 'git[^|]* push|pr merge|conf_get deploy' "$PKG_ROOT/src/lib/ship.sh" >/dev/null || fail "ship.sh pushes, merges or deploys"
}

# AC-V7-04: what it needs: an origin with both branches, and gh; exit 2 with the reason.
test_ac_v7_04_needs_an_origin_with_both_branches_and_gh() {
	ship_repo
	sw ship prepare
	fill_note "$(note_of)"
	sw ship pr
	assert_eq "$RC" 2 "exit code without an origin"
	assert_contains "$OUT" "ship: there is no origin to open a pull request on"
	add_origin
	sw ship pr
	assert_eq "$RC" 2 "exit code with master only here"
	assert_contains "$OUT" "ship: 'master' is not on origin (push it first)"
	add_production
	RC=0
	(PATH=$(path_without gh) && export PATH && cd "$REPO" && ./softwary ship pr) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "exit code without gh"
	assert_contains "$OUT" "ship: gh is not installed"
}

# AC-V8-09: the new drift items stop ship like the others (D-159): a finding
# whose counter-example no test replays is undecided drift, and a test that
# names it lets ship through.
test_ac_v8_09_unreplayed_finding_stops_ship() {
	ship_repo
	mkdir -p "$REPO/architecture"
	cp -R "$FORMALFIX/architecture/formal" "$REPO/architecture/"
	printf '\n## Findings\n\n| Invariant | Until | Reason |\n| --- | --- | --- |\n| `ShippedWasPaid` | %s | The old order code ships a created order. |\n' "$FAR" \
		>>"$REPO/architecture/formal/order.md"
	conf_set model_check true
	commit_all "the order model, with a finding"
	sw ship prepare
	assert_eq "$RC" 1 "exit code"
	assert_contains "$OUT" "ship: drift has undecided or expired items (./softwary drift)"
	no_note
	printf '# replays CE-order-ShippedWasPaid\n' >>"$REPO/tests/t.sh"
	commit_all "a test that replays it"
	sw ship prepare
	assert_eq "$RC" 0 "exit code with a test"
	[ -f "$(note_of)" ] || fail "no note"
}

run_tests "$0"
