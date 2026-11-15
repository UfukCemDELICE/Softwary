# shellcheck shell=sh
# softwary: `verify` command. Sourced by bin/softwary. POSIX sh.
#
# Runs the project's checks from commands.conf, cheapest first, without
# stopping at the first failure. Exit: 0 passed, 1 failed, 2 configuration.

SW_TAIL_LINES=20

sw_verify_usage() {
	printf 'usage: ./softwary verify [--fast] [--base <ref>]\n' >&2
}

sw_verify() {
	_fast=0 _base=
	while [ $# -gt 0 ]; do
		case $1 in
		--fast)
			_fast=1
			shift
			;;
		--base)
			[ $# -ge 2 ] || { sw_verify_usage; return 2; }
			_base=$2
			shift 2
			;;
		*)
			printf 'softwary verify: unknown option: %s\n' "$1" >&2
			sw_verify_usage
			return 2
			;;
		esac
	done
	if [ "$_fast" -eq 1 ] && [ -n "$_base" ]; then
		printf 'softwary verify: --fast cannot be combined with --base\n' >&2
		return 2
	fi
	if [ -n "$_base" ]; then
		sw_base_commit "$_base" || return 2
		SW_VERIFY_BASE=$_base
		export SW_VERIFY_BASE
	fi
	if [ "$_fast" -eq 1 ]; then _checks=$SW_FAST_KEYS; else _checks=$SW_VERIFY_KEYS; fi

	sw_conf_load "$SOFTWARY_ROOT/$SW_CONF_REL"
	if [ "$SW_CONF_FOUND" -eq 0 ]; then
		printf 'verify: %s not found; run install.sh or ./softwary doctor\n' "$SW_CONF_REL"
		return 2
	fi
	if [ -n "$SW_CONF_ERRORS" ]; then
		printf '%s' "$SW_CONF_ERRORS"
		printf 'verify: fix the lines above in %s\n' "$SW_CONF_REL"
		return 2
	fi

	_bad=0
	for _k in $(sw_conf_unknown_keys); do
		printf 'UNKNOWN  %s (line %s)\n' "$_k" "$(sw_conf_line "$_k")"
		_bad=1
	done
	for _k in $_checks; do
		if sw_in_list "$_k" "$SW_REQUIRED_KEYS" && sw_conf_is_unset "$_k"; then
			printf 'UNSET    %s\n' "$_k"
			_bad=1
		fi
	done
	if [ "$_fast" -eq 0 ]; then
		SW_PROBLEMS=
		sw_tools_load
		if [ -n "$SW_PROBLEMS" ]; then
			printf '%s' "$SW_PROBLEMS"
			_bad=1
		fi
		if [ ! -f "$SOFTWARY_ROOT/$SW_MODEL_REL" ]; then
			printf 'model: %s\n' "$SW_MODEL_MISSING"
			_bad=1
		fi
	fi
	if [ "$_bad" -ne 0 ]; then
		printf 'verify: configuration incomplete; fix the lines above\n'
		return 2
	fi

	_logdir=$SOFTWARY_ROOT/.softwary/state/logs
	mkdir -p "$_logdir" || return 2
	_pass=0 _failc=0 _skip=0
	if [ "$_fast" -eq 0 ]; then
		# The package's own checks come first: generated files are up to date,
		# the model is valid, its view is current and specs trace to tests.
		# shellcheck disable=SC2016 # expanded by the check's shell
		sw_verify_run sync 'sh "$SOFTWARY_HOME/bin/softwary" sync --check'
		# shellcheck disable=SC2016
		sw_verify_run model 'sh "$SOFTWARY_HOME/bin/softwary" model validate'
		# shellcheck disable=SC2016
		sw_verify_run views 'sh "$SOFTWARY_HOME/bin/softwary" views --check'
		# shellcheck disable=SC2016
		sw_verify_run trace 'sh "$SOFTWARY_HOME/bin/softwary" trace'
		if [ -n "$_base" ]; then
			# shellcheck disable=SC2016
			sw_verify_run adr 'sh "$SOFTWARY_HOME/bin/softwary" adr --base "$SW_VERIFY_BASE"'
		fi
	fi
	for _k in $_checks; do
		if sw_conf_is_unset "$_k"; then
			sw_line "$_k" "SKIP (not configured)"
			_skip=$((_skip + 1))
			continue
		fi
		_cmd=$(sw_conf_get "$_k")
		case $_cmd in
		NONE | NONE:*)
			sw_line "$_k" "SKIP ($(sw_none_reason "$_cmd"))"
			_skip=$((_skip + 1))
			continue
			;;
		esac
		sw_verify_run "$_k" "$_cmd"
	done
	printf 'verify: %s passed, %s failed, %s skipped\n' "$_pass" "$_failc" "$_skip"
	[ "$_failc" -eq 0 ] || return 1
	return 0
}

# sw_verify_run NAME COMMAND: runs one check from the repo root and reports it.
sw_verify_run() {
	_log=$_logdir/verify-$1.log
	_start=$(date +%s)
	_rc=0
	(cd "$SOFTWARY_ROOT" && sh -c "$2") >"$_log" 2>&1 </dev/null || _rc=$?
	_dur=$(($(date +%s) - _start))
	if [ "$_rc" -eq 0 ]; then
		sw_line "$1" "PASS (${_dur}s)"
		_pass=$((_pass + 1))
	else
		sw_line "$1" "FAIL (${_dur}s)"
		tail -n "$SW_TAIL_LINES" "$_log" | sed 's/^/    /'
		printf '    log: .softwary/state/logs/verify-%s.log (exit %s)\n' "$1" "$_rc"
		_failc=$((_failc + 1))
	fi
}
