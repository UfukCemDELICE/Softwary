# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_DRIFT_* globals are read by ship.sh
# softwary: `drift` (V7). Sourced by bin/softwary. POSIX sh.
#
# The blueprint says where each component lives (a node's metadata.paths) and
# which product examples are tested; the code says otherwise sooner or later.
# `drift` lists the differences, one item per line, and the decision the
# human took about each one (architecture/drift.md, a protected path):
#   uncovered <path>              a tracked file under src_paths no node owns
#   missing <node> <path>         a path of a node that is not there
#   empty <node>                  an active node that has no file
#   planned-with-code <node>      a planned node that has code
#   unexercised <EX>              a product example no test names
#   untested <ST-...>             a test a state machine owes that no test names
#   unreplayed <CE-...>           a finding no test replays
# An item without a valid decision, or whose decision has expired, fails
# drift (exit 1); the loop does not look at it, `ship` does (ship.sh).

SW_DRIFT_REL=architecture/drift.md
# What softwary writes or generates is never an item, also with src_paths = .
SW_DRIFT_GENERATED=".softwary/ .claude/ .cursor/ .agents/ .codex/ architecture/views/"

sw_drift_usage() {
	printf 'usage: ./softwary drift\n' >&2
}

# sw_drift_nodes: one line for each node that has paths: its id, its status
# (none when it has none) and its paths, separated by tabs.
sw_drift_nodes() {
	jq -r '.nodes[]? | objects
		| (.metadata | if type == "array" then add // {} else . // {} end) as $m
		| select(($m.paths | type) == "array")
		| [."unique-id", ($m.status // "none")] + $m.paths | join("\t")' "$SOFTWARY_ROOT/$SW_MODEL_REL"
}

# sw_drift_covered ENTRIES FILE: true when one of ENTRIES (one per line) covers
# FILE (the rule of the touches: a pattern, or a path and what is below it).
sw_drift_covered() {
	while IFS= read -r _dc_e; do
		[ -n "$_dc_e" ] || continue
		sw_guard_covers "$_dc_e" "$2" && return 0
	done <<DRIFT_ENTRIES
$1
DRIFT_ENTRIES
	return 1
}

# sw_drift_exists ENTRY: true when ENTRY names something: a path that is
# there, or a pattern that matches a file (SW_DRIFT_ALL, the tracked and the
# untracked files).
sw_drift_exists() {
	case $1 in
	*[*?[]*) ;;
	*)
		_de=${1#./}
		_de=${_de%/}
		[ -e "$SOFTWARY_ROOT/$_de" ] && return 0
		;;
	esac
	while IFS= read -r _de_f; do
		[ -n "$_de_f" ] || continue
		sw_guard_covers "$1" "$_de_f" && return 0
	done <<DRIFT_ALL
$SW_DRIFT_ALL
DRIFT_ALL
	return 1
}

# sw_drift_add ITEM: records an item.
sw_drift_add() {
	SW_DRIFT_ITEMS="${SW_DRIFT_ITEMS}$1
"
}

# sw_drift_rows: the decisions of architecture/drift.md, one line each: the
# item, the decision, the date and the reason, separated by tabs. The table
# is the one with the columns Item, Decision, Until, Reason.
sw_drift_rows() {
	[ -f "$SOFTWARY_ROOT/$SW_DRIFT_REL" ] || return 0
	tr -d '\r' <"$SOFTWARY_ROOT/$SW_DRIFT_REL" | awk -F'|' '
		function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
		finished { next }
		!intable {
			h = $0
			gsub(/[ \t]/, "", h)
			if (h == "|Item|Decision|Until|Reason|") intable = 1
			next
		}
		$0 !~ /^[ \t]*\|/ { finished = 1; next }
		{
			item = trim($2)
			if (item == "" || item ~ /^:?-+:?$/) next
			print item "\t" trim($3) "\t" trim($4) "\t" trim($5)
		}'
}

# sw_drift_row_problem DECISION UNTIL REASON: prints why the row decides
# nothing; nothing when it is a decision.
sw_drift_row_problem() {
	case $1 in
	accept | blueprint) ;;
	fix)
		printf 'fix needs a spec number'
		return 0
		;;
	fix[[:space:]]*)
		_dp_s=$(sw_trim "${1#fix}")
		if ! sw_plan_spec_dir "$_dp_s" >/dev/null; then
			printf 'fix %s: no such spec' "$_dp_s"
			return 0
		fi
		;;
	*)
		printf "decision '%s' is not accept, blueprint or fix <spec>" "$1"
		return 0
		;;
	esac
	if ! sw_valid_date "$2"; then
		printf "invalid date '%s' (use YYYY-MM-DD)" "$2"
		return 0
	fi
	[ -n "$3" ] || printf 'no reason'
}

# sw_drift_items: puts every item in SW_DRIFT_ITEMS (one per line). Returns 2,
# with the reason printed, when the project cannot be looked at.
sw_drift_items() {
	SW_DRIFT_ITEMS=
	_di_rc=0
	sw_model_check >/dev/null || _di_rc=$?
	case $_di_rc in
	2)
		printf 'drift: no model (%s)\n' "$SW_MODEL_MISSING"
		return 2
		;;
	1)
		printf 'drift: the model is invalid; run ./softwary model validate\n'
		return 2
		;;
	esac
	sw_conf_load "$SOFTWARY_ROOT/$SW_CONF_REL"
	if [ "$SW_CONF_FOUND" -eq 0 ]; then
		printf 'drift: %s not found; run install.sh or ./softwary doctor\n' "$SW_CONF_REL"
		return 2
	fi
	if [ -n "$SW_CONF_ERRORS" ]; then
		printf '%s' "$SW_CONF_ERRORS"
		return 2
	fi
	_di_p=$(sw_src_paths_problems)
	if [ -n "$_di_p" ]; then
		printf '%s\n' "$_di_p" | sed 's/^/drift: src_paths: /; s/^drift: src_paths: not set/drift: src_paths is not set/'
		return 2
	fi
	_di_src=$(sw_conf_get src_paths)
	_di_nodes=$(sw_drift_nodes)
	_di_trk=$(git -C "$SOFTWARY_ROOT" -c core.quotePath=false ls-files)
	SW_DRIFT_ALL=$(
		printf '%s\n' "$_di_trk"
		git -C "$SOFTWARY_ROOT" -c core.quotePath=false ls-files --others --exclude-standard
	)
	_di_ents=$(printf '%s\n' "$_di_nodes" | awk -F '\t' '{ for (i = 3; i <= NF; i++) print $i }')
	# uncovered: the code no node owns
	while IFS= read -r _di_f; do
		[ -n "$_di_f" ] || continue
		sw_scoped_under "$_di_f" "$SW_DRIFT_GENERATED" && continue
		sw_scoped_under "$_di_f" "$_di_src" || continue
		sw_drift_covered "$_di_ents" "$_di_f" || sw_drift_add "uncovered $_di_f"
	done <<DRIFT_TRACKED
$_di_trk
DRIFT_TRACKED
	# missing: a path of a node that has been built (a planned node has no
	# code yet)
	while IFS='	' read -r _di_id _di_st _di_rest; do
		[ -n "$_di_id" ] && [ "$_di_st" != planned ] || continue
		while IFS= read -r _di_e; do
			[ -n "$_di_e" ] || continue
			sw_drift_exists "$_di_e" || sw_drift_add "missing $_di_id $_di_e"
		done <<DRIFT_PATHS
$(printf '%s\n' "$_di_rest" | tr '\t' '\n')
DRIFT_PATHS
	done <<DRIFT_NODES
$_di_nodes
DRIFT_NODES
	# empty and planned-with-code: files the node owns, or none
	while IFS='	' read -r _di_id _di_st _di_rest; do
		[ -n "$_di_id" ] || continue
		case $_di_st in active | planned) ;; *) continue ;; esac
		_di_own=$(printf '%s\n' "$_di_rest" | tr '\t' '\n')
		_di_has=0
		while IFS= read -r _di_f; do
			[ -n "$_di_f" ] || continue
			if sw_drift_covered "$_di_own" "$_di_f"; then
				_di_has=1
				break
			fi
		done <<DRIFT_FILES
$SW_DRIFT_ALL
DRIFT_FILES
		if [ "$_di_st" = active ] && [ "$_di_has" -eq 0 ]; then
			sw_drift_add "empty $_di_id"
		elif [ "$_di_st" = planned ] && [ "$_di_has" -eq 1 ]; then
			sw_drift_add "planned-with-code $_di_id"
		fi
	done <<DRIFT_NODES2
$_di_nodes
DRIFT_NODES2
	sw_drift_unexercised || return $?
	sw_drift_obligations
}

# sw_drift_obligations: adds `untested ST-...` for every test a state machine
# owes (`states tests`) and `unreplayed CE-...` for every finding of a record
# whose identifier no tracked file under test_paths names (as a word). Returns
# 2 when there are such obligations and test_paths cannot be looked at.
sw_drift_obligations() {
	_do_st=$(sw_fmaint_obligations | cut -d' ' -f1)
	_do_ce=$(sw_fmaint_ce_ids)
	[ -n "$_do_st$_do_ce" ] || return 0
	_do_tp=
	! sw_conf_has test_paths || _do_tp=$(sw_conf_get test_paths)
	case $_do_tp in
	'' | UNSET | NONE*)
		printf 'drift: test_paths is not set in %s (the state machines and findings need it)\n' "$SW_CONF_REL"
		return 2
		;;
	esac
	_do_found=$(sw_fmaint_test_ids "$_do_tp")
	while IFS= read -r _do_id; do
		[ -n "$_do_id" ] || continue
		printf '%s\n' "$_do_found" | grep -Fqx -e "$_do_id" || sw_drift_add "untested $_do_id"
	done <<DRIFT_ST
$_do_st
DRIFT_ST
	while IFS= read -r _do_id; do
		[ -n "$_do_id" ] || continue
		printf '%s\n' "$_do_found" | grep -Fqx -e "$_do_id" || sw_drift_add "unreplayed $_do_id"
	done <<DRIFT_CE
$_do_ce
DRIFT_CE
}

# sw_drift_unexercised: adds `unexercised <EX>` for every product example none
# of whose criteria is named by a file under test_paths. Returns 2 when there
# are examples and test_paths cannot be looked at.
sw_drift_unexercised() {
	_du_ex=$(sw_product_examples)
	[ -n "$_du_ex" ] || return 0
	_du_tp=
	! sw_conf_has test_paths || _du_tp=$(sw_conf_get test_paths)
	case $_du_tp in
	'' | UNSET | NONE*)
		printf 'drift: test_paths is not set in %s (the examples need it)\n' "$SW_CONF_REL"
		return 2
		;;
	esac
	_du_found=
	for _du_p in $_du_tp; do
		[ -e "$SOFTWARY_ROOT/$_du_p" ] || continue
		_du_found="$_du_found
$(cd "$SOFTWARY_ROOT" && find "$_du_p" -type f -exec grep -hoE 'AC-[0-9]{3}-[0-9]{2}' {} + 2>/dev/null)"
	done
	_du_found=$(printf '%s\n' "$_du_found" | sort -u)
	_du_links=
	for _du_s in "$SOFTWARY_ROOT"/specs/*/spec.md; do
		[ -f "$_du_s" ] || continue
		_du_links="$_du_links
$(sw_plan_criteria "$_du_s")"
	done
	while IFS= read -r _du_e; do
		[ -n "$_du_e" ] || continue
		_du_hit=0
		for _du_a in $(printf '%s\n' "$_du_links" | awk -v e="$_du_e" '$2 == e { print $1 }'); do
			if printf '%s\n' "$_du_found" | grep -Fqx -e "$_du_a"; then
				_du_hit=1
				break
			fi
		done
		[ "$_du_hit" -eq 1 ] || sw_drift_add "unexercised $_du_e"
	done <<DRIFT_EXAMPLES
$_du_ex
DRIFT_EXAMPLES
}

# sw_drift_run: works out the items and what was decided about each. Sets
# SW_DRIFT_OUT (one `drift: <item>: <state>` line for each item, then each
# stale decision), SW_DRIFT_N (the items), SW_DRIFT_BAD (those without a valid
# decision or with an expired one) and SW_DRIFT_INFORCE (a line for each
# decision in force). Returns 2, the reason printed, when drift cannot run.
sw_drift_run() {
	SW_DRIFT_OUT='' SW_DRIFT_N=0 SW_DRIFT_BAD=0 SW_DRIFT_INFORCE=''
	sw_drift_items || return $?
	_dr_rows=$(sw_drift_rows)
	while IFS= read -r _dr_item; do
		[ -n "$_dr_item" ] || continue
		SW_DRIFT_N=$((SW_DRIFT_N + 1))
		_dr_mine=$(printf '%s\n' "$_dr_rows" | _dr_i=$_dr_item awk -F '\t' '$1 == ENVIRON["_dr_i"]')
		if [ -z "$_dr_mine" ]; then
			_dr_state=undecided
		elif [ "$(sw_count "$_dr_mine")" -gt 1 ]; then
			_dr_state="undecided (more than one decision row)"
		else
			_dr_dec=$(printf '%s\n' "$_dr_mine" | cut -f2)
			_dr_until=$(printf '%s\n' "$_dr_mine" | cut -f3)
			_dr_why=$(printf '%s\n' "$_dr_mine" | cut -f4)
			_dr_prob=$(sw_drift_row_problem "$_dr_dec" "$_dr_until" "$_dr_why")
			if [ -n "$_dr_prob" ]; then
				_dr_state="undecided ($_dr_prob)"
			elif [ "$(sw_days_left "$_dr_until")" -lt 0 ]; then
				_dr_state="expired $_dr_until"
			else
				_dr_state="decided ($_dr_dec, until $_dr_until)"
				SW_DRIFT_INFORCE="${SW_DRIFT_INFORCE}- $_dr_item: $_dr_dec (until $_dr_until): $_dr_why
"
			fi
		fi
		case $_dr_state in decided*) ;; *) SW_DRIFT_BAD=$((SW_DRIFT_BAD + 1)) ;; esac
		SW_DRIFT_OUT="${SW_DRIFT_OUT}drift: $_dr_item: $_dr_state
"
	done <<DRIFT_ITEMS
$SW_DRIFT_ITEMS
DRIFT_ITEMS
	# decisions about what is no longer there
	while IFS= read -r _dr_item; do
		[ -n "$_dr_item" ] || continue
		printf '%s\n' "$SW_DRIFT_ITEMS" | grep -Fqx -e "$_dr_item" ||
			SW_DRIFT_OUT="${SW_DRIFT_OUT}drift: $_dr_item: stale decision (remove it)
"
	done <<DRIFT_ROWS
$(printf '%s\n' "$_dr_rows" | cut -f1 | LC_ALL=C sort -u)
DRIFT_ROWS
	return 0
}

# sw_drift: the command.
sw_drift() {
	[ $# -eq 0 ] || { sw_drift_usage; return 2; }
	sw_drift_run || return $?
	printf '%s' "$SW_DRIFT_OUT"
	printf 'drift: %s item(s), %s undecided\n' "$SW_DRIFT_N" "$SW_DRIFT_BAD"
	[ "$SW_DRIFT_BAD" -eq 0 ]
}
