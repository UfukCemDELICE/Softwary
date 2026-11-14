# shellcheck shell=sh
# softwary: ADR checks. Sourced by bin/softwary. POSIX sh.
#
# `trace` validates every architecture decision record (sw_trace_adrs).
# ADR front matter: id title status affects. `affects` lists repo paths inside
# architecture/, comma-separated; a directory covers everything below it.

SW_ADR_REL=architecture/decisions
SW_ADR_FIELDS="id title status affects"
SW_ADR_STATUSES="proposed accepted superseded rejected"

# sw_adr_entry_scope ENTRY: true if ENTRY is a path below architecture/ with
# no '..', '.' or empty segment and no leading '/'.
sw_adr_entry_scope() {
	case $1 in
	architecture/?*) ;;
	*) return 1 ;;
	esac
	case /$1/ in
	*/../* | */./* | *//*) return 1 ;;
	esac
	return 0
}

# sw_trace_adrs: checks every file under architecture/decisions/ (called by
# sw_trace; adds to _tr_probs through sw_tr_problem and counts _tr_adrs).
sw_trace_adrs() {
	for _af in "$SOFTWARY_ROOT/$SW_ADR_REL"/*.md; do
		[ -f "$_af" ] || continue
		_tr_adrs=$((_tr_adrs + 1))
		_ab=${_af##*/}
		_arel=$SW_ADR_REL/$_ab
		sw_fm_read "$_af"
		sw_tr_fields "$_arel" "$SW_ADR_FIELDS" "$SW_ADR_FIELDS"
		if printf '%s\n' "$_ab" | grep -Eq '^[0-9]{4}-[a-z0-9][a-z0-9-]*\.md$'; then
			_v=$(sw_fm_get id)
			case $_v in '' | UNSET | "${_ab%%-*}") ;; *) sw_tr_problem "$_arel" "id: '$_v' does not match the file name $_ab" ;; esac
		else
			sw_tr_problem "$_arel" "file name must be NNNN-<name>.md"
		fi
		sw_tr_enum "$_arel" status "$SW_ADR_STATUSES"
		_aff=$(sw_list "$(sw_fm_get affects)")
		[ -n "$_aff" ] || continue
		while IFS= read -r _ae; do
			if ! sw_adr_entry_scope "$_ae"; then
				sw_tr_problem "$_arel" "affects: '$_ae' is outside architecture/"
			elif [ ! -e "$SOFTWARY_ROOT/$_ae" ]; then
				sw_tr_problem "$_arel" "affects: '$_ae' not found"
			fi
		done <<AFFECTS
$_aff
AFFECTS
	done
}
