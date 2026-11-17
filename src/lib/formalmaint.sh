# shellcheck shell=sh
# softwary: the upkeep of a specification (V8). Sourced by bin/softwary. POSIX sh.
#
# A model that the code has left behind proves nothing, so the record of a
# specification (architecture/formal/<ad>.md) is held to the code: its
# coverage table points at files and functions that are there, and what the
# loop may change of it (the model, the configurations, the coverage, the
# commit last verified) is told apart from what binds a human (the invariants,
# the findings, the set of files: guard.sh).

# --- the record ---------------------------------------------------------------

# sw_fmaint_section_raw SECTION: the lines of a record's table under
# "## SECTION", read from stdin, exactly as written.
sw_fmaint_section_raw() {
	tr -d '\r' | awk -v sec="$1" '
		/^##[ \t]/ { t = $0; sub(/^##[ \t]+/, "", t); sub(/[ \t]+$/, "", t); insec = (t == sec); next }
		insec && /^[ \t]*\|/ { print }'
}

# sw_fmaint_covered AD: the coverage rows that are not `planned`, one per line:
# "<path><TAB><functions>".
sw_fmaint_covered() {
	sw_formal_table "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$1.md" Coverage |
		awk -F'|' '$1 == "R" && $2 != "" && $2 != "planned" { print $2 "\t" $3 }'
}

# --- slices ---------------------------------------------------------------------

# sw_fmaint_all_covered: "<ad><TAB><path>" for the covered paths of every record.
sw_fmaint_all_covered() {
	for _fa_ad in $(sw_formal_names); do
		[ -f "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$_fa_ad.md" ] || continue
		while IFS= read -r _fa_p; do
			[ -z "$_fa_p" ] || printf '%s\t%s\n' "$_fa_ad" "$_fa_p"
		done <<COVERED
$(sw_fmaint_covered "$_fa_ad" | cut -f1)
COVERED
	done
}

# sw_fmaint_touches_problems SLICE TOUCHES COVERED: one line for each
# specification whose covered code the slice touches (its touches covers the
# path, or the path covers the touches entry: the rule of V3) without
# touching the record of that specification. COVERED is what
# sw_fmaint_all_covered prints.
sw_fmaint_touches_problems() {
	_ft_slice=$1
	_ft_list=$(sw_list "$2")
	_ft_done=
	while IFS='	' read -r _ft_ad _ft_p; do
		[ -n "$_ft_p" ] || continue
		sw_in_list "$_ft_ad" "$_ft_done" && continue
		_ft_rec=$SW_FORMAL_DIR/$_ft_ad.md
		_ft_hit=
		_ft_has=0
		while IFS= read -r _ft_e; do
			[ -n "$_ft_e" ] || continue
			! sw_guard_covers "$_ft_e" "$_ft_rec" || _ft_has=1
			if [ -z "$_ft_hit" ] && { sw_guard_covers "$_ft_e" "$_ft_p" || sw_guard_covers "$_ft_p" "$_ft_e"; }; then
				_ft_hit=$_ft_e
			fi
		done <<TOUCHES
$_ft_list
TOUCHES
		if [ -n "$_ft_hit" ] && [ "$_ft_has" -eq 0 ]; then
			printf 'slice %s touches %s covered by formal %s; add %s to touches\n' "$_ft_slice" "$_ft_hit" "$_ft_ad" "$_ft_rec"
			_ft_done="$_ft_done $_ft_ad"
		fi
	done <<ALLCOVERED
$3
ALLCOVERED
}
