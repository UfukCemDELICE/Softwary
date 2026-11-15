# shellcheck shell=sh
# softwary: the `changes` gate. Sourced by bin/softwary. POSIX sh.
#
# Every change has a spec: when a path under src_paths changed since the base,
# the change must include a slice that is in progress, in review or done, of a
# spec that is approved or done.

# sw_src_paths_problems: prints one line per problem with src_paths in the
# loaded commands.conf (nothing when it is usable).
sw_src_paths_problems() {
	if ! sw_conf_has src_paths || [ -z "$(sw_conf_get src_paths)" ]; then
		printf 'not set in %s\n' "$SW_CONF_REL"
		return 0
	fi
	set -f
	# shellcheck disable=SC2046 # src_paths is a space-separated list of paths
	set -- $(sw_conf_get src_paths)
	set +f
	for _sp in "$@"; do
		case $_sp in
		/* | .. | ../* | */.. | */../*)
			printf "'%s' must be a path inside the repository\n" "$_sp"
			;;
		*)
			[ -e "$SOFTWARY_ROOT/$_sp" ] || printf "'%s' not found\n" "$_sp"
			;;
		esac
	done
}

# sw_changes_under PATH: true if PATH is one of src_paths or below one.
sw_changes_under() {
	for _sp in $_ch_paths; do
		_sp=${_sp%/}
		case $_sp in '' | .) return 0 ;; esac
		[ "$1" = "$_sp" ] && return 0
		case $1 in
		"$_sp"/*) return 0 ;;
		# git still quotes names with tabs, newlines or quotes: gate them too.
		\""$_sp"/*) return 0 ;;
		esac
	done
	return 1
}

# sw_changes_active_slice PATH: true if PATH is a slice file whose status is
# in-progress, review or done and whose spec is approved or done.
sw_changes_active_slice() {
	case $1 in specs/*/slices/*.md) ;; *) return 1 ;; esac
	[ -f "$SOFTWARY_ROOT/$1" ] || return 1
	sw_fm_read "$SOFTWARY_ROOT/$1"
	case $(sw_fm_get status) in in-progress | review | done) ;; *) return 1 ;; esac
	_csd=${1%/slices/*}
	[ -f "$SOFTWARY_ROOT/$_csd/spec.md" ] || return 1
	sw_fm_read "$SOFTWARY_ROOT/$_csd/spec.md"
	case $(sw_fm_get status) in approved | done) return 0 ;; esac
	return 1
}

sw_changes_usage() {
	printf 'usage: ./softwary changes [--base <ref>]\n' >&2
}

# sw_changes [--base REF]: exit 0 covered or nothing to cover, 1 not covered,
# 2 configuration or usage.
sw_changes() {
	_ch_base=main
	while [ $# -gt 0 ]; do
		case $1 in
		--base)
			[ $# -ge 2 ] || { sw_changes_usage; return 2; }
			_ch_base=$2
			shift 2
			;;
		*) sw_changes_usage; return 2 ;;
		esac
	done
	sw_conf_load "$SOFTWARY_ROOT/$SW_CONF_REL"
	if [ "$SW_CONF_FOUND" -eq 0 ]; then
		printf 'changes: %s not found; run install.sh or ./softwary doctor\n' "$SW_CONF_REL"
		return 2
	fi
	if [ -n "$SW_CONF_ERRORS" ]; then
		printf '%s' "$SW_CONF_ERRORS"
		return 2
	fi
	_ch_probs=$(sw_src_paths_problems)
	if [ -n "$_ch_probs" ]; then
		printf '%s\n' "$_ch_probs" | sed 's/^/changes: src_paths: /; s/^changes: src_paths: not set/changes: src_paths is not set/'
		return 2
	fi
	_ch_paths=$(sw_conf_get src_paths)
	sw_base_commit "$_ch_base" changes || return 2
	_ch_changed=$(sw_changed_since "$SW_BASE_COMMIT")

	_ch_gated='' _ch_cover=''
	set -f
	while IFS= read -r _p; do
		[ -n "$_p" ] || continue
		if [ -z "$_ch_cover" ] && sw_changes_active_slice "$_p"; then
			_ch_cover=$_p
		fi
		if sw_changes_under "$_p"; then
			_ch_gated="$_ch_gated$_p
"
		fi
	done <<CHANGED
$_ch_changed
CHANGED
	set +f

	if [ -z "$_ch_gated" ]; then
		printf 'changes: no changes under src_paths\n'
		return 0
	fi
	if [ -n "$_ch_cover" ]; then
		printf 'changes: covered by %s\n' "$_ch_cover"
		return 0
	fi
	printf '%s' "$_ch_gated" | sed 's/$/: no slice in this change covers it/'
	printf 'changes: %s path(s) under src_paths changed without an active slice of an approved spec\n' \
		"$(sw_count "$_ch_gated")"
	return 1
}
