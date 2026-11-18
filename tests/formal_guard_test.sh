#!/bin/sh
# Tests for what V8 changes about the specifications of a project in the
# loop's gates: `guard` protects only what binds a human (the invariants, the
# findings, the set of files; architecture/proofs/), `risk` takes
# architecture/formal/ as R2 at least and `plan check` asks a slice that
# touches covered code to touch the record too.
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

JOB=001-S1
S1=specs/001-login/slices/S1.md
F=architecture/formal
MD=$F/order.md
FOUND='| `ShippedWasPaid` | 2999-12-31 | The old order code ships a created order. |'

# md_sub FROM TO: replaces the first FROM of each line of the record by TO.
md_sub() {
	awk -v f="$1" -v t="$2" '{ if ((i = index($0, f)) > 0) $0 = substr($0, 1, i - 1) t substr($0, i + length(f)); print }' \
		"$REPO/$MD" >"$T/md.tmp"
	mv "$T/md.tmp" "$REPO/$MD"
}

# lv_set VALUE: the first line of `## Last verified` becomes VALUE.
lv_set() {
	awk -v v="$1" '
		/^## / { on = ($0 == "## Last verified"); print; next }
		on && !done && NF { print v; done = 1; next }
		{ print }' "$REPO/$MD" >"$T/md.tmp"
	mv "$T/md.tmp" "$REPO/$MD"
}

# findings_row: the record gets a `## Findings` table with one row.
findings_row() {
	printf '\n## Findings\n\n| Invariant | Until | Reason |\n| --- | --- | --- |\n%s\n' "$FOUND" >>"$REPO/$MD"
}

# put FILE TEXT: writes FILE (and its directory) in the repo.
put() {
	mkdir -p "$(dirname "$REPO/$1")"
	printf '%s\n' "$2" >"$REPO/$1"
}

# formal_guard_repo [TOUCHES]: the order model and the sample plan on main,
# with an origin, and the job branch softwary/001-S1 checked out. S1 touches
# TOUCHES (default: the source, the tests and the formal and proofs directories).
formal_guard_repo() {
	setup_repo
	conf_all true
	conf_set test_paths tests
	add_product
	add_blueprint
	add_formal
	findings_row
	add_plan
	fm_set "$REPO/$S1" touches "${1:-src/api, tests, architecture/formal, architecture/proofs}"
	mkdir -p "$REPO/tests" "$REPO/src/api"
	printf '# covers AC-001-01\n' >"$REPO/tests/test_login.py"
	printf 'code\n' >"$REPO/src/api/login.py"
	add_origin
	git -C "$REPO" checkout -q -b "softwary/$JOB"
}

# AC-V8-04: the model, its configurations and the sections of the record that
# no human is bound to are the loop's to change: no protected path.
test_ac_v8_04_upkeep_is_not_protected() {
	formal_guard_repo
	printf '\\* a comment\n' >>"$REPO/$F/order.tla"
	printf '\\* a comment\n' >>"$REPO/$F/order.cfg"
	printf '\\* a comment\n' >>"$REPO/$F/order-shipunpaid.cfg"
	md_sub 'A paid order is shipped.' 'A paid order leaves the warehouse.'
	md_sub '| planned | - |' '| src/api/login.py | login |'
	md_sub 'One order at a time;' 'Two orders at a time;'
	lv_set "0123456789012345678901234567890123456789 updated"
	commit_all "the model follows the code"
	sw guard $JOB --base main
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^guard: no problems$"
	assert_no_match "$OUT" "protected"
}

# AC-V8-04: one letter of an invariant's sentence, or of a finding, is a
# protected change, whatever else changed with it.
test_ac_v8_04_invariants_and_findings_are_protected() {
	formal_guard_repo
	md_sub 'has been paid for.' 'has been paid for!'
	commit_all "an invariant is reworded"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code for an invariant"
	assert_match "$OUT" "^guard: protected: $MD$"
	assert_match "$OUT" "^guard: 1 problem\\(s\\)$"
	git -C "$REPO" checkout -q main
	git -C "$REPO" checkout -q -B "softwary/$JOB"
	md_sub '2999-12-31' '2999-12-30'
	commit_all "a finding's date moves"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code for a finding"
	assert_match "$OUT" "^guard: protected: $MD$"
}

# AC-V8-04: the base is the common ancestor: a table that the job changes and
# changes back is the base's, and a job that adds a section the tables do not
# have changes nothing that binds.
test_ac_v8_04_compared_with_the_base() {
	formal_guard_repo
	md_sub 'has been paid for.' 'has been paid for!'
	md_sub 'One order at a time;' 'Two orders at a time;'
	commit_all "an invariant is reworded and a bound changed"
	md_sub 'has been paid for!' 'has been paid for.'
	commit_all "the invariant is put back"
	sw guard $JOB --base main
	assert_eq "$RC" 0 "exit code after the table is put back"
	assert_no_match "$OUT" "protected"
	printf '\n## Notes\n\n| Invariant | Until | Reason |\n| --- | --- | --- |\n| `X` | 2999-12-31 | not a finding |\n' >>"$REPO/$MD"
	commit_all "a table under another heading"
	sw guard $JOB --base main
	assert_eq "$RC" 0 "exit code with an unrelated table"
}

# AC-V8-04: a file that is added, deleted or renamed under architecture/formal/
# is protected: the set of models is the human's.
test_ac_v8_04_added_deleted_renamed_files() {
	formal_guard_repo
	cp "$REPO/$F/order-shipunpaid.cfg" "$REPO/$F/order-extra.cfg"
	commit_all "a new configuration"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code for a new file"
	assert_match "$OUT" "^guard: protected: $F/order-extra\\.cfg$"
	git -C "$REPO" checkout -q main
	git -C "$REPO" checkout -q -B "softwary/$JOB"
	git -C "$REPO" rm -q "$MD"
	commit_all "the record is deleted"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code for a deleted record"
	assert_match "$OUT" "^guard: protected: $MD$"
	git -C "$REPO" checkout -q main
	git -C "$REPO" checkout -q -B "softwary/$JOB"
	git -C "$REPO" mv "$F/order-shipunpaid.cfg" "$F/order-unpaid.cfg"
	commit_all "a configuration is renamed"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code for a renamed file"
	assert_match "$OUT" "^guard: protected: $F/order-shipunpaid\\.cfg$"
	assert_match "$OUT" "^guard: protected: $F/order-unpaid\\.cfg$"
}

# AC-V8-04: architecture/proofs/ is protected whole.
test_ac_v8_04_proofs_are_protected() {
	formal_guard_repo
	put architecture/proofs/sum.lean "theorem t : True := trivial"
	commit_all "a proof"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^guard: protected: architecture/proofs/sum\\.lean$"
}

# AC-V8-04: the rule of the touches goes on: a change to the model outside the
# slice's touches is a problem of its own.
test_ac_v8_04_touches_still_apply() {
	formal_guard_repo "src/api, tests"
	printf '\\* a comment\n' >>"$REPO/$F/order.tla"
	commit_all "the model"
	sw guard $JOB --base main
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^guard: outside touches: $F/order\\.tla$"
	assert_no_match "$OUT" "protected"
}

# risk_repo: a repo with the order model and the sample plan on main and a
# branch that changes the model.
risk_repo() {
	setup_repo
	conf_all true
	add_product
	add_blueprint
	add_formal
	add_plan
	commit_all base
	git -C "$REPO" checkout -qb feature
	printf '\\* a comment\n' >>"$REPO/$F/order.tla"
	commit_all "the model"
}

# AC-V8-05: a changed path under architecture/formal/ is R2 at least, whatever
# risk.conf says (default R1, a rule for R1); a higher tier of risk.conf stays.
test_ac_v8_05_formal_is_r2_at_least() {
	risk_repo
	sw risk 001 --base main
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^paths +R2 \\($F/order\\.tla: "
	risk_set 'architecture/*' R1
	sw risk 001 --base main
	assert_match "$OUT" "^paths +R2 \\($F/order\\.tla: "
	risk_set "$F/*" R3
	sw risk 001 --base main
	assert_match "$OUT" "^paths +R3 \\($F/order\\.tla: $F/\\*\\)$"
	assert_eq "$(tail -n 1 "$OUT")" "risk            R3" "last line"
}

# AC-V8-05: a path outside architecture/formal/ is not raised.
test_ac_v8_05_other_paths_keep_their_tier() {
	risk_repo
	git -C "$REPO" checkout -q main
	git -C "$REPO" checkout -qB feature
	put docs/notes.txt "x"
	commit_all "notes"
	sw risk 001 --base main
	assert_match "$OUT" "^paths +R1 \\(docs/notes\\.txt: default\\)$"
	put architecture/formals.txt "x"
	commit_all "a path that only looks like it"
	sw risk 001 --base main
	assert_no_match "$OUT" "^paths +R2"
}

# plan_repo: the sample plan on a blueprint that carries the order model,
# approved; the record covers app/order.sh (the model was written before the
# code, so the approval holds), which is there.
plan_repo() {
	setup_repo
	add_product
	add_blueprint
	add_formal
	sw approve product
	approve_blueprint
	[ "$RC" -eq 0 ] || fail "approve blueprint: $(cat "$OUT")"
	add_plan
	mkdir -p "$REPO/app"
	cp "$EXISTINGFIX/app/order.sh" "$REPO/app/order.sh"
	md_sub '| planned | - |' '| app/order.sh | order_create, order_ship |'
	fm_set "$REPO/$S1" touches "app/order.sh"
}

# AC-V8-06: a slice that touches covered code and not the record of the
# model that covers it is a problem; with the record in touches it is clean.
test_ac_v8_06_record_in_touches() {
	need_tlc || return 0
	plan_repo
	sw plan check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^slice 001-S1 touches app/order\\.sh covered by formal order; add $MD to touches$"
	assert_match "$OUT" "^plan: 1 problem\\(s\\)$"
	fm_set "$REPO/$S1" touches "app/order.sh, $MD"
	sw plan check
	assert_eq "$RC" 0 "exit code with the record in touches"
	assert_match "$OUT" "^plan: clean "
}

# AC-V8-06: touches are judged as everywhere (V3): a directory covers what is
# in it and a pattern is a pattern, in either direction.
test_ac_v8_06_directories_and_patterns() {
	need_tlc || return 0
	plan_repo
	fm_set "$REPO/$S1" touches "app/"
	sw plan check
	assert_match "$OUT" "^slice 001-S1 touches app/ covered by formal order; add $MD to touches$"
	fm_set "$REPO/$S1" touches "app/*.sh"
	sw plan check
	assert_match "$OUT" "^slice 001-S1 touches app/\\*\\.sh covered by formal order; "
	fm_set "$REPO/$S1" touches "app/*.sh, architecture/formal/"
	sw plan check
	assert_eq "$RC" 0 "exit code with the formal directory"
	fm_set "$REPO/$S1" touches "app/*.sh, architecture/*"
	sw plan check
	assert_eq "$RC" 0 "exit code with a pattern over the record"
	md_sub '| app/order.sh | order_create, order_ship |' '| app | order_create, order_ship |'
	fm_set "$REPO/$S1" touches "app/order.sh"
	sw plan check
	assert_match "$OUT" "^slice 001-S1 touches app/order\\.sh covered by formal order; "
}

# AC-V8-06: coverage that is only planned asks for nothing; neither does a
# slice that is done, nor one that touches something else.
test_ac_v8_06_planned_done_and_unrelated() {
	need_tlc || return 0
	plan_repo
	md_sub '| app/order.sh | order_create, order_ship |' '| planned | - |'
	sw plan check
	assert_eq "$RC" 0 "exit code with planned coverage"
	md_sub '| planned | - |' '| app/order.sh | order_create, order_ship |'
	fm_set "$REPO/$S1" status "done"
	mkdir -p "$REPO/specs/001-login/reviews" "$REPO/tests"
	printf -- '---\nslice: S1\ndecision: approve\n---\n\n# Review of S1\n' >"$REPO/specs/001-login/reviews/S1.md"
	printf '# covers AC-001-01\n' >"$REPO/tests/test_login.sh"
	conf_set test_paths tests
	sw plan check
	assert_eq "$RC" 0 "exit code with a done slice"
	fm_set "$REPO/$S1" status planned
	fm_set "$REPO/$S1" touches "src/api"
	sw plan check
	assert_eq "$RC" 0 "exit code with an unrelated slice"
}

run_tests "$0"
