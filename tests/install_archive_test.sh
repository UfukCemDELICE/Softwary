#!/bin/sh
# Tests for installing and upgrading from a release archive, and for
# ./softwary version (V9).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# tmp_clean: the tests give the scripts $T/tmp as TMPDIR; nothing may be left.
tmp_clean() {
	# shellcheck disable=SC2012 # the names are only counted and shown
	assert_eq "$(ls -A "$T/tmp" | wc -l | tr -d ' ')" 0 "files left in TMPDIR: $(ls -A "$T/tmp")"
}

# inst ARGS...: runs install.sh with the given arguments (RC, OUT); TMPDIR is $T/tmp.
inst() {
	mkdir -p "$T/tmp"
	RC=0
	TMPDIR=$T/tmp sh "$PKG_ROOT/install.sh" "$@" >"$OUT" 2>&1 || RC=$?
}

# target_repo: an empty directory with a file of the project's, to see that
# a refusal leaves everything as it was.
target_repo() {
	REPO=$T/repo
	mkdir -p "$REPO"
	printf 'mine\n' >"$REPO/README.txt"
}

# refused TEXT: the last run exited 2 with TEXT, wrote nothing to the target
# and left nothing in TMPDIR.
refused() {
	assert_eq "$RC" 2 "exit code: $1"
	assert_contains "$OUT" "$1"
	assert_eq "$(ls -A "$REPO")" "README.txt" "the target has changed"
	tmp_clean
}

# AC-V9-06: an archive with its SHA-256 installs what the package installs from
# a clone; the temporary directory is gone.
test_ac_v9_06_install_from_archive() {
	release_archive 0.1.0
	target_repo
	inst --archive "$ARCHIVE" --sha256 "$DIGEST" "$REPO"
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^softwary 0\.1\.0: installing into "
	assert_eq "$(cat "$REPO/.softwary/VERSION")" 0.1.0 "installed version"
	[ -x "$REPO/softwary" ] || fail "no wrapper"
	tmp_clean
	mkdir "$T/other"
	sh "$PKG_ROOT/install.sh" "$T/other" >"$T/other.out" 2>&1 || fail "install from a directory failed"
	(cd "$T/other" && find . -type f | sort) >"$T/list-dir"
	(cd "$REPO" && find . -type f ! -name README.txt | sort) >"$T/list-arc"
	diff "$T/list-dir" "$T/list-arc" >/dev/null || fail "the archive installs other files: $(diff "$T/list-dir" "$T/list-arc")"
	(cd "$REPO" && ./softwary version) >"$OUT" 2>&1 || fail "the installed softwary does not run"
	# the digest may be given in capitals and before the archive
	target_repo
	rm -rf "${REPO:?}/.softwary" "${REPO:?}/softwary"
	up=$(printf '%s' "$DIGEST" | tr 'a-f' 'A-F')
	inst --sha256 "$up" --archive "$ARCHIVE" "$REPO"
	assert_eq "$RC" 0 "exit code with the digest in capitals, first"
}

# AC-V9-06: --upgrade works with an archive too (it removes what the new
# version no longer has).
test_ac_v9_06_install_upgrade_from_archive() {
	release_archive 0.1.0
	target_repo
	inst --archive "$ARCHIVE" --sha256 "$DIGEST" "$REPO"
	assert_eq "$RC" 0 "install"
	printf 'old\n' >"$REPO/.softwary/rules/gone.md"
	inst --archive "$ARCHIVE" --sha256 "$DIGEST" "$REPO" --upgrade
	assert_eq "$RC" 0 "upgrade"
	assert_contains "$OUT" "removed .softwary/rules/gone.md"
	[ ! -e "$REPO/.softwary/rules/gone.md" ] || fail "the old file is still there"
	tmp_clean
}

# AC-V9-06: a wrong digest, no digest, a digest without an archive, a missing
# file and a file that is not a gzip tar are each 2 and write nothing.
test_ac_v9_06_refusals_digest_and_file() {
	release_archive 0.1.0
	target_repo
	wrong=$(printf '%s' "$DIGEST" | tr '0-9a-f' '1-9a-f0')
	inst --archive "$ARCHIVE" --sha256 "$wrong" "$REPO"
	refused "does not match"
	inst --archive "$ARCHIVE" "$REPO"
	refused "--archive needs --sha256"
	inst --sha256 "$DIGEST" "$REPO"
	refused "--sha256 is only for --archive"
	inst --archive "$T/nope.tar.gz" --sha256 "$DIGEST" "$REPO"
	refused "is not a file"
	printf 'plain text\n' >"$T/plain.tar.gz"
	d=$(sha256sum "$T/plain.tar.gz" | cut -d' ' -f1)
	inst --archive "$T/plain.tar.gz" --sha256 "$d" "$REPO"
	refused "is not a gzip tar archive"
	inst --archive "$ARCHIVE" --sha256 'not-hex' "$REPO"
	refused "is not a SHA-256"
	inst --archive "$ARCHIVE" --sha256 "$DIGEST" "$T/missing-dir"
	assert_eq "$RC" 2 "a target that does not exist"
	tmp_clean
}

# mk_archive NAME: packs $T/tree into $T/NAME (with the given tar options) and
# sets BAD (its path) and BADSUM.
mk_archive() {
	BAD=$T/$1
	shift
	(cd "$T/tree" && tar -czPf "$BAD" "$@") || fail "tar failed"
	BADSUM=$(sha256sum "$BAD" | cut -d' ' -f1)
}

# AC-V9-06: an archive that is not a softwary package, has two roots, a path
# with '..', an absolute path, a link or a root not called softwary-* is 2,
# writes nothing and leaves no temporary directory.
test_ac_v9_06_refusals_structure() {
	release_archive 0.1.0
	target_repo
	mkdir -p "$T/tree/softwary-1.0.0/src/bin"
	printf '1.0.0\n' >"$T/tree/softwary-1.0.0/VERSION"
	mk_archive notpkg.tar.gz softwary-1.0.0
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "is not a softwary package"
	printf '#!/bin/sh\n' >"$T/tree/softwary-1.0.0/install.sh"
	mk_archive nobin.tar.gz softwary-1.0.0
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "is not a softwary package"
	rm "$T/tree/softwary-1.0.0/install.sh"
	printf '#!/bin/sh\n' >"$T/tree/softwary-1.0.0/src/bin/softwary"
	mk_archive noinstall.tar.gz softwary-1.0.0
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "is not a softwary package"
	rm "$T/tree/softwary-1.0.0/VERSION"
	printf '#!/bin/sh\n' >"$T/tree/softwary-1.0.0/install.sh"
	mk_archive noversion.tar.gz softwary-1.0.0
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "is not a softwary package"
	printf '1.0.0\n' >"$T/tree/softwary-1.0.0/VERSION"
	mkdir "$T/tree/other-1.0.0"
	printf 'x\n' >"$T/tree/other-1.0.0/file"
	mk_archive tworoots.tar.gz softwary-1.0.0 other-1.0.0
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "must have exactly one root directory"
	mk_archive badroot.tar.gz other-1.0.0
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "the root directory must be called softwary-"
	printf 'x\n' >"$T/tree/outside"
	mk_archive dotdot.tar.gz softwary-1.0.0 softwary-1.0.0/../outside
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "has a path that leaves the directory"
	mk_archive absolute.tar.gz softwary-1.0.0 "$T/tree/outside"
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "has a path that leaves the directory"
	ln -s /etc "$T/tree/softwary-1.0.0/link"
	mk_archive link.tar.gz softwary-1.0.0
	inst --archive "$BAD" --sha256 "$BADSUM" "$REPO"
	refused "has a link"
	[ ! -e "$T/outside" ] || fail "something was extracted outside"
}

# AC-V9-06: `upgrade <archive> --sha256 <digest>` upgrades with the same check
# and the same unpacking; the directory path still works.
test_ac_v9_06_upgrade_from_archive() {
	setup_repo
	cur=$(cat "$REPO/.softwary/VERSION")
	release_archive 0.9.0
	mkdir -p "$T/tmp"
	RC=0
	(cd "$REPO" && TMPDIR=$T/tmp ./softwary upgrade "$ARCHIVE" --sha256 "$DIGEST") >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(head -n 1 "$OUT")" "upgrade: $cur -> 0.9.0" "first line"
	assert_eq "$(cat "$REPO/.softwary/VERSION")" 0.9.0 "installed version"
	tmp_clean
	sw sync --check
	assert_eq "$RC" 0 "sync --check exit code"
	RC=0
	(cd "$REPO" && TMPDIR=$T/tmp ./softwary upgrade "$ARCHIVE" --sha256 "$DIGEST") >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 0 "the same archive again"
	assert_eq "$(head -n 1 "$OUT")" "upgrade: 0.9.0 -> 0.9.0" "first line of the second run"
	sw upgrade "$PKG_ROOT"
	assert_eq "$RC" 2 "a directory that is older"
	assert_contains "$OUT" "older than the installed"
}

# AC-V9-06: an upgrade that is refused writes nothing: a wrong digest, no
# digest, a digest given with a directory, an archive of an older version; each
# is refused for its own reason (the installed version is older than the
# archive's, so that the version is not what refuses).
test_ac_v9_06_upgrade_refusals() {
	setup_repo
	release_archive 0.9.0
	printf '0.0.1\n' >"$REPO/.softwary/VERSION"
	snapshot >"$T/before"
	mkdir -p "$T/tmp"
	wrong=$(printf '%s' "$DIGEST" | tr '0-9a-f' '1-9a-f0')
	for case in "does not match|$ARCHIVE --sha256 $wrong" "an archive needs --sha256|$ARCHIVE" "--sha256 is only for an archive|$PKG_ROOT --sha256 $DIGEST" \
		"usage: ./softwary upgrade|--sha256 $DIGEST" "is not a SHA-256 digest|$ARCHIVE --sha256 abc"; do
		want=${case%%|*}
		args=${case#*|}
		RC=0
		# shellcheck disable=SC2086 # the arguments are split on purpose
		(cd "$REPO" && TMPDIR=$T/tmp ./softwary upgrade $args) >"$OUT" 2>&1 || RC=$?
		assert_eq "$RC" 2 "exit code of upgrade $args"
		assert_contains "$OUT" "$want"
		tmp_clean
	done
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths"
	printf '0.9.0\n' >"$REPO/.softwary/VERSION"
	release_archive 0.2.0
	snapshot >"$T/before"
	RC=0
	(cd "$REPO" && TMPDIR=$T/tmp ./softwary upgrade "$ARCHIVE" --sha256 "$DIGEST") >"$OUT" 2>&1 || RC=$?
	assert_eq "$RC" 2 "an older archive"
	assert_contains "$OUT" "0.2.0 is older than the installed 0.9.0"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths after the older archive"
	tmp_clean
}

# AC-V9-08: `version` prints the installed version and is in help.
test_ac_v9_08_version() {
	setup_repo
	sw version
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(cat "$OUT")" "softwary $(cat "$PKG_ROOT/VERSION")" "output"
	printf '3.4.5\n' >"$REPO/.softwary/VERSION"
	sw version
	assert_eq "$(cat "$OUT")" "softwary 3.4.5" "output of another version"
	sw help
	assert_match "$OUT" '^  version +'
	sw version extra
	assert_eq "$RC" 2 "an argument"
	assert_eq "$(sh "$PKG_ROOT/src/bin/softwary" version)" "softwary $(cat "$PKG_ROOT/VERSION")" "from the package source"
}

# AC-V9-11: the package is 0.1.0; an installation of 0.0.0 (V8) upgrades to it,
# and a downgrade from it is refused.
test_ac_v9_11_version_0_1_0() {
	assert_eq "$(cat "$PKG_ROOT/VERSION")" 0.1.0 "VERSION"
	setup_repo
	printf '0.0.0\n' >"$REPO/.softwary/VERSION"
	sw upgrade "$PKG_ROOT"
	assert_eq "$RC" 0 "exit code"
	assert_eq "$(head -n 1 "$OUT")" "upgrade: 0.0.0 -> 0.1.0" "first line"
	assert_eq "$(cat "$REPO/.softwary/VERSION")" 0.1.0 "installed version"
	mkdir "$T/old"
	cp -R "$PKG_ROOT/install.sh" "$PKG_ROOT/VERSION" "$PKG_ROOT/src" "$T/old/"
	printf '0.0.0\n' >"$T/old/VERSION"
	snapshot >"$T/before"
	sw upgrade "$T/old"
	assert_eq "$RC" 2 "downgrade"
	assert_contains "$OUT" "0.0.0 is older than the installed 0.1.0; downgrading is not supported"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "changed paths"
}

run_tests "$0"
