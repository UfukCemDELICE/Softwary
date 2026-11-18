#!/bin/sh
# Builds the release archive of softwary. A development tool of the package:
# it is not installed.
# Usage: sh tools/release.sh <version>
#
# Checks, writing nothing and exiting 1 if one fails:
#   - <version> is N.N.N and is what VERSION says;
#   - CHANGELOG.md has a '## <version>' heading with something under it;
#   - the working tree is clean.
# Then writes dist/softwary-<version>.tar.gz (root directory
# softwary-<version>/) and dist/SHA256SUMS. The archive is made from HEAD with
# git archive and gzip -n: the same commit gives the same bytes. It makes no
# tag, pushes nothing and uploads nothing: those are a person's.
set -eu

if [ $# -ne 1 ]; then
	printf 'usage: sh tools/release.sh <version>\n' >&2
	exit 2
fi
version=$1
root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$root"

die() {
	printf 'release: %s\n' "$1" >&2
	exit 1
}

# What the installation needs, and what a reader of the archive needs.
paths="install.sh VERSION src README.md LICENSE CHANGELOG.md"

printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "'$version' is not a version (N.N.N)"
[ -f VERSION ] || die "VERSION is missing"
have=$(tr -d '[:space:]' <VERSION)
[ "$have" = "$version" ] || die "VERSION is $have, not $version"
[ -f CHANGELOG.md ] || die "CHANGELOG.md is missing"
# The section of the version: from its '## <version>' heading to the next
# '## ' heading; it must hold a line that is not blank.
section=$(awk -v v="$version" '
	/^## / { if (on) exit; h = $2; gsub(/[][]/, "", h); if (h == v) { on = 1; found = 1 } next }
	on { print }
	END { if (!found) exit 3 }' CHANGELOG.md) || die "CHANGELOG.md has no '## $version' section"
printf '%s\n' "$section" | grep -q '[^[:space:]]' || die "the '## $version' section of CHANGELOG.md is empty"
git rev-parse --verify -q HEAD >/dev/null || die "this is not a git repository with a commit"
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean (commit or remove what git status shows)"

work=$(mktemp -d "${TMPDIR:-/tmp}/softwary-release.XXXXXX")
trap 'rm -rf "${work:?}"' EXIT
name=softwary-$version.tar.gz
# shellcheck disable=SC2086 # the paths are split on purpose
git -c tar.umask=0002 archive --format=tar --prefix="softwary-$version/" -o "$work/archive.tar" HEAD -- $paths ||
	die "git archive failed (is every one of: $paths committed?)"
gzip -n -9 <"$work/archive.tar" >"$work/$name" || die "gzip failed"
if command -v sha256sum >/dev/null 2>&1; then
	(cd "$work" && sha256sum "$name") >"$work/SHA256SUMS"
elif command -v shasum >/dev/null 2>&1; then
	(cd "$work" && shasum -a 256 "$name") >"$work/SHA256SUMS"
else
	die "neither sha256sum nor shasum is installed"
fi
mkdir -p dist
mv -f "$work/$name" "dist/$name"
mv -f "$work/SHA256SUMS" dist/SHA256SUMS
printf 'release: dist/%s\n' "$name"
printf 'release: dist/SHA256SUMS\n'
cat dist/SHA256SUMS
