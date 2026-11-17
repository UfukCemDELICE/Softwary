# shellcheck shell=sh
# softwary: the upkeep of a specification (V8). Sourced by bin/softwary. POSIX sh.
#
# A model that the code has left behind proves nothing, so the record of a
# specification (architecture/formal/<ad>.md) is held to the code:
#   - `## Coverage` names files and functions that are there (coverage);
#   - `## Last verified` names the commit the model was last checked against
#     the code, and what has changed since (the covered files, the model and
#     its configurations, the coverage table) makes the model stale until a
#     verdict is recorded with `formal verified` (compatible or updated);
#   - what the loop may change of a record (the model, the configurations, the
#     coverage, the commit last verified) is told apart from what binds a human
#     (the invariants, the findings, the set of files: guard.sh), and a slice
#     that touches covered code touches the record too (plan.sh).

# --- the record ---------------------------------------------------------------

# sw_fmaint_section_raw SECTION: the lines of a record's table under
# "## SECTION", read from stdin, exactly as written.
sw_fmaint_section_raw() {
	tr -d '\r' | awk -v sec="$1" '
		/^##[ \t]/ { t = $0; sub(/^##[ \t]+/, "", t); sub(/[ \t]+$/, "", t); insec = (t == sec); next }
		insec && /^[ \t]*\|/ { print }'
}

# sw_fmaint_lv AD: the first line of "## Last verified" of the record, without
# backticks ("never", "<commit>" or "<commit> <verdict>").
sw_fmaint_lv() {
	tr -d '\r' <"$SOFTWARY_ROOT/$SW_FORMAL_DIR/$1.md" | awk '
		/^##[ \t]/ { t = $0; sub(/^##[ \t]+/, "", t); sub(/[ \t]+$/, "", t); on = (t == "Last verified"); next }
		on && $0 ~ /[^ \t]/ { v = $0; gsub(/`/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }'
}

# sw_fmaint_covered AD: the coverage rows that are not `planned`, one per line:
# "<path><TAB><functions>".
sw_fmaint_covered() {
	sw_formal_table "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$1.md" Coverage |
		awk -F'|' '$1 == "R" && $2 != "" && $2 != "planned" { print $2 "\t" $3 }'
}

# sw_fmaint_has_word PATH WORD: true when WORD is a word of PATH (a file, or
# any file under a directory): not part of a longer name.
sw_fmaint_has_word() {
	grep -rFhI -e "$2" "$1" 2>/dev/null | W=$2 awk '
		function hasword(text, w,   p, i, at, b, a) {
			p = 1
			while ((i = index(substr(text, p), w)) > 0) {
				at = p + i - 1
				b = (at > 1) ? substr(text, at - 1, 1) : ""
				a = substr(text, at + length(w), 1)
				if (b !~ /[A-Za-z0-9_]/ && a !~ /[A-Za-z0-9_]/) return 1
				p = at + 1
			}
			return 0
		}
		hasword($0, ENVIRON["W"]) { found = 1; exit }
		END { exit !found }'
}

# sw_fmaint_coverage_problems AD: one line for each coverage row whose path is
# not there and each function that is not a word of its file.
sw_fmaint_coverage_problems() {
	_fm_ad=$1
	while IFS='	' read -r _fm_p _fm_fns; do
		[ -n "$_fm_p" ] || continue
		case $_fm_p in
		/* | .. | ../* | */.. | */../*)
			printf 'formal %s: coverage path %s does not exist\n' "$_fm_ad" "$_fm_p"
			continue
			;;
		esac
		if [ ! -e "$SOFTWARY_ROOT/$_fm_p" ]; then
			printf 'formal %s: coverage path %s does not exist\n' "$_fm_ad" "$_fm_p"
			continue
		fi
		while IFS= read -r _fm_f; do
			_fm_f=$(sw_trim "$_fm_f")
			_fm_f=${_fm_f%'()'}
			case $_fm_f in '' | -) continue ;; esac
			sw_fmaint_has_word "$SOFTWARY_ROOT/$_fm_p" "$_fm_f" ||
				printf 'formal %s: coverage function %s not found in %s\n' "$_fm_ad" "$_fm_f" "$_fm_p"
		done <<FUNCTIONS
$(printf '%s\n' "$_fm_fns" | tr ',' '\n')
FUNCTIONS
	done <<ROWS
$(sw_fmaint_covered "$_fm_ad")
ROWS
}

# --- stale models ---------------------------------------------------------------

# sw_fmaint_paths AD KIND: the paths a record's staleness is judged by, one per
# line (pathspecs): KIND all, the covered paths and the model; KIND model, the
# model and its configurations only.
sw_fmaint_paths() {
	[ "$2" != all ] || sw_fmaint_covered "$1" | cut -f1
	printf '%s\n' "$SW_FORMAL_DIR/$1.tla" "$SW_FORMAL_DIR/$1.cfg" "$SW_FORMAL_DIR/$1-*.cfg"
}

# sw_fmaint_changed AD REF [KIND]: the paths of the stale set (KIND, see
# sw_fmaint_paths; default all) that differ from commit REF, working tree
# included, untracked files too; "## Coverage" when the table of the record
# differs; one per line, sorted.
sw_fmaint_changed() {
	_fm_ref=$2
	_fm_rec=$SW_FORMAL_DIR/$1.md
	_fm_kind=${3:-all}
	set -f
	# shellcheck disable=SC2046 # the pathspecs are words, and globbing is off
	set -- $(sw_fmaint_paths "$1" "$_fm_kind")
	set +f
	{
		git -C "$SOFTWARY_ROOT" -c core.quotePath=false diff --no-renames --name-only "$_fm_ref" -- "$@" 2>/dev/null
		git -C "$SOFTWARY_ROOT" -c core.quotePath=false ls-files --others --exclude-standard -- "$@" 2>/dev/null
		if [ "$_fm_kind" = all ]; then
			if ! git -C "$SOFTWARY_ROOT" cat-file -e "$_fm_ref:$_fm_rec" 2>/dev/null ||
				[ "$(sw_fmaint_section_raw Coverage <"$SOFTWARY_ROOT/$_fm_rec")" != "$(git -C "$SOFTWARY_ROOT" show "$_fm_ref:$_fm_rec" | sw_fmaint_section_raw Coverage)" ]; then
				printf '## Coverage\n'
			fi
		fi
	} | LC_ALL=C sort -u
}

# sw_fmaint_commit VALUE: true when VALUE is a 40-digit commit the repository has.
sw_fmaint_commit() {
	case $1 in
	*[!0-9a-f]* | '') return 1 ;;
	esac
	[ "${#1}" -eq 40 ] || return 1
	git -C "$SOFTWARY_ROOT" cat-file -e "$1^{commit}" 2>/dev/null
}

# sw_fmaint_stale_problems AD: the lines that say a model is not held to its
# code: never verified against code that is there, a commit that is not
# there, or something changed since the commit.
sw_fmaint_stale_problems() {
	_fm_ad=$1
	_fm_lv=$(sw_fmaint_lv "$_fm_ad")
	_fm_c=${_fm_lv%% *}
	if [ "$_fm_c" = never ]; then
		while IFS= read -r _fm_p; do
			[ -z "$_fm_p" ] || printf 'formal %s: never verified against %s\n' "$_fm_ad" "$_fm_p"
		done <<NEVER
$(sw_fmaint_covered "$_fm_ad" | cut -f1)
NEVER
		return 0
	fi
	# A value that is none of the forms is a problem of the record.
	case $_fm_c in *[!0-9a-f]* | '') return 0 ;; esac
	[ "${#_fm_c}" -eq 40 ] || return 0
	if ! sw_fmaint_commit "$_fm_c"; then
		printf 'formal %s: last verified commit %s is unknown\n' "$_fm_ad" "$(printf '%s' "$_fm_c" | cut -c1-7)"
		return 0
	fi
	_fm_ch=$(sw_fmaint_changed "$_fm_ad" "$_fm_c")
	[ -z "$_fm_ch" ] ||
		printf 'formal %s: stale since %s: %s changed; check the model and record a verdict (./softwary formal verified %s compatible|updated)\n' \
			"$_fm_ad" "$(printf '%s' "$_fm_c" | cut -c1-7)" "$(printf '%s\n' "$_fm_ch" | paste -sd' ' -)" "$_fm_ad"
}

# --- formal verified ------------------------------------------------------------

sw_fmaint_verified_usage() {
	printf 'usage: ./softwary formal verified <spec> compatible|updated\n' >&2
}

# sw_fmaint_verified AD VERDICT: records that the model was checked against the
# code as it is at HEAD, and says how it stands: compatible (the model still
# describes the code) or updated (the model was changed to). Writes only the
# first line of "## Last verified"; nothing is written when a condition fails.
sw_fmaint_verified() {
	[ $# -eq 2 ] || { sw_fmaint_verified_usage; return 2; }
	_fv_ad=$1
	_fv_verdict=$2
	case $_fv_verdict in
	compatible | updated) ;;
	bug | blocked)
		printf 'formal verified: bug and blocked go to the human (./softwary job escalate <job> <question>)\n'
		return 2
		;;
	*)
		sw_fmaint_verified_usage
		return 2
		;;
	esac
	if ! sw_formal_names | grep -Fqx -e "$_fv_ad" || [ ! -f "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$_fv_ad.md" ]; then
		printf "formal verified: no specification '%s' (see architecture/formal/)\n" "$_fv_ad"
		return 2
	fi
	if ! _fv_head=$(git -C "$SOFTWARY_ROOT" rev-parse -q --verify HEAD 2>/dev/null); then
		printf 'formal verified: there is no commit yet; commit the code and the model first\n'
		return 1
	fi
	_fv_rec=$SOFTWARY_ROOT/$SW_FORMAL_DIR/$_fv_ad.md
	_fv_lv=$(sw_fmaint_lv "$_fv_ad")
	if [ -z "$_fv_lv" ]; then
		printf "formal verified: %s/%s.md has no '## Last verified' line\n" "$SW_FORMAL_DIR" "$_fv_ad"
		return 2
	fi
	# 1. what the verdict is about is committed
	_fv_dirty=$(sw_fmaint_changed "$_fv_ad" HEAD)
	if [ -n "$_fv_dirty" ]; then
		printf 'formal verified: uncommitted changes in %s; commit them first\n' "$(printf '%s\n' "$_fv_dirty" | paste -sd' ' -)"
		return 1
	fi
	# 2. the model passes (the checks of the record and of the model, not the age)
	_fv_rc=0
	_fv_out=$(SW_FORMAL_NOSTALE=1 sw_formal_check "$_fv_ad") || _fv_rc=$?
	if [ "$_fv_rc" -ne 0 ]; then
		printf '%s\n' "$_fv_out"
		[ "$_fv_rc" -eq 2 ] || printf 'formal verified: formal check %s fails; nothing was written\n' "$_fv_ad"
		return "$_fv_rc"
	fi
	# 3. the verdict is what the files say
	_fv_c=${_fv_lv%% *}
	if [ "$_fv_c" != never ]; then
		if ! sw_fmaint_commit "$_fv_c"; then
			printf "formal verified: last verified commit %s is unknown; write never in '## Last verified' to start again\n" "$(printf '%s' "$_fv_c" | cut -c1-7)"
			return 1
		fi
		_fv_mc=$(sw_fmaint_changed "$_fv_ad" "$_fv_c" model)
		if [ "$_fv_verdict" = compatible ] && [ -n "$_fv_mc" ]; then
			printf 'formal verified: compatible needs the model to be unchanged since %s, but %s changed; use updated\n' \
				"$(printf '%s' "$_fv_c" | cut -c1-7)" "$(printf '%s\n' "$_fv_mc" | paste -sd' ' -)"
			return 1
		fi
		if [ "$_fv_verdict" = updated ] && [ -z "$_fv_mc" ]; then
			printf 'formal verified: updated needs the model to have changed since %s, but %s/%s.tla and its configurations are the same; use compatible\n' \
				"$(printf '%s' "$_fv_c" | cut -c1-7)" "$SW_FORMAL_DIR" "$_fv_ad"
			return 1
		fi
	fi
	# the record: its first line of '## Last verified' only
	_fv_tmp=$(mktemp "${TMPDIR:-/tmp}/softwary-verified.XXXXXX") || return 2
	awk -v v="$_fv_head $_fv_verdict" '
		/^##[ \t]/ { t = $0; sub(/^##[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t); on = (t == "Last verified"); print; next }
		on && !done && $0 ~ /[^ \t\r]/ { print v ($0 ~ /\r$/ ? "\r" : ""); done = 1; next }
		{ print }' "$_fv_rec" >"$_fv_tmp" || { rm -f "$_fv_tmp"; return 2; }
	cat "$_fv_tmp" >"$_fv_rec" || { rm -f "$_fv_tmp"; return 2; }
	rm -f "$_fv_tmp"
	_fv_s7=$(printf '%s' "$_fv_head" | cut -c1-7)
	sw_event - formal_verified - - "$_fv_ad $_fv_verdict $_fv_s7" || return 2
	printf 'formal verified: %s %s (%s)\n' "$_fv_ad" "$_fv_verdict" "$_fv_s7"
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
