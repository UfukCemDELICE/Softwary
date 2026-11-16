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

# rebase_base MESSAGE: commits the working tree as the new base: main (local
# and origin) moves to it and the job branch stands on it.
rebase_base() {
	commit_all "$1"
	git -C "$REPO" branch -f main HEAD
	git -C "$REPO" push -q --no-verify -f origin main
	git -C "$REPO" fetch -q origin
}

# AC-V3-03: a deleted file under test_paths is reported; other deletions are not.
test_ac_v3_03_test_deleted() {
	guard_repo
	put tests/test_extra.py "assert True"
	put src/api/gone.py "x"
	rebase_base "more files"
	set_touches "src/api/login.py, src/api/gone.py, tests/"
	rm "$REPO/tests/test_extra.py" "$REPO/src/api/gone.py"
	commit_all "delete"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^guard: test deleted: tests/test_extra\.py$"
	assert_no_match "$OUT" "src/api/gone"
	assert_no_match "$OUT" "criterion dropped"
}

# AC-V3-03: a criterion id that the base's tests carry and HEAD's do not is
# reported, over several test_paths; an id that only moved is not.
test_ac_v3_03_criterion_dropped() {
	guard_repo
	conf_set test_paths "tests spec_tests"
	put tests/test_a.py "# covers AC-001-01
# covers AC-001-02"
	put spec_tests/t_b.py "# covers AC-001-03"
	put docs/other.md "AC-001-04 is mentioned outside the tests"
	rebase_base "tests"
	set_touches "src/api/login.py, tests/, spec_tests/"
	put tests/test_a.py "# covers AC-001-01 only"
	put spec_tests/t_b.py "nothing"
	put tests/test_c.py "# covers AC-001-01"
	commit_all "drop"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^guard: criterion dropped: AC-001-02$"
	assert_match "$OUT" "^guard: criterion dropped: AC-001-03$"
	assert_no_match "$OUT" "AC-001-01|AC-001-04"
	assert_match "$OUT" "^guard: 2 problem\(s\)$"
}

# AC-V3-03: an added line that matches test-skip.conf is reported with its
# file and text; a marker that was already there, one removed, and one
# outside test_paths are not.
test_ac_v3_03_skip_marker_added() {
	guard_repo
	put tests/test_login.py "# covers AC-001-01
old.skip('already there')"
	rebase_base "base"
	set_touches "src/api/login.py, tests/"
	put tests/test_login.py "# covers AC-001-01
old.skip('already there')
y.skip('flaky')"
	put tests/test_new.py "it.only('focus')"
	put src/api/login.py "z.skip('not a test')"
	commit_all "markers"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^guard: skip marker: tests/test_login\.py: y\.skip\('flaky'\)$"
	assert_match "$OUT" "^guard: skip marker: tests/test_new\.py: it\.only\('focus'\)$"
	assert_no_match "$OUT" "already there|not a test"
	assert_match "$OUT" "^guard: 2 problem\(s\)$"
}

# AC-V3-04: test-skip.conf must have a pattern or NONE with a reason; a bad
# or missing file, and unset test_paths, are configuration errors (2), and
# doctor reports the file on a line of its own.
test_ac_v3_04_test_skip_conf() {
	guard_repo
	skip_file=$REPO/.softwary/config/test-skip.conf
	printf '# only a comment\n\n' >"$skip_file"
	sw doctor
	assert_match "$OUT" "^test-skip +FAIL \(.*no patterns: add your test framework's skip and focus markers, or NONE: <reason>"
	sw guard $JOB --base main
	assert_eq "$RC" 2 "no patterns"
	printf '\\.skip\\(\n(unclosed\n' >"$skip_file"
	sw doctor
	assert_match "$OUT" "^test-skip +FAIL \(.*test-skip\.conf:2: invalid pattern"
	sw guard $JOB --base main
	assert_eq "$RC" 2 "invalid pattern"
	assert_contains "$OUT" "test-skip.conf:2: invalid pattern"
	printf 'NONE\n' >"$skip_file"
	sw guard $JOB --base main
	assert_eq "$RC" 2 "NONE without a reason"
	printf 'NONE: no test framework yet\n\\.skip\\(\n' >"$skip_file"
	sw guard $JOB --base main
	assert_eq "$RC" 2 "NONE next to patterns"
	printf 'NONE: no test framework yet\n' >"$skip_file"
	sw doctor
	assert_match "$OUT" "^test-skip +PASS"
	put tests/test_login.py "# covers AC-001-01
x.skip('ignored under NONE')"
	rebase_base "marker"
	set_touches "src/api/login.py, tests/"
	put tests/test_login.py "# covers AC-001-01
x.skip('ignored under NONE')
y.skip('too')"
	commit_all "marker"
	sw guard $JOB --base main
	assert_eq "$RC" 0 "NONE turns the marker check off"
	rm "$skip_file"
	sw guard $JOB --base main
	assert_eq "$RC" 2 "missing file"
	sw doctor
	assert_match "$OUT" "^test-skip +FAIL"
	skip_conf
	conf_del test_paths
	sw guard $JOB --base main
	assert_eq "$RC" 2 "test_paths not set"
	assert_contains "$OUT" "test_paths"
	conf_set test_paths UNSET
	sw guard $JOB --base main
	assert_eq "$RC" 2 "test_paths UNSET"
	conf_set test_paths tests
	sw guard $JOB --base main
	assert_eq "$RC" 1 "the marker is reported once the file is right"
}

run_tests "$0"
