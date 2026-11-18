#!/bin/sh
# Tests for the user documentation (V9): README.md, LICENSE, CHANGELOG.md and
# docs/guide/, in English.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

GUIDE="install quickstart commands concepts tools"

# user_docs: the user documentation files, repo-relative, one per line.
user_docs() {
	printf 'README.md\nCHANGELOG.md\n'
	for g in $GUIDE; do printf 'docs/guide/%s.md\n' "$g"; done
}

# help_commands: the commands that `help` lists, one per line.
help_commands() {
	sh "$PKG_ROOT/src/bin/softwary" help | awk '/^commands:/ { on = 1; next } on && /^  [a-z]/ { print $1 }' | sort -u
}

# commands_in FILE: the commands the file names as ./softwary <command>, one per line.
commands_in() {
	awk '{
		s = $0
		while ((i = index(s, "./softwary ")) > 0) {
			s = substr(s, i + 11)
			split(s, w, /[^a-z-]/)
			if (w[1] != "") print w[1]
		}
	}' "$1" | sort -u
}

# AC-V9-10: the files are there and are not empty; the license is MIT, 2026, by
# Ufuk Cem Delice; the changelog has a section for 0.1.0 that is not empty.
test_ac_v9_10_files_license_changelog() {
	for f in README.md LICENSE CHANGELOG.md $(for g in $GUIDE; do printf 'docs/guide/%s.md ' "$g"; done); do
		[ -s "$PKG_ROOT/$f" ] || fail "$f is missing or empty"
	done
	assert_eq "$(sed -n 1p "$PKG_ROOT/LICENSE")" "MIT License" "first line of LICENSE"
	assert_contains "$PKG_ROOT/LICENSE" "Copyright (c) 2026 Ufuk Cem Delice"
	assert_contains "$PKG_ROOT/LICENSE" "Permission is hereby granted, free of charge, to any person obtaining a copy"
	assert_contains "$PKG_ROOT/LICENSE" "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND"
	assert_match "$PKG_ROOT/CHANGELOG.md" '^## 0\.1\.0( - [0-9]{4}-[0-9]{2}-[0-9]{2})?$'
	assert_eq "$(awk '/^## / { on = ($2 == "0.1.0"); next } on && /[^[:space:]]/ { n++ } END { print n + 0 }' "$PKG_ROOT/CHANGELOG.md" | awk '{ print ($1 > 5) ? "yes" : "no" }')" yes "lines under ## 0.1.0"
	assert_contains "$PKG_ROOT/README.md" "MIT"
	assert_contains "$PKG_ROOT/README.md" "[LICENSE](LICENSE)"
	for g in $GUIDE; do
		assert_contains "$PKG_ROOT/README.md" "docs/guide/$g.md"
	done
	assert_eq "$(cat "$PKG_ROOT/VERSION")" 0.1.0 "VERSION"
	# the documentation of the tools names the three tools and the model line
	for w in "Claude Code" "Cursor" "Codex" "cursor: opus = " "codex: sonnet = " "models.conf"; do
		assert_contains "$PKG_ROOT/docs/guide/tools.md" "$w"
	done
	assert_contains "$PKG_ROOT/docs/guide/install.md" "--archive"
	assert_contains "$PKG_ROOT/docs/guide/install.md" "./softwary uninstall"
}

# AC-V9-10: commands.md names every command of help and no command that help
# does not list.
test_ac_v9_10_commands_md_matches_help() {
	f=$PKG_ROOT/docs/guide/commands.md
	known=$(help_commands)
	[ -n "$known" ] || fail "could not read the command list from help"
	for c in $known; do
		grep -F -e "./softwary $c" "$f" >/dev/null || fail "commands.md does not name ./softwary $c"
	done
	used=$(commands_in "$f")
	[ -n "$used" ] || fail "commands.md names no command"
	for c in $used; do
		printf '%s\nhelp\n' "$known" | grep -Fqx -e "$c" || fail "commands.md names ./softwary $c, which help does not list"
	done
	# the other pages too
	for d in $(user_docs); do
		commands_in "$PKG_ROOT/$d" >"$T/used"
		while read -r c; do
			printf '%s\nhelp\n' "$known" | grep -Fqx -e "$c" || fail "$d names ./softwary $c, which help does not list"
		done <"$T/used"
	done
}

# AC-V9-10: every relative link of the documents goes to a file that exists
# (the part after # is not checked), and there is at least one.
test_ac_v9_10_relative_links_resolve() {
	total=0
	for d in $(user_docs); do
		dir=$(dirname "$PKG_ROOT/$d")
		links=$(grep -o ']([^)]*)' "$PKG_ROOT/$d" | sed 's/^](//; s/)$//' | grep -Ev '^(https?:|mailto:|#)' || :)
		for l in $links; do
			path=${l%%#*}
			[ -n "$path" ] || continue
			total=$((total + 1))
			[ -e "$dir/$path" ] || fail "$d links to $l, which is not there"
		done
	done
	[ "$total" -ge 10 ] || fail "only $total relative links found"
	# the check sees a broken link
	printf '[x](nope.md) [y](docs_test.sh)\n' >"$T/sample.md"
	bad=$(grep -o ']([^)]*)' "$T/sample.md" | sed 's/^](//; s/)$//' | while read -r l; do [ -e "$PKG_ROOT/tests/$l" ] || printf '%s\n' "$l"; done)
	assert_eq "$bad" "nope.md" "a broken link"
}

# AC-V9-10: the documents name no stack (the word list of AC-M0-09, without
# 'java': the model checker's runtime is named on purpose).
test_ac_v9_10_no_stack_specific_words() {
	words='npm|npx|yarn|pnpm|node\.js|nodejs|deno|bun|python|python3|pip|poetry|pytest|ruby|gem|bundler|rake|cargo|rustc|golang|javac|maven|mvn|gradle|kotlin|dotnet|nuget|php|composer|swift|make|cmake|docker|django|rails|react|spring'
	for d in $(user_docs); do
		hits=$(grep -n -i -w -E "$words" "$PKG_ROOT/$d" || :)
		[ -z "$hits" ] || fail "$d names a stack: $hits"
	done
	printf 'Run make or npm test.\n' >"$T/sample.md"
	grep -i -w -E "$words" "$T/sample.md" >/dev/null || fail "the word list does not catch a sample"
}

# AC-V9-10: the documents are in English: none of them carries a character or a
# word that only the Turkish record has.
test_ac_v9_10_in_english() {
	for d in $(user_docs) LICENSE; do
		hits=$(grep -n -E '[çğıöşüÇĞİÖŞÜ]|\b(ve|için|veya|olarak|değil|yapıtlar|kilometre)\b' "$PKG_ROOT/$d" || :)
		[ -z "$hits" ] || fail "$d is not in English: $hits"
	done
}

# AC-V9-09, AC-V9-10: the README says there is no telemetry and where the
# network is used.
test_ac_v9_10_readme_telemetry() {
	f=$PKG_ROOT/README.md
	assert_contains "$f" "softwary has no telemetry"
	assert_contains "$f" "\`git\`"
	assert_contains "$f" "\`gh\`"
	assert_contains "$f" "./softwary formal install"
	assert_contains "$f" "semantic versioning"
}

run_tests "$0"
