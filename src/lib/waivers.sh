# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_WAIVER* globals are read by verify.sh and doctor.sh
# softwary: time-limited waivers. Sourced by bin/softwary. POSIX sh.
#
# .softwary/config/waivers.conf belongs to the project. One line per waiver:
#   <key> = <YYYY-MM-DD>: <reason>
# <key> is a project check run by verify; the waiver holds through the date.
# A waived check that fails does not fail verify; it never hides the failure.

SW_WAIVERS_REL=.softwary/config/waivers.conf
SW_PACKAGE_CHECKS="sync model views trace adr changes"

# sw_valid_date DATE: true if DATE is a calendar date written YYYY-MM-DD.
sw_valid_date() {
	case $1 in
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
	*) return 1 ;;
	esac
	_vy=${1%%-*}
	_vm=${1#*-}
	_vm=${_vm%-*}
	_vd=${1##*-}
	_vy=${_vy#0}; _vy=${_vy#0}; _vy=${_vy#0}
	_vm=${_vm#0}
	_vd=${_vd#0}
	[ -n "$_vy" ] && [ -n "$_vm" ] && [ -n "$_vd" ] || return 1
	[ "$_vm" -ge 1 ] && [ "$_vm" -le 12 ] && [ "$_vd" -ge 1 ] || return 1
	case $_vm in
	2)
		if [ $((_vy % 4)) -eq 0 ] && { [ $((_vy % 100)) -ne 0 ] || [ $((_vy % 400)) -eq 0 ]; }; then
			_vmax=29
		else
			_vmax=28
		fi
		;;
	4 | 6 | 9 | 11) _vmax=30 ;;
	*) _vmax=31 ;;
	esac
	[ "$_vd" -le "$_vmax" ]
}

# sw_waivers_load: parses waivers.conf. Sets SW_WAIVERS_ERRORS (one
# "REL:LINE: message" per line) and SW_WAIVERS (the valid keys, file order).
# A missing file means no waivers.
sw_waivers_load() {
	sw_kv_load "$SOFTWARY_ROOT/$SW_WAIVERS_REL" "$SW_WAIVERS_REL" SW_WV waivers
	SW_WAIVERS_ERRORS=$SW_WV_ERRORS
	SW_WAIVERS=
	for _wk in $SW_WV_KEYS; do
		_wv=$(sw_kv_get SW_WV "$_wk")
		_wl=$(sw_kv_line SW_WV "$_wk")
		_we=
		if sw_in_list "$_wk" "$SW_PACKAGE_CHECKS"; then
			_we="'$_wk' is a package check and cannot be waived"
		elif ! sw_in_list "$_wk" "$SW_VERIFY_KEYS"; then
			_we="unknown key '$_wk' (use one of: $SW_VERIFY_KEYS)"
		else
			case $_wv in
			*:*)
				_wd=$(sw_trim "${_wv%%:*}")
				if ! sw_valid_date "$_wd"; then
					_we="invalid date '$_wd' (use YYYY-MM-DD)"
				elif [ -z "$(sw_trim "${_wv#*:}")" ]; then
					_we="'$_wk' needs a reason: '$_wk = YYYY-MM-DD: <reason>'"
				fi
				;;
			*) _we="malformed line: expected '$_wk = YYYY-MM-DD: <reason>'" ;;
			esac
		fi
		if [ -n "$_we" ]; then
			SW_WAIVERS_ERRORS="${SW_WAIVERS_ERRORS}${SW_WAIVERS_REL}:$_wl: $_we
"
		else
			SW_WAIVERS="$SW_WAIVERS $_wk"
		fi
	done
}

# sw_waiver KEY: true if KEY has a valid waiver (after sw_waivers_load). Sets
# SW_WAIVER_DATE, SW_WAIVER_REASON and SW_WAIVER_EXPIRED (1 when the date is
# before today, local time).
sw_waiver() {
	sw_in_list "$1" "$SW_WAIVERS" || return 1
	_wv=$(sw_kv_get SW_WV "$1")
	SW_WAIVER_DATE=$(sw_trim "${_wv%%:*}")
	SW_WAIVER_REASON=$(sw_trim "${_wv#*:}")
	SW_WAIVER_EXPIRED=0
	_wtoday=$(date +%Y%m%d)
	[ "$(printf '%s' "$SW_WAIVER_DATE" | tr -d -)" -ge "$_wtoday" ] || SW_WAIVER_EXPIRED=1
	return 0
}

# sw_date_days DATE: the number of days from 1970-01-01 to DATE (YYYY-MM-DD,
# valid), by the calendar and without `date` arithmetic, which is not POSIX.
sw_date_days() {
	_dd_y=${1%%-*}
	_dd_m=${1#*-}
	_dd_m=${_dd_m%-*}
	_dd_d=${1##*-}
	while :; do case $_dd_y in 0?*) _dd_y=${_dd_y#0} ;; *) break ;; esac; done
	while :; do case $_dd_m in 0?*) _dd_m=${_dd_m#0} ;; *) break ;; esac; done
	while :; do case $_dd_d in 0?*) _dd_d=${_dd_d#0} ;; *) break ;; esac; done
	[ "$_dd_m" -gt 2 ] || _dd_y=$((_dd_y - 1))
	_dd_era=$((_dd_y / 400))
	_dd_yoe=$((_dd_y - _dd_era * 400))
	if [ "$_dd_m" -gt 2 ]; then _dd_mp=$((_dd_m - 3)); else _dd_mp=$((_dd_m + 9)); fi
	_dd_doy=$(((153 * _dd_mp + 2) / 5 + _dd_d - 1))
	_dd_doe=$((_dd_yoe * 365 + _dd_yoe / 4 - _dd_yoe / 100 + _dd_doy))
	printf '%s\n' $((_dd_era * 146097 + _dd_doe - 719468))
}

# sw_days_left DATE: the days from today (local time) to DATE; negative once
# DATE is past.
sw_days_left() {
	_dl_to=$(date +%Y-%m-%d)
	printf '%s\n' $(($(sw_date_days "$1") - $(sw_date_days "$_dl_to")))
}

# sw_until_text DATE: "(<n> days left)" or "(expired)".
sw_until_text() {
	_ut_n=$(sw_days_left "$1")
	if [ "$_ut_n" -lt 0 ]; then
		printf '(expired)'
	elif [ "$_ut_n" -eq 1 ]; then
		printf '(1 day left)'
	else
		printf '(%s days left)' "$_ut_n"
	fi
}

# sw_status_waivers: what is waived or recorded as a finding, one line each:
#   waiver <key>: until <date> (<n> days left|expired): <reason>
#   finding <spec>/<invariant>: until <date> (...): <reason>
# Problems of waivers.conf come first, as doctor prints them. Writes nothing.
sw_status_waivers() {
	sw_waivers_load
	[ -z "$SW_WAIVERS_ERRORS" ] || printf '%s' "$SW_WAIVERS_ERRORS"
	for _sw_k in $SW_WAIVERS; do
		sw_waiver "$_sw_k"
		printf 'waiver %s: until %s %s: %s\n' "$_sw_k" "$SW_WAIVER_DATE" "$(sw_until_text "$SW_WAIVER_DATE")" "$SW_WAIVER_REASON"
	done
	for _sw_md in "$SOFTWARY_ROOT/$SW_FORMAL_DIR"/*.md; do
		[ -f "$_sw_md" ] || continue
		_sw_ad=${_sw_md##*/}
		_sw_ad=${_sw_ad%.md}
		sw_formal_findings "$_sw_ad" | while IFS='|' read -r _sw_i _sw_u _sw_r; do
			[ -n "$_sw_i" ] || continue
			if sw_valid_date "$_sw_u"; then
				printf 'finding %s/%s: until %s %s: %s\n' "$_sw_ad" "$_sw_i" "$_sw_u" "$(sw_until_text "$_sw_u")" "$_sw_r"
			else
				printf 'finding %s/%s: until %s (invalid date): %s\n' "$_sw_ad" "$_sw_i" "$_sw_u" "$_sw_r"
			fi
		done
	done
}
