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
		elif [ "$_lk" = concurrency ]; then
			case $_lv in 1 | 2 | 3) ;; *) _le="concurrency must be 1, 2 or 3" ;; esac
		elif [ "$_lv" = UNSET ]; then
			_le="$_lk: is UNSET (set a positive integer)"
		elif ! sw_positive_int "$_lv"; then
			_le="$_lk: '$_lv' is not a positive integer"
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
# managed ones and .softwary/local/agents/) and the tools of tools.conf. Sets
# SW_MODELS_ERRORS.
#
# Two kinds of lines: `<agent> = <class>` (the V2 line: a class such as opus or
# sonnet) and `<tool>: <class> = <model id>`, what a class is called in a tool
# (V9). A class with no line for a tool is the class name itself in Claude Code;
# in Cursor and Codex it is an error while the tool is on.
SW_MODELS_TRANSLATED="cursor codex"

# sw_models_tools_on: the tools that are on in tools.conf, one per line (none
# when the file is missing or unusable: doctor reports that).
sw_models_tools_on() {
	sw_kv_load "$SOFTWARY_ROOT/$SW_TOOLS_REL" "$SW_TOOLS_REL" SW_MTOOLS tools
	[ "$SW_MTOOLS_FOUND" -eq 1 ] || return 0
	for _mto in $SW_MTOOLS_KEYS; do
		[ "$(sw_kv_get SW_MTOOLS "$_mto")" = on ] && printf '%s\n' "$_mto"
	done
	return 0
}

# sw_models_id_ok ID: a model id is not UNSET and has no space, quote or
# '#' (it is written into YAML and TOML as it is); Cursor's brackets
# (claude-opus-5[effort=high]) are allowed.
sw_models_id_ok() {
	[ "$1" != UNSET ] || return 1
	printf '%s\n' "$1" | grep -Eq '^[][A-Za-z0-9._,=-]+$'
}

sw_models_load() {
	sw_kv_load "$SOFTWARY_ROOT/$SW_MODELS_REL" "$SW_MODELS_REL" SW_MODELS models
	if [ "$SW_MODELS_FOUND" -eq 0 ]; then
		SW_MODELS_ERRORS="$SW_MODELS_REL: file not found; rerun install.sh
"
		return 2
	fi
	_ma=$(sw_source_names agents)
	_mtools=$(sw_targets)
	_mon=$(sw_models_tools_on)
	_mclasses=
	for _mk in $SW_MODELS_KEYS; do
		_ml=$(sw_kv_line SW_MODELS "$_mk")
		_mv=$(sw_kv_get SW_MODELS "$_mk")
		_me=
		case $_mk in
		*:*)
			if ! printf '%s\n' "$_mtools" | grep -Fqx -e "${_mk%%:*}"; then
				_me="unknown tool '${_mk%%:*}' in '$_mk' (known: $(printf '%s' "$_mtools" | tr '\n' ' ' | sed 's/ $//'))"
			elif ! sw_models_id_ok "$_mv"; then
				_me="invalid model id '$_mv' for '$_mk'"
			fi
			;;
		*)
			if ! printf '%s\n' "$_ma" | grep -Fqx -e "$_mk"; then
				_me="unknown agent '$_mk'"
			else
				case $_mv in
				*[!A-Za-z0-9._-]*) _me="invalid model '$_mv' for '$_mk'" ;;
				*) sw_in_list "$_mv" "$_mclasses" || _mclasses="$_mclasses $_mv" ;;
				esac
			fi
			;;
		esac
		[ -z "$_me" ] || SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}:$_ml: $_me
"
	done
	for _mk in $_ma; do
		sw_kv_has SW_MODELS "$_mk" ||
			SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}: agent '$_mk' has no model
"
	done
	# A translation is of a class that some agent uses.
	for _mk in $SW_MODELS_KEYS; do
		case $_mk in *:*) ;; *) continue ;; esac
		sw_in_list "${_mk#*:}" "$_mclasses" ||
			SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}:$(sw_kv_line SW_MODELS "$_mk"): no agent uses the class '${_mk#*:}' ('$_mk')
"
	done
	# Cursor and Codex need a name for every class while they are on.
	for _mt in $SW_MODELS_TRANSLATED; do
		printf '%s\n' "$_mon" | grep -Fqx -e "$_mt" || continue
		for _mc in $_mclasses; do
			sw_kv_has SW_MODELS "$_mt:$_mc" ||
				SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}: $_mt is on but the class '$_mc' has no model id (add '$_mt: $_mc = <model id>')
"
		done
	done
	# The reviewer and the approver must not use the implementer's model, in
	# any tool that is on. Claude Code is always checked (the V2 rule, by class
	# name; then by the id when a class is translated); Cursor and Codex by the
	# translated id (D-192).
	if sw_kv_has SW_MODELS implementer; then
		_mi=$(sw_kv_get SW_MODELS implementer)
		for _mk in reviewer approver; do
			sw_kv_has SW_MODELS "$_mk" || continue
			_mr=$(sw_kv_get SW_MODELS "$_mk")
			_mrl=$(sw_kv_line SW_MODELS "$_mk")
			if [ "$_mr" = "$_mi" ]; then
				SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}:$_mrl: $_mk must not use the same model as implementer ($_mi)
"
			fi
			for _mt in claude-code $SW_MODELS_TRANSLATED; do
				if [ "$_mt" != claude-code ]; then
					printf '%s\n' "$_mon" | grep -Fqx -e "$_mt" || continue
				elif [ "$_mr" = "$_mi" ]; then
					continue
				fi
				_mid=$(sw_models_get implementer "$_mt") || continue
				_mrid=$(sw_models_get "$_mk" "$_mt") || continue
				[ "$_mid" = "$_mrid" ] || continue
				SW_MODELS_ERRORS="${SW_MODELS_ERRORS}${SW_MODELS_REL}:$_mrl: $_mk uses the implementer's model in $_mt ($_mrid)
"
			done
		done
	fi
	[ -z "$SW_MODELS_ERRORS" ]
}

# sw_models_get AGENT [TOOL]: the model of AGENT (after sw_models_load): its
# class, or with TOOL the model id the class has in TOOL. A class with no id
# in Claude Code is its own name; in another tool it has none (returns 1).
sw_models_get() {
	sw_kv_has SW_MODELS "$1" || return 1
	_mgc=$(sw_kv_get SW_MODELS "$1")
	if [ $# -lt 2 ]; then
		printf '%s' "$_mgc"
		return 0
	fi
	if sw_kv_has SW_MODELS "$2:$_mgc"; then
		sw_kv_get SW_MODELS "$2:$_mgc"
		return 0
	fi
	[ "$2" = claude-code ] || return 1
	printf '%s' "$_mgc"
}
