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

# sw_formal_findings_raw FILE: the lines of the findings table of a record
# exactly as written (what the blueprint approval binds besides the invariants).
sw_formal_findings_raw() {
	tr -d '\r' <"$1" | awk '
		/^##[ \t]/ { t = $0; sub(/^##[ \t]+/, "", t); sub(/[ \t]+$/, "", t); insec = (t == "Findings"); next }
		insec && /^[ \t]*\|/ { print }'
}

# sw_formal_findings AD: the findings of a record, one per line:
# "<invariant>|<until>|<reason>".
sw_formal_findings() {
	sw_formal_table "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$1.md" Findings | awk -F'|' '$1 == "R" { print $2 "|" $3 "|" $4 }'
}

# sw_formal_findings_problems AD: the problems of the findings table of a
# record (it is optional), one "<file>: <problem>" line each: the columns, an
# invariant that is not in the invariants table or is there twice, a date that
# is not a calendar date, no reason.
sw_formal_findings_problems() {
	_ff_md=$SOFTWARY_ROOT/$SW_FORMAL_DIR/$1.md
	_ff_rel=$SW_FORMAL_DIR/$1.md
	_ff_h=$(sw_formal_table "$_ff_md" Findings | awk -F'|' '$1 == "H" { print $2 "|" $3 "|" $4 }')
	[ -n "$_ff_h" ] || return 0
	if [ "$_ff_h" != "Invariant|Until|Reason" ]; then
		printf "%s: '## Findings' table must have the columns Invariant, Until, Reason\n" "$_ff_rel"
		return 0
	fi
	_ff_invs=$(sw_formal_table "$_ff_md" Invariants | awk -F'|' '$1 == "R" { print $2 }' | tr '\n' ' ')
	_ff_seen=
	while IFS='|' read -r _ff_i _ff_u _ff_r; do
		[ -n "$_ff_i$_ff_u$_ff_r" ] || continue
		if ! sw_in_list "$_ff_i" "$_ff_invs"; then
			printf "%s: finding '%s' is not in the invariants table\n" "$_ff_rel" "$_ff_i"
		elif sw_in_list "$_ff_i" "$_ff_seen"; then
			printf "%s: duplicate finding '%s'\n" "$_ff_rel" "$_ff_i"
		fi
		_ff_seen="$_ff_seen $_ff_i"
		sw_valid_date "$_ff_u" || printf "%s: finding '%s' has an invalid date '%s' (use YYYY-MM-DD)\n" "$_ff_rel" "$_ff_i" "$_ff_u"
		[ -n "$_ff_r" ] || printf "%s: finding '%s' has no reason\n" "$_ff_rel" "$_ff_i"
	done <<FINDINGS
$(sw_formal_findings "$1")
FINDINGS
	return 0
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
		_fc_p=$(sw_formal_findings_problems "$_fc_n")
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


# --- TLC ----------------------------------------------------------------------

# The jar is pinned: version and SHA-256 are the package's. SW_TLA2TOOLS names
# another place for it; SW_TLA2TOOLS_URL replaces the address (for tests).
SW_TLA_VERSION=1.8.0
SW_TLA_SHA256=7e53aa636dac8a3cb0533f343115c0548e03fc0ce5edc7739becf58d3d0fb84f
SW_TLA_URL=https://github.com/tlaplus/tlaplus/releases/download/v$SW_TLA_VERSION/tla2tools.jar

sw_formal_jar() {
	printf '%s\n' "${SW_TLA2TOOLS:-${HOME:-}/.cache/softwary/tla2tools-$SW_TLA_VERSION.jar}"
}

# sw_formal_sha256 FILE: the SHA-256 of FILE (nothing when no tool can tell).
sw_formal_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

# sw_formal_ready: returns 0 when TLC can run; otherwise prints the one line
# that says what to do and returns 2.
sw_formal_ready() {
	if ! command -v java >/dev/null 2>&1; then
		printf 'formal: java not found; TLC needs a Java runtime (11 or later): install one, then run ./softwary formal check again\n'
		return 2
	fi
	_fy_jar=$(sw_formal_jar)
	if [ ! -f "$_fy_jar" ]; then
		printf 'formal: %s not found; run ./softwary formal install\n' "$_fy_jar"
		return 2
	fi
	if [ "$(sw_formal_sha256 "$_fy_jar")" != "$SW_TLA_SHA256" ]; then
		printf 'formal: %s is not tla2tools %s (SHA-256 %s); run ./softwary formal install\n' "$_fy_jar" "$SW_TLA_VERSION" "$SW_TLA_SHA256"
		return 2
	fi
}

# sw_formal_install: downloads the pinned jar unless it is there and right.
# Returns 0, or 2 (download failed, wrong SHA-256, no tool to download or check).
sw_formal_install() {
	_fi_jar=$(sw_formal_jar)
	if [ -f "$_fi_jar" ] && [ "$(sw_formal_sha256 "$_fi_jar")" = "$SW_TLA_SHA256" ]; then
		printf 'formal install: %s (already installed)\n' "$_fi_jar"
		return 0
	fi
	if [ -z "$(sw_formal_sha256 /dev/null)" ]; then
		printf 'formal install: neither sha256sum nor shasum found; cannot check the download\n'
		return 2
	fi
	_fi_url=${SW_TLA2TOOLS_URL:-$SW_TLA_URL}
	mkdir -p "$(dirname "$_fi_jar")" || { printf 'formal install: cannot create %s\n' "$(dirname "$_fi_jar")"; return 2; }
	rm -f "$_fi_jar.part"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$_fi_jar.part" "$_fi_url" || { rm -f "$_fi_jar.part"; printf 'formal install: could not download %s\n' "$_fi_url"; return 2; }
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$_fi_jar.part" "$_fi_url" || { rm -f "$_fi_jar.part"; printf 'formal install: could not download %s\n' "$_fi_url"; return 2; }
	else
		printf 'formal install: neither curl nor wget found; download %s to %s yourself\n' "$_fi_url" "$_fi_jar"
		return 2
	fi
	if [ "$(sw_formal_sha256 "$_fi_jar.part")" != "$SW_TLA_SHA256" ]; then
		rm -f "$_fi_jar.part" "$_fi_jar"
		printf 'formal install: the download is not tla2tools %s (its SHA-256 is not %s); it was deleted\n' "$SW_TLA_VERSION" "$SW_TLA_SHA256"
		return 2
	fi
	mv "$_fi_jar.part" "$_fi_jar" || return 2
	printf 'formal install: installed %s\n' "$_fi_jar"
}

# sw_formal_tlc DIR CFG TLA WORKERS LOG [CFGFILE]: runs TLC on a copy of the
# model and the configuration (TLC writes trace files next to the model when it
# finds an error) and keeps its whole output in LOG. CFGFILE, when given, is
# the configuration that is copied in place of DIR/CFG (a generated one).
# Returns TLC's exit code.
sw_formal_tlc() {
	_ft_work=$(mktemp -d "${TMPDIR:-/tmp}/softwary-tlc.XXXXXX") || return 2
	cp "$1"/*.tla "$_ft_work/" || { rm -rf "$_ft_work"; return 2; }
	cp "${6:-$1/$2}" "$_ft_work/$2" || { rm -rf "$_ft_work"; return 2; }
	_ft_rc=0
	(cd "$_ft_work" && java -XX:+UseParallelGC -cp "$(sw_formal_jar)" tlc2.TLC -workers "$4" -config "$2" -metadir "$_ft_work/states" "$3") \
		>"$5" 2>&1 </dev/null || _ft_rc=$?
	rm -rf "$_ft_work"
	return "$_ft_rc"
}

# sw_formal_result LOG: what TLC found, in one line: "pass <n>" (n distinct
# states), "violated <name>" (a name of ? when TLC names none), "deadlock" or
# "error".
sw_formal_result() {
	awk '
		/^Model checking completed\. No error has been found\./ { ok = 1 }
		/^[0-9,.]+ states generated, [0-9,.]+ distinct states found/ { n = $4; gsub(/[^0-9]/, "", n) }
		/^Error: Invariant .* is violated\./ { v = $0; sub(/^Error: Invariant /, "", v); sub(/ is violated\..*$/, "", v); name = v }
		/^Error: Action property .* is violated\./ { v = $0; sub(/^Error: Action property /, "", v); sub(/ is violated\..*$/, "", v); name = v }
		/^Error: Temporal property .* was violated/ { v = $0; sub(/^Error: Temporal property /, "", v); sub(/ was violated.*$/, "", v); name = v }
		/^Error: Temporal properties were violated/ { name = "?" }
		/^Error: Deadlock reached/ { dead = 1 }
		END {
			if (name != "") print "violated " name
			else if (dead) print "deadlock"
			else if (ok) print "pass " n
			else print "error"
		}' "$1"
}

# sw_formal_trace LOG RECORD: the counter-example of a TLC log, one line per
# step: "  <n>. <the action's sentence> (<action>): <changed variables>". The
# sentences come from the record's Actions table; an action the record does
# not describe is written by its name.
sw_formal_trace() {
	_fa=$(sw_formal_table "$2" Actions | awk -F'|' '$1 == "R" { print $2 "|" $3 }')
	awk -v acts="$_fa" '
		BEGIN {
			n = split(acts, l, "\n")
			for (i = 1; i <= n; i++) { k = index(l[i], "|"); if (k > 0) sent[substr(l[i], 1, k - 1)] = substr(l[i], k + 1) }
		}
		function flush(   i, j, t, out, names, nn, changed, v, s) {
			if (!instate) return
			nn = 0
			for (v in cur) names[++nn] = v
			for (i = 2; i <= nn; i++) { t = names[i]; for (j = i - 1; j >= 1 && names[j] > t; j--) names[j + 1] = names[j]; names[j + 1] = t }
			out = ""; changed = 0
			for (i = 1; i <= nn; i++) {
				v = names[i]
				if (step == 1 || !(v in prev) || prev[v] != cur[v]) { out = out (changed++ ? ", " : "") v " = " cur[v] }
			}
			if (out == "") out = "no variable changed"
			s = (act in sent) ? sent[act] : (act == "Init" ? "initial state" : act)
			sub(/\.$/, "", s)
			printf "  %d. %s (%s): %s\n", step, s, act, out
			for (v in prev) delete prev[v]
			for (v in cur) { prev[v] = cur[v]; delete cur[v] }
			instate = 0
		}
		/^State [0-9]+: / {
			flush()
			step = $2; sub(/:$/, "", step); step += 0
			a = $0; sub(/^State [0-9]+: /, "", a)
			if (a ~ /^<Initial predicate>/) act = "Init"
			else if (a ~ /^</) { sub(/^</, "", a); sub(/[ >(].*$/, "", a); act = a }
			else act = "stuttering"
			instate = 1; last = ""
			next
		}
		/^Back to state [0-9]+/ {
			flush()
			a = $0; k = $4; sub(/:$/, "", k)
			sub(/^Back to state [0-9]+: </, "", a); sub(/[ >(].*$/, "", a)
			printf "  then it goes back to step %s (%s)\n", k, a
			next
		}
		instate && /^[ \t]*$/ { flush(); next }
		instate && /^(\/\\ )?[A-Za-z_][A-Za-z0-9_]* = / {
			line = $0; sub(/^\/\\ /, "", line)
			k = index(line, " = "); last = substr(line, 1, k - 1)
			cur[last] = substr(line, k + 3)
			next
		}
		instate && last != "" { t = $0; gsub(/^[ \t]+/, "", t); cur[last] = cur[last] " " t; next }
		END { flush() }' "$1"
}

# sw_formal_cfg CFG MODE NAMES: prints the configuration CFG with its INVARIANT
# and PROPERTY names changed: MODE drop leaves NAMES (blank-separated) out, MODE
# only keeps nothing but NAMES. The names are printed under one INVARIANTS and
# one PROPERTIES keyword at the end (the order of the sections does not matter
# to TLC); every other line stays as it is.
sw_formal_cfg() {
	tr -d '\r' <"$1" | awk -v mode="$2" -v names="$3" '
		BEGIN {
			n = split(names, nm, " "); for (i = 1; i <= n; i++) pick[nm[i]] = 1
			n = split("SPECIFICATION INIT NEXT CONSTANT CONSTANTS CONSTRAINT CONSTRAINTS ACTION_CONSTRAINT ACTION_CONSTRAINTS INVARIANT INVARIANTS PROPERTY PROPERTIES SYMMETRY VIEW ALIAS POSTCONDITION CHECK_DEADLOCK TERMINAL", kw, " ")
			for (i = 1; i <= n; i++) iskw[kw[i]] = 1
			kind = ""
		}
		function keep(t) {
			if (t == "") return
			if (mode == "drop" ? (t in pick) : !(t in pick)) return
			if (kind == "I") { if (!(t in seeni)) { seeni[t] = 1; ni++; inv[ni] = t } }
			else if (!(t in seenp)) { seenp[t] = 1; np++; prop[np] = t }
		}
		{
			code = $0; k = index(code, "\\*"); if (k > 0) code = substr(code, 1, k - 1)
			m = split(code, tok, /[ \t]+/)
			start = 0
			for (i = 1; i <= m; i++) if (tok[i] != "") { start = i; break }
			if (start == 0) { print; next }
			if (tok[start] in iskw) {
				kind = (tok[start] == "INVARIANT" || tok[start] == "INVARIANTS") ? "I" : ((tok[start] == "PROPERTY" || tok[start] == "PROPERTIES") ? "P" : "")
				if (kind == "") { print; next }
				start++
			} else if (kind == "") { print; next }
			for (i = start; i <= m; i++) keep(tok[i])
		}
		END {
			if (ni > 0) { print "INVARIANTS"; for (i = 1; i <= ni; i++) print "  " inv[i] }
			if (np > 0) { print "PROPERTIES"; for (i = 1; i <= np; i++) print "  " prop[i] }
		}'
}

# --- formal check ---------------------------------------------------------------

# sw_formal_variant_rows AD: "<file> <invariant>" of the record's variants.
sw_formal_variant_rows() {
	sw_formal_table "$SOFTWARY_ROOT/$SW_FORMAL_DIR/$1.md" Variants | awk -F'|' '$1 == "R" { print $2 " " $3 }'
}

# sw_formal_check_one AD: checks one specification, printing its lines.
# Returns 0 when it passes, 1 when not.
sw_formal_check_one() {
	_fo_ad=$1
	_fo_dir=$SOFTWARY_ROOT/$SW_FORMAL_DIR
	_fo_logs=$SOFTWARY_ROOT/.softwary/state/logs
	mkdir -p "$_fo_logs" || return 1
	if ! _fo_p=$(sw_formal_record_check "$_fo_ad"); then
		printf '%s\n' "$_fo_p"
		printf 'formal %s: FAIL: the record has problems (./softwary blueprint check)\n' "$_fo_ad"
		return 1
	fi
	# The findings of the record are invariants the code is known to break: the
	# model runs without them, and each runs alone (below).
	_fo_find=$(sw_formal_findings "$_fo_ad")
	_fo_gen=
	_fo_tmp=
	if [ -n "$_fo_find" ]; then
		_fo_tmp=$(mktemp -d "${TMPDIR:-/tmp}/softwary-cfg.XXXXXX") || return 1
		_fo_names=$(printf '%s\n' "$_fo_find" | cut -d'|' -f1 | tr '\n' ' ')
		sw_formal_cfg "$_fo_dir/$_fo_ad.cfg" drop "$_fo_names" >"$_fo_tmp/good.cfg"
		_fo_gen=$_fo_tmp/good.cfg
	fi
	_fo_log=$_fo_logs/formal-$_fo_ad.log
	sw_formal_tlc "$_fo_dir" "$_fo_ad.cfg" "$_fo_ad.tla" auto "$_fo_log" "$_fo_gen" || :
	_fo_res=$(sw_formal_result "$_fo_log")
	case $_fo_res in
	"pass "*) _fo_states=${_fo_res#pass } ;;
	violated* | deadlock)
		_fo_name=${_fo_res#violated }
		[ "$_fo_res" != deadlock ] || _fo_name=deadlock
		printf 'formal %s: FAIL: %s violated\n' "$_fo_ad" "$_fo_name"
		# One worker searches breadth first and reports the shortest path.
		sw_formal_tlc "$_fo_dir" "$_fo_ad.cfg" "$_fo_ad.tla" 1 "$_fo_log" "$_fo_gen" || :
		sw_formal_trace "$_fo_log" "$_fo_dir/$_fo_ad.md"
		printf '    log: .softwary/state/logs/formal-%s.log\n' "$_fo_ad"
		[ -z "$_fo_tmp" ] || rm -rf "$_fo_tmp"
		return 1
		;;
	*)
		printf 'formal %s: FAIL: TLC could not check the model\n' "$_fo_ad"
		tail -n 8 "$_fo_log" | sed 's/^/    /'
		printf '    log: .softwary/state/logs/formal-%s.log\n' "$_fo_ad"
		[ -z "$_fo_tmp" ] || rm -rf "$_fo_tmp"
		return 1
		;;
	esac
	_fo_bad=0
	_fo_today=$(date +%Y%m%d)
	while IFS='|' read -r _fo_fi _fo_fu _fo_fr; do
		[ -n "$_fo_fi" ] || continue
		sw_formal_cfg "$_fo_dir/$_fo_ad.cfg" only "$_fo_fi" >"$_fo_tmp/one.cfg"
		_fo_flog=$_fo_logs/formal-$_fo_ad-finding-$_fo_fi.log
		sw_formal_tlc "$_fo_dir" "$_fo_ad.cfg" "$_fo_ad.tla" auto "$_fo_flog" "$_fo_tmp/one.cfg" || :
		_fo_fres=$(sw_formal_result "$_fo_flog")
		case $_fo_fres in
		"violated $_fo_fi" | "violated ?")
			if [ "$(printf '%s' "$_fo_fu" | tr -d -)" -lt "$_fo_today" ]; then
				printf 'formal %s: FAIL: %s violated (finding expired %s)\n' "$_fo_ad" "$_fo_fi" "$_fo_fu"
				_fo_bad=1
			else
				printf 'formal %s: FINDING: %s violated (until %s: %s)\n' "$_fo_ad" "$_fo_fi" "$_fo_fu" "$_fo_fr"
			fi
			sw_formal_tlc "$_fo_dir" "$_fo_ad.cfg" "$_fo_ad.tla" 1 "$_fo_flog" "$_fo_tmp/one.cfg" || :
			sw_formal_trace "$_fo_flog" "$_fo_dir/$_fo_ad.md"
			;;
		"pass "*) printf 'formal %s: finding %s no longer reproduces (remove it)\n' "$_fo_ad" "$_fo_fi" ;;
		*)
			printf 'formal %s: FAIL: finding %s could not be checked (see .softwary/state/logs/formal-%s-finding-%s.log)\n' "$_fo_ad" "$_fo_fi" "$_fo_ad" "$_fo_fi"
			_fo_bad=1
			;;
		esac
	done <<FINDINGS
$_fo_find
FINDINGS
	[ -z "$_fo_tmp" ] || rm -rf "$_fo_tmp"
	_fo_vars=$(sw_formal_variant_rows "$_fo_ad")
	while read -r _fo_vf _fo_vb; do
		[ -n "$_fo_vf" ] || continue
		[ -f "$_fo_dir/$_fo_vf" ] || { _fo_bad=1; continue; }
		_fo_vlog=$_fo_logs/formal-${_fo_vf%.cfg}.log
		sw_formal_tlc "$_fo_dir" "$_fo_vf" "$_fo_ad.tla" auto "$_fo_vlog" || :
		_fo_vr=$(sw_formal_result "$_fo_vlog")
		case $_fo_vr in
		"violated $_fo_vb") printf 'formal %s: variant %s fails on %s\n' "$_fo_ad" "$_fo_vf" "$_fo_vb" ;;
		"violated ?")
			if grep -Ew -e "$_fo_vb" "$_fo_dir/$_fo_vf" >/dev/null 2>&1; then
				printf 'formal %s: variant %s fails on %s\n' "$_fo_ad" "$_fo_vf" "$_fo_vb"
			else
				printf 'formal %s: variant %s failed on an unnamed property (expected %s)\n' "$_fo_ad" "$_fo_vf" "$_fo_vb"
				_fo_bad=1
			fi
			;;
		violated*)
			printf 'formal %s: variant %s failed on %s (expected %s)\n' "$_fo_ad" "$_fo_vf" "${_fo_vr#violated }" "$_fo_vb"
			_fo_bad=1
			;;
		deadlock)
			printf 'formal %s: variant %s failed on deadlock (expected %s)\n' "$_fo_ad" "$_fo_vf" "$_fo_vb"
			_fo_bad=1
			;;
		"pass "*)
			printf 'formal %s: variant %s did not fail (expected %s)\n' "$_fo_ad" "$_fo_vf" "$_fo_vb"
			_fo_bad=1
			;;
		*)
			printf 'formal %s: variant %s could not be checked (see .softwary/state/logs/formal-%s.log)\n' "$_fo_ad" "$_fo_vf" "${_fo_vf%.cfg}"
			_fo_bad=1
			;;
		esac
	done <<VARIANTS
$_fo_vars
VARIANTS
	[ "$_fo_bad" -eq 0 ] || return 1
	printf 'formal %s: PASS (%s states)\n' "$_fo_ad" "$_fo_states"
}

# sw_formal_check [AD]: checks every specification (or AD). Returns 0 all pass,
# 1 one fails, 2 TLC cannot run or AD is unknown.
sw_formal_check() {
	_fk_names=$(sw_formal_names)
	if [ -n "${1-}" ]; then
		if ! printf '%s\n' "$_fk_names" | grep -Fqx -e "$1"; then
			printf "formal: no specification '%s' (see architecture/formal/)\n" "$1"
			return 2
		fi
		_fk_names=$1
	fi
	if [ -z "$_fk_names" ]; then
		printf 'formal: no specs\n'
		return 0
	fi
	sw_formal_ready || return 2
	_fk_rc=0
	for _fk_n in $_fk_names; do
		sw_formal_check_one "$_fk_n" || _fk_rc=1
	done
	return "$_fk_rc"
}

# sw_formal check [<spec>] | install
sw_formal() {
	case ${1:-} in
	check)
		[ $# -le 2 ] || { printf 'usage: ./softwary formal check [<spec>] | formal install\n' >&2; return 2; }
		sw_formal_check "${2-}"
		;;
	install)
		[ $# -eq 1 ] || { printf 'usage: ./softwary formal check [<spec>] | formal install\n' >&2; return 2; }
		sw_formal_install
		;;
	*)
		printf 'usage: ./softwary formal check [<spec>] | formal install\n' >&2
		return 2
		;;
	esac
}
