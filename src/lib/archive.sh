# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_ARCHIVE_PKG is read by the callers
# softwary: unpacking a release archive. Sourced by install.sh (from the
# package it runs in) and by bin/softwary (`upgrade`). POSIX sh.
#
# A release archive is softwary-<version>.tar.gz made by tools/release.sh:
# one root directory softwary-<version>/ with the package in it. Nothing is
# unpacked before the SHA-256 the caller was given matches and the list of the
# archive is safe.

# sw_archive_sha256 FILE: prints the SHA-256 of FILE; 2 when no tool is installed.
sw_archive_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum <"$1" | awk '{ print $1 }'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 <"$1" | awk '{ print $1 }'
	else
		return 2
	fi
}

# sw_archive_unpack ARCHIVE DIGEST WORK PREFIX: checks ARCHIVE against DIGEST
# and its list of entries, unpacks it into WORK (an existing, empty directory)
# and sets SW_ARCHIVE_PKG to the package directory in it. Returns 0, or 2 after
# a "PREFIX: ..." line on stderr; WORK is the caller's to remove.
sw_archive_unpack() {
	_au_a=$1
	_au_p=$4
	if [ ! -f "$_au_a" ]; then
		printf '%s: %s is not a file\n' "$_au_p" "$_au_a" >&2
		return 2
	fi
	_au_d=$(printf '%s' "$2" | tr 'A-F' 'a-f')
	if ! printf '%s\n' "$_au_d" | grep -Eq '^[0-9a-f]{64}$'; then
		printf "%s: '%s' is not a SHA-256 digest (64 hexadecimal digits)\n" "$_au_p" "$2" >&2
		return 2
	fi
	_au_h=$(sw_archive_sha256 "$_au_a") || {
		printf '%s: neither sha256sum nor shasum is installed, so the archive cannot be checked\n' "$_au_p" >&2
		return 2
	}
	if [ "$_au_h" != "$_au_d" ]; then
		printf '%s: the SHA-256 of %s does not match (expected %s, got %s)\n' "$_au_p" "$_au_a" "$_au_d" "$_au_h" >&2
		return 2
	fi
	if ! tar -tzf "$_au_a" >"$3/list" 2>/dev/null; then
		printf '%s: %s is not a gzip tar archive\n' "$_au_p" "$_au_a" >&2
		return 2
	fi
	# Only files and directories, and only inside the directory it unpacks to.
	tar -tvzf "$_au_a" 2>/dev/null | cut -c1 | sort -u >"$3/types"
	if grep -Eqv '^[-d]$' "$3/types"; then
		printf '%s: %s has a link or a special file; refused\n' "$_au_p" "$_au_a" >&2
		return 2
	fi
	while IFS= read -r _au_n; do
		case /$_au_n/ in
		//* | */../*)
			printf '%s: %s has a path that leaves the directory: %s\n' "$_au_p" "$_au_a" "$_au_n" >&2
			return 2
			;;
		esac
	done <"$3/list"
	sed 's#/.*##' "$3/list" | sort -u >"$3/roots"
	if [ "$(wc -l <"$3/roots" | tr -d ' ')" -ne 1 ]; then
		printf '%s: %s must have exactly one root directory\n' "$_au_p" "$_au_a" >&2
		return 2
	fi
	_au_r=$(cat "$3/roots")
	case $_au_r in
	softwary-?*) ;;
	*)
		printf '%s: the root directory must be called softwary-<version> (it is %s)\n' "$_au_p" "$_au_r" >&2
		return 2
		;;
	esac
	mkdir "$3/pkg" || return 2
	if ! tar -xzf "$_au_a" -C "$3/pkg" 2>/dev/null; then
		printf '%s: %s could not be unpacked\n' "$_au_p" "$_au_a" >&2
		return 2
	fi
	SW_ARCHIVE_PKG=$3/pkg/$_au_r
	if [ ! -f "$SW_ARCHIVE_PKG/VERSION" ] || [ ! -f "$SW_ARCHIVE_PKG/install.sh" ] || [ ! -f "$SW_ARCHIVE_PKG/src/bin/softwary" ]; then
		printf '%s: %s is not a softwary package\n' "$_au_p" "$_au_a" >&2
		return 2
	fi
	return 0
}
