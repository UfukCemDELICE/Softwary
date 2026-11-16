# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: loop.conf and models.conf. Sourced by bin/softwary. POSIX sh.
#
# Both files belong to the project. Both are `key = value` files read with
# the kv parser of config.sh. The load functions return 0 when the file is
# usable and 2 otherwise, with one "REL[:LINE]: problem" per line in the
# *_ERRORS variable; doctor lists them and `run start` stops on them.

SW_LOOP_REL=.softwary/config/loop.conf
SW_LOOP_KEYS_ALL="max_rounds max_job_minutes max_run_minutes concurrency max_job_tokens max_run_tokens min_catch_percent"
SW_LOOP_TOKEN_KEYS="max_job_tokens max_run_tokens"
SW_MODELS_REL=.softwary/config/models.conf

# sw_loop_load: parses loop.conf. Sets SW_LOOP_ERRORS.
sw_loop_load() {
	sw_kv_load "$SOFTWARY_ROOT/$SW_LOOP_REL" "$SW_LOOP_REL" SW_LOOP commands
	if [ "$SW_LOOP_FOUND" -eq 0 ]; then
		SW_LOOP_ERRORS="$SW_LOOP_REL: file not found; rerun install.sh
"
		return 2
	fi
	for _lk in $SW_LOOP_KEYS; do
		_ll=$(sw_kv_line SW_LOOP "$_lk")
		_lv=$(sw_kv_get SW_LOOP "$_lk")
		_le=
		if ! sw_in_list "$_lk" "$SW_LOOP_KEYS_ALL"; then
			_le="unknown key '$_lk' (use $SW_LOOP_KEYS_ALL)"
		elif sw_in_list "$_lk" "$SW_LOOP_TOKEN_KEYS"; then
			case $_lv in
			UNSET) _le="$_lk: is UNSET (set a positive integer or 'NONE: <reason>')" ;;
			NONE:*) ;;
			*) sw_positive_int "$_lv" || _le="$_lk: '$_lv' is not a positive integer or 'NONE: <reason>'" ;;
			esac
		elif [ "$_lk" = min_catch_percent ]; then
			sw_percent "$_lv" || _le="$_lk: '$_lv' is not a whole number from 0 to 100"
		elif [ "$_lv" = UNSET ]; then
			_le="$_lk: is UNSET (set a positive integer)"
		elif ! sw_positive_int "$_lv"; then
			_le="$_lk: '$_lv' is not a positive integer"
		elif [ "$_lk" = concurrency ] && [ "$_lv" -ne 1 ]; then
			_le="concurrency above 1 arrives with parallel jobs (V4)"
		fi
		[ -z "$_le" ] || SW_LOOP_ERRORS="${SW_LOOP_ERRORS}${SW_LOOP_REL}:$_ll: $_le
"
	done
	for _lk in $SW_LOOP_KEYS_ALL; do
		sw_kv_has SW_LOOP "$_lk" ||
			SW_LOOP_ERRORS="${SW_LOOP_ERRORS}${SW_LOOP_REL}: '$_lk' is missing
"
	done
	[ -z "$SW_LOOP_ERRORS" ]
}

# sw_positive_int VALUE: true for 1, 2, 3, ... (no sign, no leading zero).
sw_positive_int() {
	case $1 in '' | 0* | *[!0-9]*) return 1 ;; esac
	return 0
}

# sw_percent VALUE: true for a whole number from 0 to 100 (no sign, no
# leading zero).
sw_percent() {
	case $1 in
	0 | [1-9] | [1-9][0-9] | 100) return 0 ;;
	esac
	return 1
}

# sw_loop_get KEY: the value of KEY (after sw_loop_load returned 0).
sw_loop_get() {
	sw_kv_get SW_LOOP "$1"
}

# sw_loop_num KEY: the limit of KEY as a number; nothing when it is NONE.
sw_loop_num() {
	_lg=$(sw_kv_get SW_LOOP "$1")
	sw_positive_int "$_lg" && printf '%s\n' "$_lg"
	return 0
}

# sw_models_load: parses models.conf against the installed subagents (the
# managed ones and .softwary/local/agents/). Sets SW_MODELS_ERRORS.
sw_models_load() {
	sw_kv_load "$SOFTWARY_ROOT/$SW_MODELS_REL" "$SW_MODELS_REL" SW_MODELS tools
	if [ "$SW_MODELS_FOUND" -eq 0 ]; then
		SW_MODELS_ERRORS="$SW_MODELS_REL: file not found; rerun install.sh
"
		return 2
	fi
	_ma=$(sw_source_names agents)
	for _mk in $SW_MODELS_KEYS; do
		_ml=$(sw_kv_line SW_MODELS "$_mk")
		_mv=$(sw_kv_get SW_MODELS "$_mk")
		_me=
		if ! printf '%s\n' "$_ma" | grep -Fqx -e "$_mk"; then
			_me="unknown agent '$_mk'"
		else
			case $_mv in
			*[!A-Za-z0-9._-]*) _me="invalid model '$_mv' for '$_mk'" ;;
			esac
		fi
		[ -z "$_me" ] || SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}:$_ml: $_me
"
	done
	for _mk in $_ma; do
		sw_kv_has SW_MODELS "$_mk" ||
			SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}: agent '$_mk' has no model
"
	done
	if sw_kv_has SW_MODELS implementer; then
		_mi=$(sw_kv_get SW_MODELS implementer)
		for _mk in reviewer approver; do
			sw_kv_has SW_MODELS "$_mk" || continue
			[ "$(sw_kv_get SW_MODELS "$_mk")" = "$_mi" ] || continue
			SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}:$(sw_kv_line SW_MODELS "$_mk"): $_mk must not use the same model as implementer ($_mi)
"
		done
	fi
	[ -z "$SW_MODELS_ERRORS" ]
}

# sw_models_get AGENT: the model of AGENT (after sw_models_load returned 0).
sw_models_get() {
	sw_kv_get SW_MODELS "$1"
}
