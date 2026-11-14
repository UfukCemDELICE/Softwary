# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by verify.sh and doctor.sh
# softwary: commands.conf parsing. Sourced by bin/softwary. POSIX sh.
#
# Format: one `key = value` per line; blank lines and lines starting with '#'
# are ignored. A value is a shell command, UNSET, or `NONE: <reason>`.

SW_REQUIRED_KEYS="format_check lint typecheck test build security"
SW_OPTIONAL_CHECK_KEYS="contract_check arch_check"
SW_OTHER_KEYS="run deploy bootstrap"
SW_SETTING_KEYS="test_paths src_paths"
SW_VERIFY_KEYS="format_check lint typecheck test build contract_check arch_check security"
SW_FAST_KEYS="format_check lint typecheck"
SW_CONF_REL=.softwary/config/commands.conf

# sw_trim STRING: prints STRING without leading and trailing whitespace.
sw_trim() {
	_s=$1
	_s=${_s#"${_s%%[![:space:]]*}"}
	_s=${_s%"${_s##*[![:space:]]}"}
	printf '%s' "$_s"
}

# sw_in_list WORD LIST: true if WORD is one of the space-separated LIST.
sw_in_list() {
	case " $2 " in *" $1 "*) return 0 ;; esac
	return 1
}

sw_known_key() {
	sw_in_list "$1" "$SW_REQUIRED_KEYS $SW_OPTIONAL_CHECK_KEYS $SW_OTHER_KEYS $SW_SETTING_KEYS"
}

sw_conf_error() {
	SW_CONF_ERRORS="${SW_CONF_ERRORS}${SW_CONF_REL}:$1: $2
"
}

# sw_conf_load FILE: parses FILE. Sets SW_CONF_KEYS (keys in file order) and
# SW_CONF_ERRORS (one message per line, empty when the file is well-formed).
# Values are read with sw_conf_get, line numbers with sw_conf_line.
sw_conf_load() {
	SW_CONF_KEYS=
	SW_CONF_ERRORS=
	SW_CONF_FOUND=0
	[ -f "$1" ] || return 0
	SW_CONF_FOUND=1
	_n=0
	while IFS= read -r _line || [ -n "$_line" ]; do
		_n=$((_n + 1))
		_line=$(sw_trim "$_line")
		case $_line in '' | '#'*) continue ;; esac
		case $_line in
		*=*) ;;
		*)
			sw_conf_error "$_n" "malformed line: expected 'key = value'"
			continue
			;;
		esac
		_key=$(sw_trim "${_line%%=*}")
		_value=$(sw_trim "${_line#*=}")
		case $_key in
		'')
			sw_conf_error "$_n" "malformed line: missing key before '='"
			continue
			;;
		[!a-z]* | *[!a-z0-9_]*)
			sw_conf_error "$_n" "malformed line: invalid key '$_key' (use lowercase letters, digits, '_')"
			continue
			;;
		esac
		if [ -z "$_value" ]; then
			sw_conf_error "$_n" "malformed line: empty value for '$_key' (use a command, UNSET or 'NONE: <reason>')"
			continue
		fi
		case $_value in
		NONE | NONE:*)
			if [ -z "$(sw_none_reason "$_value")" ]; then
				sw_conf_error "$_n" "malformed line: '$_key' needs a reason: 'NONE: <reason>'"
				continue
			fi
			;;
		esac
		if sw_in_list "$_key" "$SW_CONF_KEYS"; then
			sw_conf_error "$_n" "malformed line: duplicate key '$_key' (first on line $(sw_conf_line "$_key"))"
			continue
		fi
		SW_CONF_KEYS="$SW_CONF_KEYS $_key"
		eval "SW_CONF_V_$_key=\$_value"
		eval "SW_CONF_L_$_key=\$_n"
	done <"$1"
}

# sw_none_reason VALUE: prints the reason of a `NONE: <reason>` value.
sw_none_reason() {
	_r=${1#NONE}
	_r=${_r#:}
	sw_trim "$_r"
}

sw_conf_has() {
	sw_in_list "$1" "$SW_CONF_KEYS"
}

sw_conf_get() {
	sw_conf_has "$1" || return 1
	eval "printf '%s' \"\$SW_CONF_V_$1\""
}

sw_conf_line() {
	eval "printf '%s' \"\${SW_CONF_L_$1-}\""
}

# sw_conf_is_unset KEY: true if KEY is absent or set to UNSET.
sw_conf_is_unset() {
	sw_conf_has "$1" || return 0
	[ "$(sw_conf_get "$1")" = UNSET ]
}

# sw_conf_unknown_keys: prints the keys of the file that are not recognised.
sw_conf_unknown_keys() {
	for _k in $SW_CONF_KEYS; do
		sw_known_key "$_k" || printf '%s\n' "$_k"
	done
}

# sw_line NAME STATUS: one report line, name first.
sw_line() {
	printf '%-15s %s\n' "$1" "$2"
}
