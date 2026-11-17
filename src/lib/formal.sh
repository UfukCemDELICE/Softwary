# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: formal specifications (V5). Sourced by bin/softwary and by
# tests/tlc.sh. POSIX sh.
#
# architecture/formal/<ad>.tla is the TLA+ model, <ad>.cfg the configuration
# of the model as it should be, <ad>-<variant>.cfg a broken variant and
# <ad>.md the record: the invariants as plain sentences, the actions, what
# code is covered, bounds and assumptions, the commit last verified and the
# variants. `blueprint check` checks the records; `formal check` runs TLC.

SW_FORMAL_DIR=architecture/formal
SW_FORMAL_SECTIONS="Invariants|Actions|Coverage|Bounds and assumptions|Last verified|Variants"

# --- the record (<ad>.md) -----------------------------------------------------

# sw_formal_table FILE SECTION: the table under "## SECTION" of a record, one
# line per row: "H|<cell>|<cell>" for the header, "R|<cell>|..." for a row.
# Backticks and the blanks around a cell are dropped.
sw_formal_table() {
	tr -d '\r' <"$1" | awk -v sec="$2" '
		/^##[ \t]/ { t = $0; sub(/^##[ \t]+/, "", t); sub(/[ \t]+$/, "", t); insec = (t == sec); hdr = 0; next }
		insec && /^[ \t]*\|/ {
			line = $0; sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
			n = split(line, c, "|"); out = ""; sepl = 1
			for (i = 1; i <= n; i++) {
				v = c[i]; gsub(/`/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
				if (v !~ /^:?-+:?$/) sepl = 0
				out = out "|" v
			}
			if (sepl) next
			print (hdr ? "R" : "H") out; hdr = 1
		}'
}

# sw_formal_invariants_raw FILE: the lines of the invariants table of a record
# exactly as written (what the blueprint approval binds).
sw_formal_invariants_raw() {
	tr -d '\r' <"$1" | awk '
		/^##[ \t]/ { t = $0; sub(/^##[ \t]+/, "", t); sub(/[ \t]+$/, "", t); insec = (t == "Invariants"); next }
		insec && /^[ \t]*\|/ { print }'
}

# sw_formal_actions FILE: the action names of a record, one per line.
sw_formal_actions() {
	sw_formal_table "$1" Actions | awk -F'|' '$1 == "R" && $2 != "" { print $2 }'
}

# sw_formal_record_problems AD FILES: the problems of the record
# architecture/formal/<AD>.md, one "<file>: <problem>" per line. FILES are the
# file names of architecture/formal/.
sw_formal_record_problems() {
	_fr_md=$SOFTWARY_ROOT/$SW_FORMAL_DIR/$1.md
	_fr_cfg=$SOFTWARY_ROOT/$SW_FORMAL_DIR/$1.cfg
	[ -f "$_fr_cfg" ] || _fr_cfg=
	tr -d '\r' <"$_fr_md" | awk -v ad="$1" -v rel="$SW_FORMAL_DIR/$1.md" -v cfgrel="$SW_FORMAL_DIR/$1.cfg" \
		-v cfg="$_fr_cfg" -v files="$2" -v secs="$SW_FORMAL_SECTIONS" '
		function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
		function prob(m) { print rel ": " m }
		function hasword(text, w,   p, i, a, b, at) {
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
		BEGIN {
			nsec = split(secs, want, "|")
			nf = split(files, fl, " "); for (i = 1; i <= nf; i++) have[fl[i]] = 1
			exphdr["Invariants"] = "Name|Statement|Harm"; exphdr["Actions"] = "Action|Statement"
			exphdr["Coverage"] = "Path|Functions"; exphdr["Variants"] = "File|Breaks"
			if (cfg != "") {
				while ((getline l < cfg) > 0) { sub(/\r$/, "", l); if (l !~ /^[ \t]*\\\*/) cfgtext = cfgtext "\n" l }
				close(cfg)
			}
		}
		/UNSET/ { prob("line " NR ": UNSET") }
		/^##[ \t]/ {
			sec = $0; sub(/^##[ \t]+/, "", sec); sub(/[ \t]+$/, "", sec)
			seen[sec] = 1; hdr = 0
			next
		}
		sec == "Bounds and assumptions" && /^[ \t]*[-*+][ \t]+[^ \t]/ { bounds++ }
		sec == "Last verified" && !lastdone && $0 ~ /[^ \t]/ { lastv = trim($0); gsub(/`/, "", lastv); lastdone = 1 }
		/^[ \t]*\|/ && (sec in exphdr) {
			line = $0; sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
			n = split(line, c, "|"); sepl = 1
			for (i = 1; i <= n; i++) { gsub(/`/, "", c[i]); c[i] = trim(c[i]); if (c[i] !~ /^:?-+:?$/) sepl = 0 }
			if (sepl) next
			if (!hdr) {
				hdr = 1; got = c[1]; for (i = 2; i <= n; i++) got = got "|" c[i]
				if (got != exphdr[sec]) { x = exphdr[sec]; gsub(/\|/, ", ", x); prob("'\''## " sec "'\'' table must have the columns " x) }
				next
			}
			rows[sec]++
			if (sec == "Invariants") {
				if (c[1] !~ /^[A-Za-z][A-Za-z0-9_]*$/) { prob("invariant name '\''" c[1] "'\'' is not an identifier"); next }
				if (c[1] in isinv) { prob("duplicate invariant '\''" c[1] "'\''"); next }
				isinv[c[1]] = 1; inv[++ninv] = c[1]
				if (c[2] == "") prob("invariant '\''" c[1] "'\'' has no statement")
				if (c[3] == "") prob("invariant '\''" c[1] "'\'' has no harm")
			} else if (sec == "Actions") {
				if (c[1] == "") prob("an action has no name")
				else if (c[2] == "") prob("action '\''" c[1] "'\'' has no statement")
			} else if (sec == "Coverage") {
				if (c[1] == "") prob("a coverage entry has no path")
				else if (c[1] != "planned" && (c[2] == "" || c[2] == "-")) prob("coverage '\''" c[1] "'\'' names no functions (or use '\''planned'\'')")
			} else if (sec == "Variants") {
				f = c[1]; b = c[2]
				if (f !~ ("^" ad "-[a-z][a-z0-9_]*\\.cfg$")) prob("variant file '\''" f "'\'' must be named " ad "-<variant>.cfg")
				if (!(f in have)) prob("variant file '\''" f "'\'' not found")
				if (!(b in isinv) && b != "") prob("variant '\''" f "'\'' breaks '\''" b "'\'', which is not in the invariants table")
				else if (b == "") prob("variant '\''" f "'\'' names no invariant it breaks")
				else broken[b] = 1
			}
		}
		END {
			for (i = 1; i <= nsec; i++) if (!(want[i] in seen)) prob("missing section '\''## " want[i] "'\''")
			for (s in exphdr) if ((s in seen) && !(s in rows)) prob("'\''## " s "'\'' has no entry")
			if (("Bounds and assumptions" in seen) && bounds == 0) prob("'\''## Bounds and assumptions'\'' has no item")
			if (("Last verified" in seen) && lastv != "never" && lastv !~ /^[0-9a-f]{40}$/) prob("'\''## Last verified'\'' must be a 40-digit commit or '\''never'\''")
			for (i = 1; i <= ninv; i++) {
				if (!(inv[i] in broken)) prob("invariant '\''" inv[i] "'\'' has no variant that breaks it")
				if (cfg != "" && !hasword(cfgtext, inv[i]))
					print cfgrel ": invariant '\''" inv[i] "'\'' of " ad ".md is not checked (list it under INVARIANTS or PROPERTIES)"
			}
		}'
}

# sw_formal_refs: "<ad> <file>" for every flow or state machine that names a
# specification.
sw_formal_refs() {
	for _fx in $(sw_json_files "$SW_FLOWS_DIR") $(sw_json_files "$SW_STATES_DIR"); do
		_fxn=$(jq -r '.formal? | strings' "$SOFTWARY_ROOT/$_fx" 2>/dev/null) || continue
		[ -z "$_fxn" ] || printf '%s %s\n' "$_fxn" "$_fx"
	done
}

# sw_formal_names: the specifications of the project, one per line: those
# flows and state machines name and those with a model under architecture/formal/.
sw_formal_names() {
	{
		sw_formal_refs | awk '{ print $1 }'
		for _fn in "$SOFTWARY_ROOT/$SW_FORMAL_DIR"/*.tla; do
			[ -f "$_fn" ] || continue
			_fn=${_fn##*/}
			printf '%s\n' "${_fn%.tla}"
		done
	} | grep -E '^[a-z][a-z0-9_]*$' | LC_ALL=C sort -u
}

# sw_formal_specs_exist: true if architecture/formal/ holds a TLA+ model.
sw_formal_specs_exist() {
	for _fe in "$SOFTWARY_ROOT/$SW_FORMAL_DIR"/*.tla; do
		[ -f "$_fe" ] && return 0
	done
	return 1
}

# sw_formal_record_check [AD]: prints one "<file>: <problem>" line per problem
# of the specifications' files and records (of AD, or of every one). Returns 0
# clean, 1 problems.
sw_formal_record_check() {
	_fc_out=
	_fc_refs=$(sw_formal_refs)
	_fc_files=
	for _fc_x in "$SOFTWARY_ROOT/$SW_FORMAL_DIR"/*; do
		[ -f "$_fc_x" ] && _fc_files="$_fc_files ${_fc_x##*/}"
	done
	for _fc_n in ${1:-$(sw_formal_names)}; do
		_fc_by=$(printf '%s\n' "$_fc_refs" | awk -v n="$_fc_n" '$1 == n { print $2; exit }')
		_fc_note=
		[ -z "$_fc_by" ] || _fc_note=" (named by $_fc_by)"
		for _fc_e in tla cfg md; do
			[ -f "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$_fc_n.$_fc_e" ] ||
				_fc_out="${_fc_out}$SW_FORMAL_DIR/$_fc_n.$_fc_e: not found$_fc_note
"
		done
		[ -f "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$_fc_n.md" ] || continue
		_fc_p=$(sw_formal_record_problems "$_fc_n" "$_fc_files")
		[ -z "$_fc_p" ] || _fc_out="${_fc_out}$_fc_p
"
		# Every event of a state machine is an action of the record.
		_fc_acts=$(sw_formal_actions "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$_fc_n.md" | tr '\n' ' ')
		for _fc_s in $(printf '%s\n' "$_fc_refs" | awk -v n="$_fc_n" -v d="$SW_STATES_DIR/" '$1 == n && index($2, d) == 1 { print $2 }'); do
			for _fc_ev in $(jq -r '.transitions[]? | .event? | strings' "$SOFTWARY_ROOT/$_fc_s" 2>/dev/null | LC_ALL=C sort -u); do
				sw_in_list "$_fc_ev" "$_fc_acts" ||
					_fc_out="${_fc_out}$_fc_s: event '$_fc_ev' has no action in $SW_FORMAL_DIR/$_fc_n.md
"
			done
		done
	done
	[ -z "$_fc_out" ] || printf '%s' "$_fc_out"
	[ -z "$_fc_out" ]
}
