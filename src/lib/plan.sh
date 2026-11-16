# shellcheck shell=sh
# softwary: `plan check` and `plan approve`. Sourced by bin/softwary. POSIX sh.
#
# A plan is the specs under specs/ with their slices. `plan check` adds to
# `trace` the approvals, the links from criteria to product examples and the
# order of the slices; `plan approve` approves a draft spec on the strength of
# the spec-analyst's record, specs/NNN-<name>/analysis.md.

# sw_plan_criteria SPEC_FILE: prints "<criterion id> <example id or ->" for
# every criterion item (- **AC-NNN-NN:** ...) of the spec's body, one line
# per example the item names.
sw_plan_criteria() {
	tr -d '\r' <"$1" | awk '
		function flush(   s, i) {
			if (id == "") return
			s = text; found = 0
			while (match(s, /EX-F[0-9][0-9]*-[0-9][0-9]/)) {
				print id " " substr(s, RSTART, RLENGTH); found = 1
				s = substr(s, RSTART + RLENGTH)
			}
			if (!found) print id " -"
			id = ""
		}
		NR == 1 && $0 == "---" { infm = 1; next }
		infm { if ($0 == "---") infm = 0; next }
		/^[ \t]*[-*+][ \t]+\*\*AC-[0-9][0-9][0-9]-[0-9][0-9]:\*\*/ {
			flush()
			match($0, /AC-[0-9][0-9][0-9]-[0-9][0-9]/)
			id = substr($0, RSTART, RLENGTH); text = $0
			next
		}
		/^[ \t]+[^ \t]/ && id != "" && !/^[ \t]*([-*+]|[0-9]+\.)[ \t]/ { text = text " " $0; next }
		{ flush() }
		END { flush() }'
}

# sw_plan_order SPECS: reads "N <slice>" and "E <slice> <dependency>" lines
# from stdin and prints, one per line, the slices that cannot be put in
# order: those in a dependency cycle and those that depend on one.
sw_plan_unordered() {
	awk '
		$1 == "N" { node[$2] = 1; order[++n] = $2; next }
		$1 == "E" { from[++m] = $2; to[m] = $3 }
		END {
			do {
				changed = 0
				for (i = 1; i <= n; i++) {
					x = order[i]
					if (x in done) continue
					ok = 1
					for (j = 1; j <= m; j++)
						if (from[j] == x && (to[j] in node) && !(to[j] in done)) { ok = 0; break }
					if (ok) { done[x] = 1; changed = 1 }
				}
			} while (changed)
			for (i = 1; i <= n; i++) if (!(order[i] in done)) print order[i]
		}'
}

# sw_plan_problems [SPECDIR]: prints the problems of the plan, one per line;
# with SPECDIR (a directory name under specs/) only those that concern that
# spec, and the approvals. Returns 0 clean, 1 problems.
sw_plan_problems() {
	_pl_only=${1-}
	_pl_out=
	for _pl_k in $SW_APPROVAL_KINDS; do
		_pl_s=$(sw_approval_state "$_pl_k")
		[ "$_pl_s" = approved ] ||
			_pl_out="${_pl_out}$_pl_k: approval is $_pl_s (run ./softwary approve $_pl_k)
"
	done
	_pl_examples=$(sw_product_examples)
	_pl_nodes=
	_pl_edges=
	for _pl_dir in "$SOFTWARY_ROOT"/specs/*/; do
		[ -f "${_pl_dir}spec.md" ] || continue
		_pl_dir=${_pl_dir%/}
		_pl_dn=${_pl_dir##*/}
		_pl_id=${_pl_dn%%-*}
		sw_fm_read "$_pl_dir/spec.md"
		_pl_status=$(sw_fm_get status)
		if { [ -z "$_pl_only" ] || [ "$_pl_only" = "$_pl_dn" ]; } && { [ "$_pl_status" = draft ] || [ "$_pl_status" = approved ]; }; then
			_pl_rel=specs/$_pl_dn/spec.md
			_pl_links=$(sw_plan_criteria "$_pl_dir/spec.md")
			while read -r _pl_ac _pl_ex; do
				[ -n "$_pl_ac" ] || continue
				if [ "$_pl_ex" = - ]; then
					_pl_out="${_pl_out}$_pl_rel: $_pl_ac: no example link (name an EX-F<n>-NN of $SW_PRODUCT_REL)
"
				elif ! printf '%s\n' "$_pl_examples" | grep -Fqx -e "$_pl_ex"; then
					_pl_out="${_pl_out}$_pl_rel: $_pl_ac: unknown example $_pl_ex
"
				fi
			done <<LINKS
$_pl_links
LINKS
			if [ "$_pl_status" = draft ]; then
				sw_spec_open_questions "$_pl_dir/spec.md" &&
					_pl_out="${_pl_out}$_pl_rel: open questions: a spec must have none to be approved
"
				_pl_words=$(wc -w <"$_pl_dir/spec.md" | tr -d ' ')
				[ "$_pl_words" -le "$SW_SPEC_MAX_WORDS" ] ||
					_pl_out="${_pl_out}$_pl_rel: $_pl_words words; a spec must be at most $SW_SPEC_MAX_WORDS to be approved
"
			fi
		fi
		for _pl_sf in "$_pl_dir"/slices/*.md; do
			[ -f "$_pl_sf" ] || continue
			_pl_sn=${_pl_sf##*/}
			_pl_sn=${_pl_sn%.md}
			_pl_nodes="${_pl_nodes}N $_pl_id-$_pl_sn
"
			sw_fm_read "$_pl_sf"
			for _pl_d in $(sw_list "$(sw_fm_get depends_on)"); do
				case $_pl_d in S*) _pl_d=$_pl_id-$_pl_d ;; esac
				_pl_edges="${_pl_edges}E $_pl_id-$_pl_sn $_pl_d
"
			done
		done
	done
	_pl_un=$(printf '%s%s' "$_pl_nodes" "$_pl_edges" | sw_plan_unordered)
	if [ -n "$_pl_un" ]; then
		_pl_mine=1
		if [ -n "$_pl_only" ]; then
			_pl_mine=$(printf '%s\n' "$_pl_un" | awk -v p="${_pl_only%%-*}-" 'index($0, p) == 1 { f = 1 } END { print f + 0 }')
		fi
		[ "$_pl_mine" -eq 0 ] ||
			_pl_out="${_pl_out}plan: dependency cycle among: $(printf '%s\n' "$_pl_un" | LC_ALL=C sort | paste -sd' ' -)
"
	fi
	_pl_rc=0
	_pl_tr=$(sw_trace) || _pl_rc=$?
	_pl_tr=$(printf '%s\n' "$_pl_tr" | grep -Ev '^trace: [0-9]+ ' || :)
	if [ -n "$_pl_only" ]; then
		_pl_tr=$(printf '%s\n' "$_pl_tr" | awk -v a="specs/$_pl_only/" -v b="specs/$_pl_only:" 'index($0, a) == 1 || index($0, b) == 1')
	fi
	[ -z "$_pl_tr" ] || _pl_out="${_pl_out}$_pl_tr
"
	[ -z "$_pl_out" ] || printf '%s' "$_pl_out"
	[ -z "$_pl_out" ]
}

# sw_plan_spec_dir ARG: prints the directory name under specs/ for a spec id
# (001) or directory name (001-login, specs/001-login).
sw_plan_spec_dir() {
	_pl_a=${1#specs/}
	_pl_a=${_pl_a%/}
	if printf '%s\n' "$_pl_a" | grep -Eq '^[0-9]{3}$'; then
		for _pl_d in "$SOFTWARY_ROOT/specs/$_pl_a"-*/; do
			[ -f "${_pl_d}spec.md" ] || continue
			_pl_d=${_pl_d%/}
			printf '%s\n' "${_pl_d##*/}"
			return 0
		done
		return 1
	fi
	[ -f "$SOFTWARY_ROOT/specs/$_pl_a/spec.md" ] || return 1
	printf '%s\n' "$_pl_a"
}

sw_plan_check() {
	if ! _pl_ap=$(sw_approvals_problems); then
		printf '%s\n' "$_pl_ap"
		return 2
	fi
	_pl_rc=0
	_pl_probs=$(sw_plan_problems) || _pl_rc=$?
	if [ "$_pl_rc" -eq 0 ]; then
		_pl_n=0
		for _pl_d in "$SOFTWARY_ROOT"/specs/*/spec.md; do
			[ -f "$_pl_d" ] && _pl_n=$((_pl_n + 1))
		done
		if [ "$_pl_n" -eq 1 ]; then printf 'plan: clean (1 spec)\n'; else printf 'plan: clean (%s specs)\n' "$_pl_n"; fi
		return 0
	fi
	printf '%s\n' "$_pl_probs"
	printf 'plan: %s problem(s)\n' "$(sw_count "$_pl_probs")"
	return 1
}

# sw_plan_refuse MESSAGE: a refusal of `plan approve`.
sw_plan_refuse() {
	printf 'plan approve: %s\n' "$1"
	return 1
}

# sw_plan_approve SPEC: a draft spec whose plan is clean and whose analysis
# passes, for exactly this version of the spec, becomes approved.
sw_plan_approve() {
	if [ $# -ne 1 ]; then
		printf 'usage: ./softwary plan check | plan approve <spec>\n' >&2
		return 2
	fi
	if ! _pl_dn=$(sw_plan_spec_dir "$1"); then
		printf 'plan approve: no spec %s under specs/\n' "$1"
		return 2
	fi
	if ! _pl_ap=$(sw_approvals_problems); then
		printf '%s\n' "$_pl_ap"
		return 2
	fi
	_pl_sf=$SOFTWARY_ROOT/specs/$_pl_dn/spec.md
	_pl_id=${_pl_dn%%-*}
	sw_fm_read "$_pl_sf"
	_pl_status=$(sw_fm_get status)
	[ "$_pl_status" = draft ] || { sw_plan_refuse "spec $_pl_id is ${_pl_status:-unreadable}, not draft"; return 1; }
	_pl_rc=0
	_pl_probs=$(sw_plan_problems "$_pl_dn") || _pl_rc=$?
	if [ "$_pl_rc" -ne 0 ]; then
		printf '%s\n' "$_pl_probs"
		sw_plan_refuse "plan check reports problems for spec $_pl_id"
		return 1
	fi
	_pl_af=$SOFTWARY_ROOT/specs/$_pl_dn/analysis.md
	[ -f "$_pl_af" ] || { sw_plan_refuse "no analysis.md for spec $_pl_id; run the spec-analyst first"; return 1; }
	sw_fm_read "$_pl_af"
	[ "$(sw_fm_get spec)" = "$_pl_id" ] ||
		{ sw_plan_refuse "analysis is of spec $(sw_fm_get spec), not $_pl_id"; return 1; }
	[ "$(sw_fm_get decision)" = pass ] ||
		{ sw_plan_refuse "analysis decision is $(sw_fm_get decision), not pass"; return 1; }
	[ "$(sw_fm_get digest)" = "$(git -C "$SOFTWARY_ROOT" hash-object -- "specs/$_pl_dn/spec.md")" ] ||
		{ sw_plan_refuse "analysis is of another version of the spec; run the spec-analyst again"; return 1; }
	awk '
		NR == 1 { print; next }
		!closed && $0 ~ /^---[ \t\r]*$/ { closed = 1 }
		!closed && !done && /^status:[ \t]*draft[ \t\r]*$/ {
			print "status: approved" ($0 ~ /\r$/ ? "\r" : ""); done = 1; next
		}
		{ print }' "$_pl_sf" >"$_pl_sf.tmp" || return 2
	cat "$_pl_sf.tmp" >"$_pl_sf"
	rm -f "$_pl_sf.tmp"
	sw_event - plan_approve - - "$_pl_dn" || return 2
	printf 'plan approve: spec %s approved\n' "$_pl_id"
}

# sw_plan check | approve <spec>
sw_plan() {
	case ${1:-} in
	check)
		[ $# -eq 1 ] || { printf 'usage: ./softwary plan check | plan approve <spec>\n' >&2; return 2; }
		sw_plan_check
		;;
	approve)
		shift
		sw_plan_approve "$@"
		;;
	*)
		printf 'usage: ./softwary plan check | plan approve <spec>\n' >&2
		return 2
		;;
	esac
}
