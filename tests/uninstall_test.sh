#!/bin/sh
# Tests for ./softwary uninstall (V9).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# project: a repository with softwary installed, all three tools on and
# synced, and the project's own files: code, product, architecture, specs,
# CONTEXT.md, a README, an AGENTS.md with text of its own, a local skill, state,
# a rule of its own in .cursor/ and a configuration that is the project's.
project() {
	setup_repo
	printf '# My AGENTS\n\nBuild with make.\n' >"$REPO/AGENTS.md"
	conf_all true
	tools_all on
	models_translate
	mkdir -p "$REPO/product" "$REPO/architecture/decisions" "$REPO/specs/001-x" "$REPO/.softwary/local/skills/mine" \
		"$REPO/.softwary/state/logs" "$REPO/.cursor/rules" "$REPO/src"
	printf 'product\n' >"$REPO/product/PRODUCT.md"
	printf 'adr\n' >"$REPO/architecture/decisions/0001-x.md"
	printf 'spec\n' >"$REPO/specs/001-x/spec.md"
	printf 'terms\n' >"$REPO/CONTEXT.md"
	printf 'readme\n' >"$REPO/README.md"
	printf 'code\n' >"$REPO/src/code.sh"
	printf -- '---\nname: mine\ndescription: Project skill.\n---\nBody.\n' >"$REPO/.softwary/local/skills/mine/SKILL.md"
	printf 'log\n' >"$REPO/.softwary/state/logs/verify-lint.log"
	printf 'rule\n' >"$REPO/.cursor/rules/mine.mdc"
	sw sync
	[ "$RC" -eq 0 ] || fail "sync failed"
}

# files: every file of the repository except .git, sorted.
files() {
	(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sed 's#^\./##' | sort)
}

# AC-V9-07: without --yes it lists every path it would remove and writes
# nothing (0); the list is what --yes then removes.
test_ac_v9_07_lists_and_writes_nothing_without_yes() {
	project
	snapshot >"$T/before"
	git -C "$REPO" config --get core.hooksPath >"$T/hp-before"
	sw uninstall
	assert_eq "$RC" 0 "exit code"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths"
	assert_eq "$(git -C "$REPO" config --get core.hooksPath)" "$(cat "$T/hp-before")" "core.hooksPath"
	for p in softwary .softwary/bin/softwary .softwary/lib/sync.sh .softwary/VERSION .softwary/templates/spec.md \
		.claude/agents/reviewer.md .cursor/agents/reviewer.md .codex/agents/reviewer.toml .agents/skills/softwary-run/SKILL.md \
		'AGENTS.md (block)' '.softwary/generated'; do
		assert_match "$OUT" "^  remove $(printf '%s' "$p" | sed 's/[().]/\\&/g')\$"
	done
	assert_contains "$OUT" "--yes"
	cp "$OUT" "$T/listing"
	files >"$T/files-before"
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code with --yes"
	files >"$T/files-after"
	# every file that vanished was listed, and every listed file (not a block) vanished
	comm -23 "$T/files-before" "$T/files-after" >"$T/vanished"
	sed -n 's/^  remove \(.*\)$/\1/p' "$T/listing" | sed 's/ (block; nothing else was in the file)$//' | grep -v ' (block)$' | grep -v '^core\.hooksPath' | sort >"$T/listed"
	assert_eq "$(comm -13 "$T/listed" "$T/vanished")" "" "removed but not listed"
	assert_eq "$(comm -23 "$T/listed" "$T/vanished")" "" "listed but not removed"
}

# AC-V9-07: after --yes only the project's files stay: its code, product,
# architecture, specs, CONTEXT.md, a rule of its own, config/, local/ and
# state/ of .softwary/, and AGENTS.md without the block.
test_ac_v9_07_yes_leaves_only_the_projects_files() {
	project
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code"
	files >"$T/files"
	sed -e '/^\.git\//d' "$T/files" >"$T/kept"
	grep -Ev '^(\.softwary/(config|local|state)/|\.github/|product/|architecture/|specs/|src/|\.cursor/rules/|README\.md$|CONTEXT\.md$|AGENTS\.md$)' "$T/kept" >"$T/others" || :
	assert_eq "$(cat "$T/others")" "" "files of the package left"
	for f in README.md CONTEXT.md src/code.sh product/PRODUCT.md architecture/decisions/0001-x.md specs/001-x/spec.md \
		.cursor/rules/mine.mdc .softwary/local/skills/mine/SKILL.md .softwary/state/logs/verify-lint.log \
		.softwary/config/commands.conf .softwary/config/tools.conf .softwary/config/models.conf .softwary/config/loop.conf AGENTS.md; do
		[ -f "$REPO/$f" ] || fail "$f is gone"
	done
	assert_eq "$(cat "$REPO/AGENTS.md")" "$(printf '# My AGENTS\n\nBuild with make.')" "AGENTS.md without the block"
	assert_no_match "$REPO/AGENTS.md" 'softwary:'
	[ ! -e "$REPO/CLAUDE.md" ] || fail "CLAUDE.md held only the block and should be gone"
	[ ! -e "$REPO/softwary" ] || fail "the wrapper is still there"
	[ -d "$REPO/.softwary" ] || fail ".softwary/ itself is gone"
	for d in .claude .codex .agents; do
		[ ! -e "$REPO/$d" ] || fail "$d is still there"
	done
	[ ! -e "$REPO/.cursor/agents" ] && [ ! -e "$REPO/.cursor/skills" ] || fail "the Cursor files are still there"
	assert_match "$OUT" "^removed AGENTS\.md \(block\)$"
	assert_match "$OUT" "^removed CLAUDE\.md \(block; nothing else was in the file\)$"
	assert_match "$OUT" "^uninstall: done"
}

# AC-V9-07: a generated file that was edited by hand stays, with its own line;
# so does an edited block; the rest goes.
test_ac_v9_07_edited_generated_files_stay() {
	project
	printf 'my note\n' >>"$REPO/.cursor/agents/reviewer.md"
	sed 's/^@AGENTS.md$/@AGENTS.md edited/' "$REPO/CLAUDE.md" >"$T/c" && cp "$T/c" "$REPO/CLAUDE.md"
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^kept \.cursor/agents/reviewer\.md \(changed by hand\)$"
	assert_match "$OUT" "^kept CLAUDE\.md \(block\) \(changed by hand\)$"
	assert_contains "$REPO/.cursor/agents/reviewer.md" "my note"
	assert_contains "$REPO/CLAUDE.md" "@AGENTS.md edited"
	[ ! -e "$REPO/.cursor/agents/implementer.md" ] || fail "an untouched generated file is still there"
	[ ! -e "$REPO/.codex" ] || fail ".codex is still there"
}

# AC-V9-07: a missing manifest means nothing generated can be told from the
# project's files: they stay, and it says so; the package still goes.
test_ac_v9_07_no_manifest_keeps_the_generated_files() {
	project
	rm -f "${REPO:?}/.softwary/generated"
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^kept the generated files: \.softwary/generated is missing"
	[ -f "$REPO/.cursor/agents/reviewer.md" ] || fail "a generated file went without a manifest"
	[ ! -e "$REPO/softwary" ] || fail "the wrapper is still there"
}

# AC-V9-07: core.hooksPath is unset when it points at the package's hooks and
# left alone when it is anything else.
test_ac_v9_07_hooks_path() {
	project
	assert_eq "$(git -C "$REPO" config --get core.hooksPath)" .softwary/hooks "core.hooksPath before"
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code"
	! git -C "$REPO" config --get core.hooksPath >/dev/null || fail "core.hooksPath is still set"
	assert_match "$OUT" "^removed core\.hooksPath \(\.softwary/hooks\)$"
	project
	git -C "$REPO" config core.hooksPath .githooks
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code with another hooks path"
	assert_eq "$(git -C "$REPO" config --get core.hooksPath)" .githooks "core.hooksPath"
}

# put_job JOB STATE: a job file in STATE.
put_job() {
	mkdir -p "$REPO/.softwary/state/jobs/$1"
	printf 'state=%s\nround=1\nstarted=%s\ntokens=0\n' "$2" "$(date +%s)" >"$REPO/.softwary/state/jobs/$1/job"
}

# AC-V9-07: an open run or a job that is not merged or abandoned is 1 and
# nothing is written, with or without --yes; a stopped run and finished jobs do not stop it.
test_ac_v9_07_refuses_with_a_run_or_a_job() {
	project
	open_run
	snapshot >"$T/before"
	for flag in --yes ""; do
		# shellcheck disable=SC2086 # no flag is no argument
		sw uninstall $flag
		assert_eq "$RC" 1 "exit code with a run ($flag)"
		assert_contains "$OUT" "uninstall: a run is open (./softwary run stop)"
		snapshot >"$T/after"
		assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths with a run ($flag)"
	done
	printf 'started=1\ntokens=0\nstopped=2\n' >"$REPO/.softwary/state/run"
	put_job 001-S1 merged
	put_job 001-S2 abandoned
	put_job 001-S3 escalated
	snapshot >"$T/before"
	sw uninstall --yes
	assert_eq "$RC" 1 "exit code with an escalated job"
	assert_contains "$OUT" "uninstall: job 001-S3 is escalated; finish or abandon it first"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths with a job"
	put_job 001-S3 implementing
	sw uninstall
	assert_eq "$RC" 1 "exit code with an implementing job and no --yes"
	put_job 001-S3 merged
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code with only finished jobs and a stopped run"
	[ -f "$REPO/.softwary/state/jobs/001-S3/job" ] || fail "the job state was removed"
	[ ! -e "$REPO/softwary" ] || fail "the wrapper is still there"
}

# AC-V9-07: a softwary file that is not the package's wrapper is the project's
# own: it stays, with a line; the rest of the package goes.
test_ac_v9_07_foreign_wrapper_stays() {
	project
	rm -f "${REPO:?}/softwary"
	printf '#!/bin/sh\n# the project own script\n' >"$REPO/softwary"
	RC=0
	(cd "$REPO" && sh .softwary/bin/softwary uninstall --yes) >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^kept softwary \(not softwary's wrapper\)$"
	assert_contains "$REPO/softwary" "the project own script"
	[ ! -e "$REPO/.softwary/bin" ] || fail "the package is still there"
}

# AC-V9-07: uninstall and then install again: sync is clean and the project's
# own text in AGENTS.md is still there once; the configuration was kept.
test_ac_v9_07_reinstall_syncs_clean() {
	project
	cp "$REPO/.softwary/config/tools.conf" "$T/tools.conf"
	sw uninstall --yes
	assert_eq "$RC" 0 "exit code"
	sh "$PKG_ROOT/install.sh" "$REPO" >"$OUT" 2>&1 || fail "install failed"
	assert_contains "$OUT" ".softwary/config/tools.conf (exists, kept)"
	cmp -s "$T/tools.conf" "$REPO/.softwary/config/tools.conf" || fail "tools.conf changed"
	sw sync
	assert_eq "$RC" 0 "sync exit code"
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
	assert_eq "$(grep -c 'Build with make' "$REPO/AGENTS.md")" 1 "the project's text in AGENTS.md"
	assert_eq "$(grep -c '^<!-- softwary:begin' "$REPO/AGENTS.md")" 1 "blocks in AGENTS.md"
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
}

# AC-V9-07: an unknown option or argument is 2 and writes nothing.
test_ac_v9_07_usage() {
	project
	snapshot >"$T/before"
	for a in --nope extra "--yes extra"; do
		# shellcheck disable=SC2086 # the arguments are split on purpose
		sw uninstall $a
		assert_eq "$RC" 2 "exit code of uninstall $a"
		assert_contains "$OUT" "usage: ./softwary uninstall [--yes]"
	done
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths"
}

run_tests "$0"
