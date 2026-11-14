# shellcheck shell=sh
# softwary: `upgrade` command. Sourced by bin/softwary. POSIX sh.
#
# Replaces the managed files with those of a package directory (a newer
# softwary checkout), removes managed files the new version no longer has,
# then runs `sync` with the new code. The package's install.sh decides what is
# managed. Exit: sync's exit code, or 2 for a bad path or version.

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

# sw_upgrade PACKAGE_PATH
sw_upgrade() {
	if [ $# -ne 1 ]; then
		printf 'usage: ./softwary upgrade <package-path>\n' >&2
		return 2
	fi
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
	# The files of this very command were just replaced: continue in the new code.
	exec sh "$SOFTWARY_ROOT/.softwary/bin/softwary" sync
}
