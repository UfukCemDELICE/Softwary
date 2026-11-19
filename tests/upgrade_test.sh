#!/bin/sh
# Tests for ./softwary upgrade (M3).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# make_pkg DIR VERSION: a copy of the package with the given version.
make_pkg() {
	mkdir -p "$1"
	cp -R "$PKG_ROOT/install.sh" "$PKG_ROOT/VERSION" "$PKG_ROOT/src" "$1/"
	printf '%s\n' "$2" >"$1/VERSION"
}

# installed_version: the version recorded in the repo.
installed_version() {
	cat "$REPO/.softwary/VERSION"
}

# AC-M3-08: managed files are replaced, the version change is shown first, sync runs.
# The package path may be relative to the caller's directory.
test_ac_m3_08_replaces_managed_files_and_runs_sync() {
	setup_repo
	make_pkg "$T/pkg" "$NEXT_VERSION"
	printf '8. A new rule.\n' >>"$T/pkg/src/rules/core.md"
	RC=0
	(cd "$REPO" && ./softwary upgrade ../pkg) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(head -n 1 "$OUT")" "upgrade: $PKG_VERSION -> $NEXT_VERSION" "first line"
	assert_eq "$(installed_version)" "$NEXT_VERSION" "installed version"
	cmp -s "$T/pkg/src/rules/core.md" "$REPO/.softwary/rules/core.md" || fail "core.md was not replaced"
	assert_contains "$REPO/AGENTS.md" "8. A new rule."
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

# AC-M3-08: files that the new version no longer has are removed; new ones are added.
test_ac_m3_08_removes_files_gone_from_new_version() {
	setup_repo
	make_pkg "$T/pkg" "$NEXT_VERSION"
	rm "$T/pkg/src/templates/artifacts/review.md"
	printf 'extra\n' >"$T/pkg/src/rules/extra.md"
	sw upgrade "$T/pkg"
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^  removed \.softwary/templates/review\.md$"
	[ ! -e "$REPO/.softwary/templates/review.md" ] || fail "review.md still there"
	[ -f "$REPO/.softwary/rules/extra.md" ] || fail "new file was not installed"
}

# AC-M3-08: nothing the project owns is touched.
test_ac_m3_08_leaves_project_files_alone() {
	setup_repo
	mkdir -p "$REPO/specs/001-x" "$REPO/architecture/decisions" "$REPO/.softwary/local/skills/mine" "$REPO/.softwary/state/logs"
	printf 'spec\n' >"$REPO/specs/001-x/spec.md"
	printf 'adr\n' >"$REPO/architecture/decisions/0001-x.md"
	printf 'terms\n' >"$REPO/CONTEXT.md"
	printf -- '---\nname: mine\ndescription: Project skill.\n---\nBody.\n' >"$REPO/.softwary/local/skills/mine/SKILL.md"
	printf 'log\n' >"$REPO/.softwary/state/logs/verify-lint.log"
	printf '# edited\n' >>"$REPO/.softwary/config/commands.conf"
	make_pkg "$T/pkg" "$NEXT_VERSION"
	printf 'changed\n' >>"$T/pkg/src/rules/core.md"
	snapshot >"$T/before"
	sw upgrade "$T/pkg"
	assert_eq "$RC" 0 "exit code"
	snapshot >"$T/after"
	changed=$(changed_paths "$T/before" "$T/after")
	[ -n "$changed" ] || fail "nothing changed at all"
	printf '%s\n' "$changed" >"$T/changed"
	assert_no_match "$T/changed" '^(\.softwary/(config|local|state)/|architecture/|specs/|CONTEXT\.md)'
}

# AC-M3-08: versions compare numerically; an older package or a bad version is
# refused (2) without changing anything; the same version is re-applied.
test_ac_m3_08_version_order_is_numeric() {
	setup_repo
	printf '0.9.0\n' >"$REPO/.softwary/VERSION"
	make_pkg "$T/new" 0.10.0
	sw upgrade "$T/new"
	assert_eq "$RC" 0 "0.9.0 -> 0.10.0"
	assert_eq "$(installed_version)" 0.10.0 "installed version"
	make_pkg "$T/old" 0.9.0
	snapshot >"$T/before"
	sw upgrade "$T/old"
	assert_eq "$RC" 2 "0.10.0 -> 0.9.0"
	assert_match "$OUT" "0\.9\.0 is older than the installed 0\.10\.0"
	make_pkg "$T/bad" 1.2
	sw upgrade "$T/bad"
	assert_eq "$RC" 2 "package version 1.2"
	assert_match "$OUT" "invalid version '1\.2'"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths"
	printf 'abc\n' >"$REPO/.softwary/VERSION"
	sw upgrade "$T/new"
	assert_eq "$RC" 2 "installed version abc"
	printf '0.10.0\n' >"$REPO/.softwary/VERSION"
	sw upgrade "$T/new"
	assert_eq "$RC" 0 "same version"
	assert_eq "$(head -n 1 "$OUT")" "upgrade: 0.10.0 -> 0.10.0" "first line"
}

# AC-M3-08: a path that is not a package, or no path, is refused (2); nothing changes.
test_ac_m3_08_not_a_package_exits_2() {
	setup_repo
	mkdir "$T/empty"
	snapshot >"$T/before"
	for p in "$REPO" "$T/nope" "$T/empty"; do
		sw upgrade "$p"
		assert_eq "$RC" 2 "upgrade $p"
		assert_match "$OUT" "is not a softwary package"
	done
	sw upgrade
	assert_eq "$RC" 2 "upgrade without a path"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths"
}

# AC-M3-08: the exit code of the final sync is the exit code of upgrade.
test_ac_m3_08_sync_failure_is_reported() {
	setup_repo
	tools_set cursor UNSET
	make_pkg "$T/pkg" "$NEXT_VERSION"
	sw upgrade "$T/pkg"
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "UNSET"
	assert_eq "$(installed_version)" "$NEXT_VERSION" "the managed files were still replaced"
}

# AC-M3-08: upgrade points core.hooksPath at the managed hooks, like install.
test_ac_m3_08_hooks_path_redirected() {
	setup_repo
	git -C "$REPO" config --unset core.hooksPath
	make_pkg "$T/pkg" "$NEXT_VERSION"
	sw upgrade "$T/pkg"
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(git -C "$REPO" config --get core.hooksPath)" .softwary/hooks "core.hooksPath"
}

# AC-V5-12: upgrade removes the skills the new version no longer has, from the
# sources and from all three tools; a skill of the same name under local/ stays.
test_ac_v5_12_upgrade_removes_gone_skills() {
	setup_repo
	tools_all on
	for s in discover architect specify slice; do
		mkdir -p "$REPO/.softwary/skills/$s"
		printf -- '---\nname: %s\ndescription: Old stage.\n---\nBody.\n' "$s" >"$REPO/.softwary/skills/$s/SKILL.md"
	done
	mkdir -p "$REPO/.softwary/local/skills/slice"
	printf -- '---\nname: slice\ndescription: My own slicing.\n---\nMine.\n' >"$REPO/.softwary/local/skills/slice/SKILL.md"
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	for d in .claude .cursor .agents; do
		[ -f "$REPO/$d/skills/softwary-discover/SKILL.md" ] || fail "$d: the old skill was not distributed"
	done
	make_pkg "$T/pkg" "$(installed_version)"
	sw upgrade "$T/pkg"
	assert_eq "$RC" 0 "upgrade exit code"
	for s in discover architect specify; do
		[ ! -e "$REPO/.softwary/skills/$s" ] || fail ".softwary/skills/$s is still there"
		for d in .claude .cursor .agents; do
			[ ! -e "$REPO/$d/skills/softwary-$s" ] || fail "$d/skills/softwary-$s is still there"
		done
	done
	[ ! -e "$REPO/.softwary/skills/slice" ] || fail ".softwary/skills/slice is still there"
	for d in .claude .cursor .agents; do
		assert_contains "$REPO/$d/skills/softwary-slice/SKILL.md" "My own slicing."
	done
	for s in define blueprint plan handoff; do
		[ -f "$REPO/.claude/skills/softwary-$s/SKILL.md" ] || fail "softwary-$s was not generated"
	done
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
}

run_tests "$0"
