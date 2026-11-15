#!/bin/sh
# Tests for the git hooks installed by install.sh (M3).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# Real commits and pushes run the hooks, so the identity must come from here.
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

# hooks_path [DIR]: the core.hooksPath of DIR (default: the repo), or nothing.
hooks_path() {
	git -C "${1:-$REPO}" config --get core.hooksPath || :
}

# new_repo: an empty, initialised git repo that softwary is not installed in.
new_repo() {
	REPO=$T/repo
	mkdir -p "$REPO"
	git -C "$REPO" init -q
}

# install_here: runs install.sh into the repo, keeping its output in $OUT.
install_here() {
	RC=0
	sh "$PKG_ROOT/install.sh" "$REPO" >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "install exit code"
}

# gcommit MESSAGE: a real git commit (hooks run); output in $OUT, exit in $RC.
gcommit() {
	RC=0
	git -C "$REPO" commit -q -m "$1" >"$OUT" 2>&1 || RC=$?
}

# change_file: stages a new version of f.
change_file() {
	printf '%s\n' "$1" >"$REPO/f"
	git -C "$REPO" add f
}

# add_remote: a bare remote called origin and main as the current branch.
add_remote() {
	git init -q --bare "$T/remote.git"
	git -C "$REPO" remote add origin "$T/remote.git"
	git -C "$REPO" symbolic-ref HEAD refs/heads/main
}

# AC-M3-01: install points core.hooksPath at the managed, executable hooks.
test_ac_m3_01_install_sets_hooks_path() {
	setup_repo
	assert_eq "$(hooks_path)" .softwary/hooks "core.hooksPath"
	[ -x "$REPO/.softwary/hooks/pre-commit" ] || fail "pre-commit is not executable"
	[ -x "$REPO/.softwary/hooks/pre-push" ] || fail "pre-push is not executable"
	conf_all true
	sw doctor
	assert_match "$OUT" "^hooks +PASS"
}

# AC-M3-01: another hook path is left alone and doctor reports it.
test_ac_m3_01_other_hooks_path_kept() {
	new_repo
	git -C "$REPO" config core.hooksPath .githooks
	install_here
	assert_eq "$(hooks_path)" .githooks "core.hooksPath"
	assert_match "$OUT" "^hooks: core.hooksPath is '.githooks'; kept$"
	sw doctor
	assert_match "$OUT" "^hooks +FAIL \(core\.hooksPath is '\.githooks', not \.softwary/hooks\)$"
}

# AC-M3-01: a real (non-sample) hook in .git/hooks is not displaced; samples are no obstacle.
test_ac_m3_01_custom_hook_kept() {
	new_repo
	printf '#!/bin/sh\nexit 0\n' >"$REPO/.git/hooks/pre-commit"
	chmod +x "$REPO/.git/hooks/pre-commit"
	install_here
	assert_eq "$(hooks_path)" "" "core.hooksPath"
	assert_match "$OUT" "^hooks: \.git/hooks/pre-commit is not a sample; kept$"
	sw doctor
	assert_match "$OUT" "^hooks +FAIL \(core\.hooksPath is not set.*\.git/hooks/pre-commit"
}

# AC-M3-01: a target that is not the root of a git repo (a subdirectory, a
# plain directory, a linked worktree) never changes another repo's config.
test_ac_m3_01_not_a_repo_root() {
	mkdir "$T/outer" "$T/plain"
	git -C "$T/outer" init -q
	mkdir "$T/outer/sub"
	REPO=$T/outer/sub
	install_here
	assert_match "$OUT" "^hooks: not a git repository root"
	assert_eq "$(hooks_path "$T/outer")" "" "outer repo core.hooksPath"
	REPO=$T/plain
	install_here
	assert_match "$OUT" "^hooks: not a git repository root"
	# A linked worktree has a .git file; its hooks directory is elsewhere.
	new_repo
	git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
	git -C "$REPO" worktree add -q "$T/wt" -b wt
	REPO=$T/wt
	install_here
	assert_eq "$(hooks_path "$T/wt")" .softwary/hooks "worktree core.hooksPath"
}

# AC-M3-02: verify --fast gates the commit.
test_ac_m3_02_commit_gated_by_verify_fast() {
	setup_repo
	conf_all true
	change_file one
	gcommit one
	assert_eq "$RC" 0 "commit with passing checks"
	conf_set lint false
	change_file two
	gcommit two
	[ "$RC" -ne 0 ] || fail "commit went through although lint fails"
	assert_match "$OUT" "^lint +FAIL"
	assert_eq "$(git -C "$REPO" rev-list --count HEAD)" 1 "commits"
}

# AC-M3-02: the full verify gates the push, not the commit.
test_ac_m3_02_push_gated_by_verify() {
	setup_repo
	conf_all true
	add_remote
	conf_set test false
	change_file one
	gcommit one
	assert_eq "$RC" 0 "commit (fast keys only)"
	RC=0
	git -C "$REPO" push -q origin main >"$OUT" 2>&1 || RC=$?
	[ "$RC" -ne 0 ] || fail "push went through although test fails"
	assert_match "$OUT" "^test +FAIL"
	git -C "$T/remote.git" rev-parse -q --verify refs/heads/main >/dev/null && fail "the remote received main"
	conf_set test true
	git -C "$REPO" push -q origin main >"$OUT" 2>&1 || fail "push with passing checks failed"
}

# AC-M3-02: a hook in .softwary/local/hooks/ replaces the managed one.
test_ac_m3_02_local_hook_overrides() {
	setup_repo
	conf_all true
	add_remote
	conf_set lint false
	mkdir -p "$REPO/.softwary/local/hooks"
	printf '#!/bin/sh\ntouch "%s/ran"\nexit 0\n' "$T" >"$REPO/.softwary/local/hooks/pre-commit"
	printf '#!/bin/sh\nexit 1\n' >"$REPO/.softwary/local/hooks/pre-push"
	chmod +x "$REPO/.softwary/local/hooks/pre-commit" "$REPO/.softwary/local/hooks/pre-push"
	change_file one
	gcommit one
	assert_eq "$RC" 0 "commit with a local hook that accepts"
	[ -f "$T/ran" ] || fail "the local pre-commit hook did not run"
	conf_set lint true
	RC=0
	git -C "$REPO" push -q origin main >"$OUT" 2>&1 || RC=$?
	[ "$RC" -ne 0 ] || fail "push went through although the local pre-push hook rejects"
}

# AC-M3-02: without the wrapper the hook refuses instead of letting the commit pass.
test_ac_m3_02_missing_wrapper_fails_closed() {
	setup_repo
	conf_all true
	rm "$REPO/softwary"
	change_file one
	gcommit one
	[ "$RC" -ne 0 ] || fail "commit went through without ./softwary"
	assert_match "$OUT" "\./softwary is missing"
}

run_tests "$0"
