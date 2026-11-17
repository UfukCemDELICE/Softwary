#!/bin/sh
# Runs TLC (the TLA+ model checker) on one configuration of docs/formal/ and
# prints its output; the exit code is TLC's (0 no error, 12 an invariant and 13 a
# temporal property is violated), or 2 when TLC cannot be had.
# Usage: sh tests/tlc.sh <config>   e.g. sh tests/tlc.sh docs/formal/merge.cfg
#        sh tests/tlc.sh --check    java and the jar are in order
# The specification is the .tla of the config's name up to its first '-'
# (merge-nogate.cfg -> merge.tla). The jar is tla2tools 1.8.0, from
# $SW_TLA2TOOLS or ~/.cache/softwary/tla2tools-1.8.0.jar; it is downloaded when
# it is not there and its SHA-256 must be the one below. TLC is a development
# dependency of this repository; the package does not need it.

version=1.8.0
sha256=7e53aa636dac8a3cb0533f343115c0548e03fc0ce5edc7739becf58d3d0fb84f
url=https://github.com/tlaplus/tlaplus/releases/download/v$version/tla2tools.jar
jar=${SW_TLA2TOOLS:-$HOME/.cache/softwary/tla2tools-$version.jar}

die() {
	printf 'tlc: %s\n' "$*" >&2
	exit 2
}

digest() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

command -v java >/dev/null 2>&1 || die "java is not installed (TLC needs a Java runtime; or set SW_SKIP_FORMAL=<reason>)"
if [ ! -f "$jar" ]; then
	mkdir -p "$(dirname "$jar")" || die "cannot make $(dirname "$jar")"
	command -v curl >/dev/null 2>&1 || die "$jar is missing and curl is not installed"
	curl -fsSL -o "$jar.part" "$url" || die "could not download $url"
	mv "$jar.part" "$jar"
fi
[ "$(digest "$jar")" = "$sha256" ] || die "$jar is not tla2tools $version (SHA-256 $sha256)"
[ "${1-}" != --check ] || exit 0
[ $# -eq 1 ] && [ -f "$1" ] || die "usage: sh tests/tlc.sh <config> | --check"

cfg=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
spec=${cfg%.cfg}
spec=${spec%%-*}.tla
[ -f "$spec" ] || die "no specification $spec for $cfg"
work=$(mktemp -d "${TMPDIR:-/tmp}/softwary-tlc.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
cp "$spec" "$cfg" "$work/"
cd "$work" || exit 2
java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -config "$(basename "$cfg")" -metadir "$work/states" "$(basename "$spec")" 2>&1
