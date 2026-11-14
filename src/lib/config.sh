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

# sw_kv_load FILE REL PREFIX MODE: parses a `key = value` file.
#   MODE commands: keys [a-z][a-z0-9_]*, NONE values need a reason.
#   MODE tools:    keys [a-z][a-z0-9-]*.
# Sets ${PREFIX}_FOUND (0/1), ${PREFIX}_KEYS (keys in file order) and
# ${PREFIX}_ERRORS (one "REL:LINE: message" per line, empty when well-formed).
# Values and line numbers are read with sw_kv_get and sw_kv_line.
sw_kv_load() {
	_kv_rel=$2
	_kv_p=$3
	_kv_mode=$4
	_kv_keys=
	_kv_errors=
	_kv_found=0
	if [ -f "$1" ]; then
		_kv_found=1
		_n=0
		while IFS= read -r _line || [ -n "$_line" ]; do
			_n=$((_n + 1))
			sw_kv_parse_line "$_line"
		done <"$1"
	fi
	eval "${_kv_p}_FOUND=\$_kv_found"
	eval "${_kv_p}_KEYS=\$_kv_keys"
	eval "${_kv_p}_ERRORS=\$_kv_errors"
}

sw_kv_error() {
	_kv_errors="${_kv_errors}${_kv_rel}:$1: $2
"
}

# sw_kv_parse_line LINE: one line of sw_kv_load (line number in $_n).
sw_kv_parse_line() {
	_line=$(sw_trim "$1")
	case $_line in '' | '#'*) return 0 ;; esac
	case $_line in
	*=*) ;;
	*)
		sw_kv_error "$_n" "malformed line: expected 'key = value'"
		return 0
		;;
	esac
	_key=$(sw_trim "${_line%%=*}")
	_value=$(sw_trim "${_line#*=}")
	if [ -z "$_key" ]; then
		sw_kv_error "$_n" "malformed line: missing key before '='"
		return 0
	fi
	if ! sw_valid_key "$_kv_mode" "$_key"; then
		if [ "$_kv_mode" = tools ]; then _hint="lowercase letters, digits, '-'"; else _hint="lowercase letters, digits, '_'"; fi
		sw_kv_error "$_n" "malformed line: invalid key '$_key' (use $_hint)"
		return 0
	fi
	if [ -z "$_value" ]; then
		sw_kv_error "$_n" "malformed line: empty value for '$_key'"
		return 0
	fi
	if [ "$_kv_mode" = commands ]; then
		case $_value in
		NONE | NONE:*)
			if [ -z "$(sw_none_reason "$_value")" ]; then
				sw_kv_error "$_n" "malformed line: '$_key' needs a reason: 'NONE: <reason>'"
				return 0
			fi
			;;
		esac
	fi
	if sw_in_list "$_key" "$_kv_keys"; then
		_first=
		eval "_first=\${${_kv_p}_L_$(sw_key_var "$_key")}"
		sw_kv_error "$_n" "malformed line: duplicate key '$_key' (first on line $_first)"
		return 0
	fi
	_kv_keys="$_kv_keys $_key"
	_var=$(sw_key_var "$_key")
	eval "${_kv_p}_V_$_var=\$_value"
	eval "${_kv_p}_L_$_var=\$_n"
}

# sw_valid_key MODE KEY: true if KEY is a valid key for MODE (commands or tools).
sw_valid_key() {
	case $2 in [!a-z]*) return 1 ;; esac
	if [ "$1" = tools ]; then
		case $2 in *[!a-z0-9-]*) return 1 ;; esac
	else
		case $2 in *[!a-z0-9_]*) return 1 ;; esac
	fi
	return 0
}

# sw_key_var KEY: the variable-name form of KEY ('-' becomes '_').
sw_key_var() {
	printf '%s' "$1" | tr - _
}

# sw_kv_has PREFIX KEY / sw_kv_get PREFIX KEY / sw_kv_line PREFIX KEY
sw_kv_has() {
	_kv_list=
	eval "_kv_list=\${${1}_KEYS-}"
	sw_in_list "$2" "$_kv_list"
}

sw_kv_get() {
	sw_kv_has "$1" "$2" || return 1
	eval "printf '%s' \"\${${1}_V_$(sw_key_var "$2")}\""
}

sw_kv_line() {
	eval "printf '%s' \"\${${1}_L_$(sw_key_var "$2")-}\""
}

# sw_conf_load FILE: parses commands.conf into the SW_CONF_* variables.
sw_conf_load() {
	sw_kv_load "$1" "$SW_CONF_REL" SW_CONF commands
}

# sw_none_reason VALUE: prints the reason of a `NONE: <reason>` value.
sw_none_reason() {
	_r=${1#NONE}
	_r=${_r#:}
	sw_trim "$_r"
}

sw_conf_has() {
	sw_kv_has SW_CONF "$1"
}

sw_conf_get() {
	sw_kv_get SW_CONF "$1"
}

sw_conf_line() {
	sw_kv_line SW_CONF "$1"
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
