#!/bin/sh
# Runs TLC (the TLA+ model checker) on one configuration of docs/formal/ and
# prints its output; the exit code is TLC's (0 no error, 12 an invariant and 13 a
# temporal property is violated), or 2 when TLC cannot be had.
# Usage: sh tests/tlc.sh <config>   e.g. sh tests/tlc.sh docs/formal/merge.cfg
#        sh tests/tlc.sh --check    java and the jar are in order
# The specification is the .tla of the config's name up to its first '-'
# (merge-nogate.cfg -> merge.tla). The jar, its pinned SHA-256 and the way TLC
# is called are the package's (src/lib/formal.sh, the code of `softwary formal`):
# $SW_TLA2TOOLS or ~/.cache/softwary/tla2tools-1.8.0.jar, downloaded when it is
# not there.

root=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=src/lib/formal.sh
. "$root/src/lib/formal.sh"

die() {
	printf 'tlc: %s\n' "$*" >&2
	exit 2
}

command -v java >/dev/null 2>&1 || die "java is not installed (TLC needs a Java runtime; or set SW_SKIP_FORMAL=<reason>)"
jar=$(sw_formal_jar)
if [ ! -f "$jar" ]; then
	sw_formal_install >&2 || die "$jar is missing and could not be installed"
fi
[ "$(sw_formal_sha256 "$jar")" = "$SW_TLA_SHA256" ] || die "$jar is not tla2tools $SW_TLA_VERSION (SHA-256 $SW_TLA_SHA256)"
[ "${1-}" != --check ] || exit 0
[ $# -eq 1 ] && [ -f "$1" ] || die "usage: sh tests/tlc.sh <config> | --check"

cfg=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
spec=${cfg%.cfg}
spec=${spec%%-*}.tla
[ -f "$spec" ] || die "no specification $spec for $cfg"
log=$(mktemp "${TMPDIR:-/tmp}/softwary-tlc.XXXXXX") || exit 2
trap 'rm -f "$log"' EXIT
rc=0
sw_formal_tlc "$(dirname "$cfg")" "$(basename "$cfg")" "$(basename "$spec")" auto "$log" || rc=$?
cat "$log"
exit "$rc"
