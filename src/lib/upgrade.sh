# shellcheck shell=sh
# softwary: `upgrade` command. Sourced by bin/softwary. POSIX sh.
#
# Replaces the managed files with those of a package directory (a newer
# softwary checkout) or of a release archive (checked against its SHA-256 and
# unpacked into a temporary directory), removes managed files the new version
# no longer has, then runs `sync` with the new code. The package's install.sh
# decides what is managed. Exit: sync's exit code, or 2 for a bad path,
# archive, digest or version.

# sw_version_valid VERSION: N.N.N, digits only.
sw_version_valid() {
	printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# sw_version_cmp A B: prints -1, 0 or 1 comparing A with B field by field,
# numerically (0.10.0 is newer than 0.9.0).
sw_version_cmp() {
	awk -v a="$1" -v b="$2" 'BEGIN {
		split(a, x, "."); split(b, y, ".")
		for (i = 1; i <= 3; i++) {
			if (x[i] + 0 < y[i] + 0) { print -1; exit }
			if (x[i] + 0 > y[i] + 0) { print 1; exit }
		}
		print 0
	}'
}

# sw_version_cmd: `version`. The installed version is .softwary/VERSION; in a
# clone the package's own VERSION is next to src/.
sw_version_cmd() {
	if [ $# -ne 0 ]; then
		printf 'usage: ./softwary version\n' >&2
		return 2
	fi
	_vc_f=$SOFTWARY_HOME/VERSION
	[ -f "$_vc_f" ] || _vc_f=$SOFTWARY_HOME/../VERSION
	_vc_v=$(sw_trim "$(cat "$_vc_f" 2>/dev/null)")
	if ! sw_version_valid "$_vc_v"; then
		printf 'softwary: the version is not known (no valid VERSION file)\n' >&2
		return 2
	fi
	printf 'softwary %s\n' "$_vc_v"
}

# sw_upgrade PACKAGE_PATH | ARCHIVE --sha256 DIGEST
sw_upgrade() {
	_up_arg=
	_up_sha=
	while [ $# -gt 0 ]; do
		case $1 in
		--sha256)
			[ $# -ge 2 ] || break
			_up_sha=$2
			shift 2
			;;
		*)
			[ -z "$_up_arg" ] || break
			_up_arg=$1
			shift
			;;
		esac
	done
	if [ $# -ne 0 ] || [ -z "$_up_arg" ]; then
		printf 'usage: ./softwary upgrade <package-path>\n       ./softwary upgrade <archive.tar.gz> --sha256 <digest>\n' >&2
		return 2
	fi
	_up_work=
	if [ -f "$_up_arg" ]; then
		if [ -z "$_up_sha" ]; then
			printf 'upgrade: an archive needs --sha256 <digest> (the digest from SHA256SUMS)\n' >&2
			return 2
		fi
		_up_work=$(mktemp -d "${TMPDIR:-/tmp}/softwary-upgrade.XXXXXX") || return 2
		trap 'sw_lock_release_all; rm -rf "${_up_work:?}"' EXIT
		if ! sw_archive_unpack "$_up_arg" "$_up_sha" "$_up_work" upgrade; then
			rm -rf "${_up_work:?}"
			return 2
		fi
		_up_dir=$SW_ARCHIVE_PKG
	elif [ -n "$_up_sha" ]; then
		printf 'upgrade: --sha256 is only for an archive\n' >&2
		return 2
	else
		_up_dir=$_up_arg
	fi
	_up_rc=0
	sw_upgrade_dir "$_up_dir" || _up_rc=$?
	[ -z "$_up_work" ] || rm -rf "${_up_work:?}"
	[ "$_up_rc" -eq 0 ] || return "$_up_rc"
	# The files of this very command were just replaced: continue in the new code.
	exec sh "$SOFTWARY_ROOT/.softwary/bin/softwary" sync
}

# sw_upgrade_dir PACKAGE_PATH: checks the package and its version and installs
# it over the managed files; the caller then runs sync.
sw_upgrade_dir() {
	if [ ! -f "$1/VERSION" ] || [ ! -f "$1/install.sh" ] || [ ! -f "$1/src/bin/softwary" ]; then
		printf 'upgrade: %s is not a softwary package\n' "$1"
		return 2
	fi
	_up_pkg=$(cd "$1" && pwd -P) || return 2
	_up_new=$(sw_trim "$(cat "$_up_pkg/VERSION")")
	_up_old=$(sw_trim "$(cat "$SOFTWARY_ROOT/.softwary/VERSION" 2>/dev/null)")
	for _up_v in "$_up_new" "$_up_old"; do
		if ! sw_version_valid "$_up_v"; then
			printf "upgrade: invalid version '%s' (expected N.N.N)\n" "$_up_v"
			return 2
		fi
	done
	if [ "$(sw_version_cmp "$_up_new" "$_up_old")" -lt 0 ]; then
		printf 'upgrade: %s is older than the installed %s; downgrading is not supported\n' "$_up_new" "$_up_old"
		return 2
	fi
	printf 'upgrade: %s -> %s\n' "$_up_old" "$_up_new"
	if ! sh "$_up_pkg/install.sh" "$SOFTWARY_ROOT" --upgrade; then
		printf 'upgrade: installing the new files failed\n'
		return 2
	fi
	return 0
}
