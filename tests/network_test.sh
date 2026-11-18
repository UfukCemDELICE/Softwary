#!/bin/sh
# Tests that the package does not reach the network except where it is known
# to (V9): no telemetry.
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# NET_ALLOW: the places of src/ and install.sh where a line may name a network
# tool or an address, as <file>:<function> (empty function: outside a function).
# git, gh and the download of formal install are the package's whole reach;
# the two CALM models name a schema in "$schema", which nothing fetches.
NET_ALLOW='src/lib/formal.sh:
src/lib/formal.sh:sw_formal_install
src/templates/artifacts/system.calm.json:
src/eval/sample/architecture/model/system.calm.json:'

# net_hits ROOT: the lines of ROOT/src and ROOT/install.sh outside comments that
# use curl, wget, nc, ncat, /dev/tcp or /dev/udp or an http(s):// address, as
# <file>:<function>:<line>: <text>. A function runs from its `name() {` line to
# the `}` in column one.
net_hits() {
	(
		cd "$1" || exit 1
		{ find src -type f; printf 'install.sh\n'; } | sort | while IFS= read -r f; do
			awk -v f="$f" '
				/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $0; sub(/\(.*/, "", fn) }
				/^[ \t]*#/ { next }
				/(^|[^A-Za-z0-9_.-])(curl|wget|ncat|nc)([^A-Za-z0-9_-]|$)|\/dev\/(tcp|udp)|https?:\/\// { print f ":" fn ":" NR ": " $0 }
				/^}/ { fn = "" }' "$f"
		done
	)
}

# net_unlisted ROOT: the hits of net_hits that NET_ALLOW does not cover.
net_unlisted() {
	net_hits "$1" | while IFS= read -r line; do
		key=${line%%: *}
		key=${key%:*}
		printf '%s\n' "$NET_ALLOW" | grep -Fqx -e "$key" || printf '%s\n' "$line"
	done
}

# AC-V9-09: every line of src/ and install.sh that can reach the network is one
# of the known places; the known places are really there (the list is not stale).
test_ac_v9_09_no_unknown_network_use() {
	unlisted=$(net_unlisted "$PKG_ROOT")
	assert_eq "$unlisted" "" "network use outside the allowed places"
	hits=$(net_hits "$PKG_ROOT")
	printf '%s\n' "$hits" | grep -q '^src/lib/formal.sh:sw_formal_install:' || fail "the download of formal install is not where the list says"
	printf '%s\n' "$hits" | grep -q '^src/lib/formal.sh::' || fail "the address constant of formal.sh is not where the list says"
}

# AC-V9-09: the check catches what it is for: one line with each tool, added to
# a copy of the package, is found (the file and function are named).
test_ac_v9_09_the_check_catches_a_new_call() {
	mkdir "$T/pkg"
	cp -R "$PKG_ROOT/install.sh" "$PKG_ROOT/src" "$T/pkg/"
	assert_eq "$(net_unlisted "$T/pkg")" "" "a clean copy"
	for call in 'curl -s example.invalid' 'wget -q example.invalid' 'nc example.invalid 80' 'ncat example.invalid 80' 'exec 3<>/dev/tcp/example.invalid/80' 'ping=https://example.invalid/x' 'x=http://example.invalid/x'; do
		cp "$PKG_ROOT/src/lib/doctor.sh" "$T/pkg/src/lib/doctor.sh"
		printf '\nsw_added() {\n\t%s\n}\n' "$call" >>"$T/pkg/src/lib/doctor.sh"
		found=$(net_unlisted "$T/pkg")
		printf '%s\n' "$found" | grep -q '^src/lib/doctor.sh:sw_added:' || fail "not found: $call"
	done
	cp "$PKG_ROOT/src/lib/doctor.sh" "$T/pkg/src/lib/doctor.sh"
	printf '# curl is only named in this comment\n' >>"$T/pkg/src/lib/doctor.sh"
	assert_eq "$(net_unlisted "$T/pkg")" "" "a comment"
	printf '\njq -nc --arg x y "{}"\n' >>"$T/pkg/src/lib/doctor.sh"
	assert_eq "$(net_unlisted "$T/pkg")" "" "jq -nc is not nc"
	cp "$PKG_ROOT/install.sh" "$T/pkg/install.sh"
	printf 'curl -s example.invalid\n' >>"$T/pkg/install.sh"
	printf '%s\n' "$(net_unlisted "$T/pkg")" | grep -q '^install.sh::' || fail "install.sh is not checked"
	cp "$PKG_ROOT/install.sh" "$T/pkg/install.sh"
	cp "$PKG_ROOT/src/lib/formal.sh" "$T/pkg/src/lib/formal.sh"
	printf '\nsw_formal_other() {\n\tcurl -s example.invalid\n}\n' >>"$T/pkg/src/lib/formal.sh"
	printf '%s\n' "$(net_unlisted "$T/pkg")" | grep -q '^src/lib/formal.sh:sw_formal_other:' || fail "another function of formal.sh is allowed"
}

run_tests "$0"
