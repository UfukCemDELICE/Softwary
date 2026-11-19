#!/bin/sh
# Tests for tools/release.sh (V9): the release archive of the package.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# rel: runs release.sh <version> in the fixture repository $FX (RC, OUT).
rel() {
	RC=0
	(cd "$FX" && sh tools/release.sh "$@") >"$OUT" 2>&1 || RC=$?
}

# refused: release.sh was refused with 1, with TEXT, and wrote nothing: no
# dist/ and no tag.
refused() {
	assert_eq "$RC" 1 "exit code: $1"
	assert_contains "$OUT" "$1"
	[ ! -e "$FX/dist" ] || fail "dist/ was written despite: $1"
	assert_eq "$(git -C "$FX" tag | wc -l | tr -d ' ')" 0 "tags"
}

# AC-V9-05: the version, the changelog and the working tree are each checked,
# and a refusal is 1 and writes nothing.
test_ac_v9_05_refusals_write_nothing() {
	FX=$T/fx
	release_fixture "$FX" 0.1.0
	rel 0.2.0
	refused "VERSION is 0.1.0, not 0.2.0"
	rel 1.2
	refused "'1.2' is not a version (N.N.N)"
	rel 0.1.0.1
	refused "'0.1.0.1' is not a version (N.N.N)"
	printf '# Changelog\n\n## 0.0.9\n\n- Old.\n' >"$FX/CHANGELOG.md"
	git -C "$FX" -c user.name=t -c user.email=t@example.com commit -q -am "changelog without the version"
	rel 0.1.0
	refused "CHANGELOG.md has no '## 0.1.0' section"
	printf '# Changelog\n\n## 0.1.0\n\n\n## 0.0.9\n\n- Old.\n' >"$FX/CHANGELOG.md"
	git -C "$FX" -c user.name=t -c user.email=t@example.com commit -q -am "empty section"
	rel 0.1.0
	refused "the '## 0.1.0' section of CHANGELOG.md is empty"
	printf '# Changelog\n\n## 0.1.0\n\n- Something.\n' >"$FX/CHANGELOG.md"
	git -C "$FX" -c user.name=t -c user.email=t@example.com commit -q -am "fixed"
	printf 'edit\n' >>"$FX/README.md"
	rel 0.1.0
	refused "the working tree is not clean"
	git -C "$FX" checkout -q -- README.md
	printf 'new\n' >"$FX/untracked.txt"
	rel 0.1.0
	refused "the working tree is not clean"
	rm -f "${FX:?}/untracked.txt"
	rel
	assert_eq "$RC" 2 "no version"
	rel 0.1.0
	assert_eq "$RC" 0 "exit code once everything holds"
}

# AC-V9-05: the archive is softwary-<version>.tar.gz with the root directory
# softwary-<version>/, what the installation needs and the README, the LICENSE,
# the NOTICE
# and the CHANGELOG, not tests/ nor docs/; SHA256SUMS lists it and checks out.
test_ac_v9_05_archive_content_and_sums() {
	FX=$T/fx
	release_fixture "$FX" 0.1.0
	rel 0.1.0
	assert_eq "$RC" 0 "exit code"
	a=$FX/dist/softwary-0.1.0.tar.gz
	[ -f "$a" ] || fail "no archive"
	tar -tzf "$a" >"$T/list" || fail "the archive is not a tar.gz"
	assert_eq "$(sed 's#/.*##' "$T/list" | sort -u)" "softwary-0.1.0" "root directory"
	for f in install.sh VERSION README.md LICENSE NOTICE CHANGELOG.md src/bin/softwary src/lib/sync.sh src/templates/models.conf; do
		assert_contains "$T/list" "softwary-0.1.0/$f"
	done
	assert_no_match "$T/list" '^softwary-0\.1\.0/(tests|docs|tools|\.git)'
	assert_eq "$(wc -l <"$FX/dist/SHA256SUMS" | tr -d ' ')" 1 "lines of SHA256SUMS"
	assert_match "$FX/dist/SHA256SUMS" '^[0-9a-f]{64}  softwary-0\.1\.0\.tar\.gz$'
	(cd "$FX/dist" && sha256sum -c SHA256SUMS) >"$OUT" 2>&1 || fail "SHA256SUMS does not check out"
	assert_eq "$(tar -xzOf "$a" softwary-0.1.0/VERSION)" 0.1.0 "VERSION in the archive"
}

# AC-V9-05: two runs from the same commit make the same bytes, also when the
# files were touched in between; another commit makes another archive.
test_ac_v9_05_deterministic() {
	FX=$T/fx
	release_fixture "$FX" 0.1.0
	rel 0.1.0
	assert_eq "$RC" 0 "first run"
	first=$(sha256sum "$FX/dist/softwary-0.1.0.tar.gz" | cut -d' ' -f1)
	cp "$FX/dist/SHA256SUMS" "$T/sums1"
	rm -rf "${FX:?}/dist"
	sleep 1
	find "$FX/src" "$FX/install.sh" -type f -exec touch {} +
	rel 0.1.0
	assert_eq "$RC" 0 "second run"
	second=$(sha256sum "$FX/dist/softwary-0.1.0.tar.gz" | cut -d' ' -f1)
	assert_eq "$second" "$first" "digest of the second run"
	cmp -s "$T/sums1" "$FX/dist/SHA256SUMS" || fail "SHA256SUMS differ"
	rel 0.1.0
	assert_eq "$RC" 0 "a run over an existing dist/"
	assert_eq "$(sha256sum "$FX/dist/softwary-0.1.0.tar.gz" | cut -d' ' -f1)" "$first" "digest over an existing dist/"
	printf '\n# changed\n' >>"$FX/src/lib/sync.sh"
	git -C "$FX" -c user.name=t -c user.email=t@example.com commit -q -am "another commit"
	rel 0.1.0
	third=$(sha256sum "$FX/dist/softwary-0.1.0.tar.gz" | cut -d' ' -f1)
	[ "$third" != "$first" ] || fail "another commit made the same archive"
}

# AC-V9-05: it makes no tag, does not push, has no remote to push to and does
# not upload: the script does not even name the commands that would.
test_ac_v9_05_makes_no_tag_and_pushes_nothing() {
	FX=$T/fx
	release_fixture "$FX" 0.1.0
	rel 0.1.0
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(git -C "$FX" tag | wc -l | tr -d ' ')" 0 "tags"
	assert_eq "$(git -C "$FX" remote | wc -l | tr -d ' ')" 0 "remotes"
	assert_eq "$(git -C "$FX" status --porcelain | wc -l | tr -d ' ')" 0 "dist/ is ignored: the tree stays clean"
	for w in 'git tag' 'git push' 'curl' 'wget' 'gh ' 'release create'; do
		! grep -v '^[[:space:]]*#' "$PKG_ROOT/tools/release.sh" | grep -F -e "$w" >/dev/null || fail "tools/release.sh uses: $w"
	done
}

run_tests "$0"
