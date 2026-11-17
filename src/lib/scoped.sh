# shellcheck shell=sh
# softwary: scoped checks (V6). Sourced by bin/softwary. POSIX sh.
#
# A check that fails and is waived does not fail verify (waivers.sh), but then
# the loop is blind to what it breaks. `<key>_files` in commands.conf is the
# same check on the files of the change only: a command with a {files}
# placeholder, or `NONE: <reason>`. verify runs it, after the WAIVED line of a
# waived and red check, on the files the change touches under src_paths and
# test_paths; it must pass there.

SW_SCOPED_PLACEHOLDER='{files}'

# verify's base for the scoped checks: a commit, or empty when there is none
# (--base was not given, or --fast has no integration branch to compare with).
SW_SCOPED_COMMIT=

# sw_scoped_problems: one "commands.conf:LINE: ..." line per `<key>_files`
# whose command has no {files} (nothing when they are all usable). UNSET and
# NONE: <reason> are usable.
sw_scoped_problems() {
	for _sc_k in $SW_VERIFY_KEYS; do
		sw_conf_has "${_sc_k}_files" || continue
		_sc_v=$(sw_conf_get "${_sc_k}_files")
		case $_sc_v in UNSET | NONE | NONE:*) continue ;; esac
		case $_sc_v in
		*"$SW_SCOPED_PLACEHOLDER"*) ;;
		*) printf '%s:%s: %s_files must contain %s (or be NONE: <reason>)\n' \
			"$SW_CONF_REL" "$(sw_conf_line "${_sc_k}_files")" "$_sc_k" "$SW_SCOPED_PLACEHOLDER" ;;
		esac
	done
}

# sw_scoped_missing: the keys that have a waiver and no usable `<key>_files`
# (absent or UNSET), one per line. Loads the waivers.
sw_scoped_missing() {
	sw_waivers_load
	for _sm_k in $SW_WAIVERS; do
		if sw_conf_is_unset "${_sm_k}_files"; then printf '%s\n' "$_sm_k"; fi
	done
	return 0
}

# sw_scoped_changed COMMIT: the paths changed since COMMIT (committed,
# uncommitted and untracked), sorted and unique: the set `adr` and `changes`
# use, listed with NUL separators so that a name with a tab or a quote stays
# one name.
sw_scoped_changed() {
	(cd "$SOFTWARY_ROOT" && {
		git diff -z --no-renames --name-only "$1" --
		git ls-files -z --others --exclude-standard
	} | tr '\0' '\n' | LC_ALL=C sort -u)
}

# sw_scoped_under PATH DIRS: true if PATH is one of DIRS or below one.
sw_scoped_under() {
	for _su_d in $2; do
		_su_d=${_su_d%/}
		case $_su_d in '' | .) return 0 ;; esac
		[ "$1" = "$_su_d" ] && return 0
		case $1 in "$_su_d"/*) return 0 ;; esac
	done
	return 1
}

# sw_scoped_files COMMIT: the files the change since COMMIT touches under
# src_paths and test_paths that are in the working tree, one per line.
sw_scoped_files() {
	_sf_dirs=
	! sw_conf_has src_paths || _sf_dirs=$(sw_conf_get src_paths)
	! sw_conf_has test_paths || _sf_dirs="$_sf_dirs $(sw_conf_get test_paths)"
	_sf_all=$(sw_scoped_changed "$1")
	set -f
	while IFS= read -r _sf_p; do
		[ -n "$_sf_p" ] && [ -f "$SOFTWARY_ROOT/$_sf_p" ] || continue
		if sw_scoped_under "$_sf_p" "$_sf_dirs"; then printf '%s\n' "$_sf_p"; fi
	done <<SCOPED_FILES
$_sf_all
SCOPED_FILES
	set +f
	return 0
}

# sw_scoped_list FILES: FILES (one path per line) as arguments of a shell
# command: each in single quotes, a leading '-' made harmless as './-', joined
# by blanks.
sw_scoped_list() {
	printf '%s\n' "$1" | while IFS= read -r _sl_p; do
		[ -n "$_sl_p" ] || continue
		case $_sl_p in -*) _sl_p=./$_sl_p ;; esac
		printf "'%s' " "$(printf '%s' "$_sl_p" | sed "s/'/'\\\\''/g")"
	done | sed 's/ $//'
}

# sw_scoped_command CMD LIST: CMD with every {files} replaced by LIST.
sw_scoped_command() {
	_sk_rest=$1
	_sk_out=
	while :; do
		case $_sk_rest in
		*"$SW_SCOPED_PLACEHOLDER"*)
			_sk_out=$_sk_out${_sk_rest%%"$SW_SCOPED_PLACEHOLDER"*}$2
			_sk_rest=${_sk_rest#*"$SW_SCOPED_PLACEHOLDER"}
			;;
		*) break ;;
		esac
	done
	printf '%s%s' "$_sk_out" "$_sk_rest"
}

# sw_scoped_run KEY: reports `<key> (changed files)` for a check that is
# waived and red, and runs the scoped command (the counters and $_logdir are
# verify's).
sw_scoped_run() {
	_sr_key=$1
	_sr_name="$_sr_key (changed files)"
	if [ -z "$SW_SCOPED_COMMIT" ]; then
		sw_line "$_sr_name" "SKIP (no base)"
		_skip=$((_skip + 1))
		return 0
	fi
	if sw_conf_is_unset "${_sr_key}_files"; then
		sw_line "$_sr_name" "SKIP (${_sr_key}_files is not set)"
		_skip=$((_skip + 1))
		return 0
	fi
	_sr_val=$(sw_conf_get "${_sr_key}_files")
	case $_sr_val in
	NONE | NONE:*)
		sw_line "$_sr_name" "SKIP ($(sw_none_reason "$_sr_val"))"
		_skip=$((_skip + 1))
		return 0
		;;
	esac
	_sr_files=$(sw_scoped_files "$SW_SCOPED_COMMIT")
	if [ -z "$_sr_files" ]; then
		sw_line "$_sr_name" "SKIP (no changed files)"
		_skip=$((_skip + 1))
		return 0
	fi
	_sr_cmd=$(sw_scoped_command "$_sr_val" "$(sw_scoped_list "$_sr_files")")
	# shellcheck disable=SC2154 # _logdir is verify's
	_sr_log=$_logdir/verify-${_sr_key}-files.log
	_sr_start=$(date +%s)
	_sr_rc=0
	(cd "$SOFTWARY_ROOT" && sh -c "$_sr_cmd") >"$_sr_log" 2>&1 </dev/null || _sr_rc=$?
	_sr_dur=$(($(date +%s) - _sr_start))
	if [ "$_sr_rc" -eq 0 ]; then
		sw_line "$_sr_name" "PASS (${_sr_dur}s)"
		_pass=$((_pass + 1))
	else
		sw_line "$_sr_name" "FAIL (${_sr_dur}s)"
		tail -n "$SW_TAIL_LINES" "$_sr_log" | sed 's/^/    /'
		printf '    log: .softwary/state/logs/verify-%s-files.log (exit %s)\n' "$_sr_key" "$_sr_rc"
		_failc=$((_failc + 1))
	fi
}
