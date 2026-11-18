#!/bin/sh
# End-to-end test of V9 (AC-V9-12): a release archive made by tools/release.sh
# is installed into an empty repository with three tools on and a model id for
# each class in each of them; sync writes the models into the subagents of the
# three tools; doctor catches a reviewer that falls on the implementer's model;
# upgrade works with the same archive; uninstall --yes leaves only the project's
# files and .softwary/{config,local,state}; an archive with a wrong digest
# writes nothing.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# files: every file of the repository except .git, sorted.
files() {
	(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sed 's#^\./##' | sort)
}

# entries DIR: how many entries DIR holds.
entries() {
	find "$1" -mindepth 1 | wc -l | tr -d ' '
}

# fresh_install: the archive of 0.1.0 (ARCHIVE, DIGEST), an empty repository
# with a README and a source directory of its own (REPO, the files in
# $T/project), softwary installed into it from the archive with three tools on,
# a model id for each class in Cursor and Codex, and everything else the
# repository needs for doctor to pass. Nothing is written by the package
# before the archive is checked.
fresh_install() {
	release_archive 0.1.0
	REPO=$T/repo
	mkdir -p "$REPO/src"
	: >"$REPO/src/.gitkeep"
	printf '# My project\n' >"$REPO/README.md"
	git -C "$REPO" init -q || fail "git init failed"
	git -C "$REPO" symbolic-ref HEAD refs/heads/main
	files >"$T/project"
	mkdir -p "$T/tmp"
	TMPDIR=$T/tmp sh "$PKG_ROOT/install.sh" --archive "$ARCHIVE" --sha256 "$DIGEST" "$REPO" >"$OUT" 2>&1 || fail "install from the archive failed"
	assert_eq "$(entries "$T/tmp")" 0 "files left in TMPDIR"
	assert_eq "$(cat "$REPO/.softwary/VERSION")" 0.1.0 "installed version"
	loop_conf
	skip_conf
	add_bootstrap
	conf_all true
	tools_all on
	printf 'cursor: opus = cursor-opus\ncursor: sonnet = cursor-sonnet\ncodex: opus = codex-opus\ncodex: sonnet = codex-sonnet\n' \
		>>"$REPO/.softwary/config/models.conf"
	risk_set default R1
	add_ci
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	add_model
}

# AC-V9-12: the archive is built by release.sh; the installation from it is
# the same as one from the package; sync writes the model into the subagents of
# the three tools, doctor passes, and catches a reviewer on the implementer's model.
test_ac_v9_12_install_sync_doctor() {
	fresh_install
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/implementer.md")" "model: sonnet" "Claude Code, implementer"
	assert_eq "$(sed -n 4p "$REPO/.claude/agents/reviewer.md")" "model: opus" "Claude Code, reviewer"
	assert_eq "$(sed -n 4p "$REPO/.cursor/agents/implementer.md")" "model: cursor-sonnet" "Cursor, implementer"
	assert_eq "$(sed -n 4p "$REPO/.cursor/agents/approver.md")" "model: cursor-opus" "Cursor, approver"
	assert_eq "$(sed -n 4p "$REPO/.codex/agents/implementer.toml")" 'model = "codex-sonnet"' "Codex, implementer"
	assert_eq "$(sed -n 4p "$REPO/.codex/agents/reviewer.toml")" 'model = "codex-opus"' "Codex, reviewer"
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_match "$OUT" "^models +PASS"
	sw version
	assert_eq "$(cat "$OUT")" "softwary 0.1.0" "version"
	sed '/^cursor: opus = /d' "$REPO/.softwary/config/models.conf" >"$T/m" && cp "$T/m" "$REPO/.softwary/config/models.conf"
	printf 'cursor: opus = cursor-sonnet\n' >>"$REPO/.softwary/config/models.conf"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code with the reviewer on the implementer's model"
	assert_match "$OUT" "^models +FAIL .*reviewer uses the implementer's model in cursor \(cursor-sonnet\)"
	assert_match "$OUT" "^models +FAIL .*approver uses the implementer's model in cursor \(cursor-sonnet\)"
	assert_no_match "$OUT" "in codex"
}

# AC-V9-12: upgrade works with the same archive: nothing but the version line
# changes, sync stays clean, the project's files are as they were.
test_ac_v9_12_upgrade_with_the_archive() {
	fresh_install
	files >"$T/before"
	snapshot >"$T/snap-before"
	RC=0
	(cd "$REPO" && TMPDIR=$T/tmp ./softwary upgrade "$ARCHIVE" --sha256 "$DIGEST") >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(head -n 1 "$OUT")" "upgrade: 0.1.0 -> 0.1.0" "first line"
	assert_eq "$(entries "$T/tmp")" 0 "files left in TMPDIR"
	files >"$T/after"
	assert_eq "$(diff "$T/before" "$T/after" || :)" "" "files changed by an upgrade of the same version"
	snapshot >"$T/snap-after"
	assert_eq "$(changed_paths "$T/snap-before" "$T/snap-after")" "" "contents changed by an upgrade of the same version"
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

# AC-V9-12: after uninstall --yes only the project's files and
# .softwary/{config,local,state} are left; the project's own text stays.
test_ac_v9_12_uninstall_leaves_the_project() {
	fresh_install
	mkdir -p "$REPO/.softwary/local" "$REPO/.softwary/state/logs"
	printf 'note\n' >"$REPO/.softwary/local/note.md"
	printf 'log\n' >"$REPO/.softwary/state/logs/a.log"
	sw uninstall
	assert_eq "$RC" 0 "exit code of the list"
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code"
	files >"$T/left"
	grep -Ev '^(\.softwary/(config|local|state)/|\.github/|architecture/)' "$T/left" >"$T/left-project" || :
	assert_eq "$(diff "$T/project" "$T/left-project" || :)" "" "the files left besides config, local, state, .github and architecture"
	for f in .softwary/local/note.md .softwary/state/logs/a.log .softwary/config/commands.conf .softwary/config/models.conf .softwary/config/tools.conf; do
		[ -f "$REPO/$f" ] || fail "$f is gone"
	done
	[ ! -e "$REPO/.softwary/bin" ] && [ ! -e "$REPO/softwary" ] && [ ! -e "$REPO/.softwary/generated" ] || fail "the package is still there"
	[ ! -e "$REPO/.claude" ] && [ ! -e "$REPO/.cursor" ] && [ ! -e "$REPO/.codex" ] && [ ! -e "$REPO/.agents" ] || fail "generated files are still there"
	[ ! -e "$REPO/AGENTS.md" ] && [ ! -e "$REPO/CLAUDE.md" ] || fail "AGENTS.md and CLAUDE.md held only the blocks and should be gone"
}

# AC-V9-12: an archive with a wrong digest writes nothing, to an empty
# directory and to an installed repository alike (install and upgrade).
test_ac_v9_12_wrong_digest_writes_nothing() {
	release_archive 0.1.0
	wrong=$(printf '%s' "$DIGEST" | tr '0-9a-f' '1-9a-f0')
	mkdir -p "$T/empty" "$T/tmp"
	TMPDIR=$T/tmp sh "$PKG_ROOT/install.sh" --archive "$ARCHIVE" --sha256 "$wrong" "$T/empty" >"$OUT" 2>&1 && fail "install accepted a wrong digest"
	assert_contains "$OUT" "does not match"
	assert_eq "$(entries "$T/empty")" 0 "files written to the empty directory"
	setup_repo
	snapshot >"$T/before"
	RC=0
	(cd "$REPO" && TMPDIR=$T/tmp ./softwary upgrade "$ARCHIVE" --sha256 "$wrong") >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "upgrade exit code"
	assert_contains "$OUT" "does not match"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "files changed by an upgrade with a wrong digest"
	assert_eq "$(entries "$T/tmp")" 0 "files left in TMPDIR"
}

run_tests "$0"
