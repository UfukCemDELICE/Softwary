#!/bin/sh
# Tests for ./softwary guard (V3): protected paths, touches, test loosening.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
S1=specs/001-login/slices/S1.md
REVIEW=specs/001-login/reviews/S1.md

# guard_repo: approved product, blueprint and plan, an origin, and the job
# branch softwary/001-S1 checked out with nothing changed yet. S1 touches
# src/api/login.py.
guard_repo() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_plan
	mkdir -p "$REPO/tests" "$REPO/src/api"
	printf '# covers AC-001-01\n' >"$REPO/tests/test_login.py"
	printf 'code\n' >"$REPO/src/api/login.py"
	add_origin
	git -C "$REPO" checkout -q -b "softwary/$JOB"
}

# put FILE TEXT: writes FILE (and its directory) in the repo.
put() {
	mkdir -p "$(dirname "$REPO/$1")"
	printf '%s\n' "$2" >"$REPO/$1"
}

# set_touches VALUE: S1's touches, on the base too (the job branch is cut
# from main, so the plan is what the guard reads).
set_touches() {
	git -C "$REPO" checkout -q main
	fm_set "$REPO/$S1" touches "$1"
	commit_all "touches"
	git -C "$REPO" push -q --no-verify origin main
	git -C "$REPO" fetch -q origin
	git -C "$REPO" checkout -q "softwary/$JOB"
	git -C "$REPO" merge -q --no-edit main
}

# AC-V3-01: every protected root is a line of its own; src/ is not; 1 and 0.
test_ac_v3_01_protected_paths() {
	guard_repo
	put src/api/login.py "changed"
	commit_all "only src"
	sw guard $JOB --base main
	assert_eq "$RC" 0 "exit code with only src/ changed"
	assert_match "$OUT" "^guard: no problems$"
	assert_no_match "$OUT" "protected"
	protected=".softwary/config/commands.conf .github/workflows/softwary.yml CODEOWNERS docs/CODEOWNERS softwary product/PRODUCT.md architecture/model/system.calm.json architecture/data/model.json architecture/contracts/api.yaml"
	for p in $protected; do
		mkdir -p "$(dirname "$REPO/$p")"
		printf '\n# changed\n' >>"$REPO/$p"
	done
	commit_all "protected"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code with protected paths changed"
	for p in $protected; do
		assert_match "$OUT" "^guard: protected: $(printf '%s' "$p" | sed 's/\./\\./g')$"
	done
	assert_no_match "$OUT" "^guard: protected: src/"
	assert_match "$OUT" "^guard: [0-9]+ problem\(s\)$"
}

# AC-V3-01: the diff is taken from the common ancestor with the base, and
# only what is committed counts; a path that is merely similar is not protected.
test_ac_v3_01_similar_paths_are_not_protected() {
	guard_repo
	put src/api/login.py "changed"
	put docs/notes.md "x"
	put products/list.md "x"
	put architecture/views/system.mmd "x"
	put softwary.txt "x"
	commit_all "similar"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_no_match "$OUT" "protected"
}

# AC-V3-02: exact paths, directories (with or without a slash) and globs cover;
# a prefix that is not a directory does not; the slice and review files do.
test_ac_v3_02_outside_touches() {
	guard_repo
	set_touches "src/api/login.py, lib/, util, src/gen/*.sh"
	put src/api/login.py "changed"
	put lib/a.txt "x"
	put lib/deep/b.txt "x"
	put util/c.txt "x"
	put src/gen/x.sh "x"
	put src/gen/sub/y.sh "x"
	fm_set "$REPO/$S1" status in-progress
	put "$REVIEW" "review"
	commit_all "covered"
	sw guard $JOB --base main
	assert_eq "$RC" 0 "exit code with every path covered"
	assert_match "$OUT" "^guard: no problems$"
	put src/api/other.py "x"
	put src/api/login.py.bak "x"
	put lib2/d.txt "x"
	put src/gen/z.txt "x"
	put specs/001-login/slices/S2.md "x"
	commit_all "not covered"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code with paths outside touches"
	for p in src/api/other.py src/api/login.py.bak lib2/d.txt src/gen/z.txt specs/001-login/slices/S2.md; do
		assert_match "$OUT" "^guard: outside touches: $(printf '%s' "$p" | sed 's/\./\\./g')$"
	done
	assert_no_match "$OUT" "outside touches: (lib/|util/|src/gen/x|src/gen/sub|specs/001-login/slices/S1|specs/001-login/reviews)"
	assert_match "$OUT" "^guard: 5 problem\(s\)$"
}

# AC-V3-02: a job cannot widen its own touches: the slice is read at the base.
test_ac_v3_02_touches_are_read_at_the_base() {
	guard_repo
	fm_set "$REPO/$S1" touches "src/api/login.py, evil/"
	put evil/x.txt "x"
	commit_all "widened"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^guard: outside touches: evil/x\.txt$"
}

# AC-V3-04: a usage mistake, an unknown job or slice and a base that is not
# there are configuration errors: 2.
test_ac_v3_04_usage_and_config_errors() {
	guard_repo
	sw guard
	assert_eq "$RC" 2 "no job"
	sw guard $JOB --base
	assert_eq "$RC" 2 "--base without a value"
	sw guard $JOB --other
	assert_eq "$RC" 2 "unknown option"
	sw guard not-a-job
	assert_eq "$RC" 2 "malformed job"
	sw guard 009-S9 --base main
	assert_eq "$RC" 2 "unknown spec"
	sw guard 001-S9 --base main
	assert_eq "$RC" 2 "unknown slice"
	sw guard $JOB --base nowhere
	assert_eq "$RC" 2 "base that does not exist"
	assert_contains "$OUT" "nowhere"
	sw guard $JOB
	assert_eq "$RC" 0 "default base is the integration branch"
	conf_set integration_branch UNSET
	sw guard $JOB
	assert_eq "$RC" 2 "no integration branch and no --base"
}

# AC-V3-07: plan check reports an empty touches and one that leaves the repo.
test_ac_v3_07_plan_check_touches() {
	setup_repo
	add_product
	add_blueprint
	sw approve product
	sw approve blueprint
	add_plan
	sw plan check
	assert_eq "$RC" 0 "clean plan"
	fm_set "$REPO/$S1" touches ""
	sw plan check
	assert_eq "$RC" 1 "empty touches"
	assert_match "$OUT" "^$S1: touches is empty$"
	for bad in /abs a/../b .. ../x a/..; do
		fm_set "$REPO/$S1" touches "src/ok.py, $bad"
		sw plan check
		assert_eq "$RC" 1 "touches $bad"
		assert_contains "$OUT" "$S1: touches: '$bad' is outside the repository"
	done
	fm_set "$REPO/$S1" touches "src/**/*.py, docs/, a..b/c"
	sw plan check
	assert_eq "$RC" 0 "globs, directories and dots in names are fine"
	fm_set "$REPO/$S1" touches ""
	fm_set "$REPO/specs/001-login/spec.md" status "done"
	sw plan check
	assert_no_match "$OUT" "touches"
}

run_tests "$0"
