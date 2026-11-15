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
