# shellcheck shell=sh
# softwary: `verify` command. Sourced by bin/softwary. POSIX sh.
#
# Runs the project's checks from commands.conf, cheapest first, without
# stopping at the first failure. Exit: 0 passed, 1 failed, 2 configuration.

SW_TAIL_LINES=20

sw_verify() {
	_fast=0
	for _a in "$@"; do
		case $_a in
		--fast) _fast=1 ;;
		*)
			printf 'softwary verify: unknown option: %s\n' "$_a" >&2
			printf 'usage: ./softwary verify [--fast]\n' >&2
			return 2
			;;
		esac
	done
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
	if [ "$_bad" -ne 0 ]; then
		printf 'verify: configuration incomplete; fix the keys above in %s\n' "$SW_CONF_REL"
		return 2
	fi

	_logdir=$SOFTWARY_ROOT/.softwary/state/logs
	mkdir -p "$_logdir" || return 2
	_pass=0 _failc=0 _skip=0
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
		_log=$_logdir/verify-$_k.log
		_start=$(date +%s)
		_rc=0
		(cd "$SOFTWARY_ROOT" && sh -c "$_cmd") >"$_log" 2>&1 </dev/null || _rc=$?
		_dur=$(($(date +%s) - _start))
		if [ "$_rc" -eq 0 ]; then
			sw_line "$_k" "PASS (${_dur}s)"
			_pass=$((_pass + 1))
		else
			sw_line "$_k" "FAIL (${_dur}s)"
			tail -n "$SW_TAIL_LINES" "$_log" | sed 's/^/    /'
			printf '    log: .softwary/state/logs/verify-%s.log (exit %s)\n' "$_k" "$_rc"
			_failc=$((_failc + 1))
		fi
	done
	printf 'verify: %s passed, %s failed, %s skipped\n' "$_pass" "$_failc" "$_skip"
	[ "$_failc" -eq 0 ] || return 1
	return 0
}
