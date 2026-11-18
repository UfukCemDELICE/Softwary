#!/bin/sh
# Tests for the upkeep of a specification (V8): the coverage table points at
# real code, a model that is older than the code it covers is stale, and
# `formal verified` records the verdict that brings it up to date. The tests
# that run TLC need Java and the pinned jar (SW_SKIP_FORMAL=<reason> skips
# them, visibly).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

F=architecture/formal
MD=$F/order.md
FNS='order_create, order_pay, order_ship, order_cancel'
EVENTS_REL=.softwary/state/events.log

# covered: a repo whose order model covers app/order.sh (the shop's code), as
# the project's own commit. The record has never been verified.
covered() {
	setup_repo
	add_product
	add_blueprint
	add_formal
	mkdir -p "$REPO/app"
	cp "$EXISTINGFIX/app/order.sh" "$REPO/app/order.sh"
	md_sub '| planned | - |' "| app/order.sh | $FNS |"
	commit_all "the shop's order code and its model"
}

# md_sub FROM TO: replaces the first FROM of each line of the record by TO
# (TO may contain FROM).
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

# lv_get: the first line of `## Last verified`.
lv_get() {
	awk '/^## / { on = ($0 == "## Last verified"); next } on && NF { print; exit }' "$REPO/$MD"
}

# verified_now: the record says the model was verified at the commit that is
# HEAD now (a bare commit, as V5 wrote it), and that is committed.
verified_now() {
	lv_set "$(git -C "$REPO" rev-parse HEAD)"
	commit_all "verified"
}

# AC-V8-01: a covered path that is not there is a problem of its own, in
# `blueprint check` (the record check) and in `formal check`.
test_ac_v8_01_missing_path() {
	covered
	md_sub 'app/order.sh' 'app/ghost.sh'
	sw blueprint check
	assert_eq "$RC" 1 "blueprint check exit code"
	assert_match "$OUT" "^formal order: coverage path app/ghost\\.sh does not exist$"
	assert_no_match "$OUT" "coverage function"
	assert_match "$OUT" "^blueprint: 1 problem\\(s\\)$"
	need_tlc || return 0
	sw formal check order
	assert_eq "$RC" 1 "formal check exit code"
	assert_match "$OUT" "^formal order: coverage path app/ghost\\.sh does not exist$"
	# the model is checked all the same: a mistake of the model shows too
	assert_match "$OUT" "^formal order: variant order-shipunpaid\\.cfg fails on ShippedWasPaid$"
	assert_match "$OUT" "^formal order: FAIL: the model passes \\([0-9]+ states\\) but is not held to the code \\(see above\\)$"
}

# AC-V8-01: every function the table names must be in the file, as a word:
# order_pay is not order_payment. One line for each missing function.
test_ac_v8_01_missing_function() {
	covered
	printf 'order_create() { :; }\norder_payment() { :; }\norder_ship() { :; }\norder_cancelled() { :; }\n' >"$REPO/app/order.sh"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: coverage function order_pay not found in app/order\\.sh$"
	assert_match "$OUT" "^formal order: coverage function order_cancel not found in app/order\\.sh$"
	assert_no_match "$OUT" "function order_create"
	assert_no_match "$OUT" "function order_ship"
	assert_match "$OUT" "^blueprint: 2 problem\\(s\\)$"
}

# AC-V8-01: a name that only occurs inside a longer word does not count, and
# a comment that names it does (a word of the file is a word).
test_ac_v8_01_word_boundary() {
	covered
	printf 'order_payment() { :; }\n' >"$REPO/app/other.sh"
	md_sub "| app/order.sh | $FNS |" '| app/other.sh | order_pay |'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: coverage function order_pay not found in app/other\\.sh$"
	need_tlc || return 0
	printf '# order_pay is in order_payment\n' >>"$REPO/app/other.sh"
	sw blueprint check
	assert_no_match "$OUT" "coverage"
}

# AC-V8-01: a `planned` row is not looked at; a directory is searched as a whole.
test_ac_v8_01_planned_and_directory() {
	need_tlc || return 0
	covered
	md_sub "| app/order.sh | $FNS |" '| planned | - |'
	sw blueprint check
	assert_eq "$RC" 0 "exit code with a planned row"
	md_sub '| planned | - |' "| app | $FNS |"
	sw blueprint check
	assert_no_match "$OUT" "coverage"
	md_sub "| app | $FNS |" "| app | $FNS, order_ghost |"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with a missing function in a directory"
	assert_match "$OUT" "^formal order: coverage function order_ghost not found in app$"
}

# AC-V8-02: a record that has never been verified and covers code fails; one
# whose coverage is only `planned` does not (the model came before the code).
test_ac_v8_02_never_verified() {
	need_tlc || return 0
	covered
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: never verified against app/order\\.sh$"
	assert_no_match "$OUT" "PASS"
	md_sub "| app/order.sh | $FNS |" '| planned | - |'
	commit_all "planned"
	sw formal check order
	assert_eq "$RC" 0 "exit code with planned coverage"
	assert_no_match "$OUT" "never verified"
	assert_no_match "$OUT" "stale"
}

# AC-V8-02: a commit the repository does not have cannot be told from a
# lie: it is reported by its first seven digits.
test_ac_v8_02_unknown_commit() {
	need_tlc || return 0
	covered
	lv_set 1234567890123456789012345678901234567890
	commit_all "verified at a commit nobody has"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: last verified commit 1234567 is unknown$"
}

# AC-V8-02: a bare commit (V5's record) is valid: compatible. Nothing changed
# since, so the check passes; the verdict words are accepted as well.
test_ac_v8_02_commit_and_verdict_forms() {
	need_tlc || return 0
	covered
	verified_now
	sw formal check order
	assert_eq "$RC" 0 "exit code with a bare commit"
	assert_match "$OUT" "^formal order: PASS "
	for v in compatible updated; do
		lv_set "$(git -C "$REPO" rev-parse HEAD) $v"
		commit_all "verified $v"
		sw blueprint check
		assert_eq "$RC" 0 "blueprint check exit code with $v"
	done
	lv_set "$(git -C "$REPO" rev-parse HEAD) bug"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with bug"
	assert_match "$OUT" "^$MD: '## Last verified' must be never, a 40-digit commit, a commit and compatible or updated, or those and two 40-digit digests$"
}

# AC-V8-02: the covered file changed in a later commit: stale, and the paths
# that changed are named.
test_ac_v8_02_stale_committed() {
	need_tlc || return 0
	covered
	verified_now
	printf '# a change\n' >>"$REPO/app/order.sh"
	commit_all "the code changes"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	sha7=$(git -C "$REPO" rev-parse --short=7 HEAD~2)
	assert_match "$OUT" "^formal order: stale since $sha7: app/order\\.sh changed; check the model and record a verdict \\(./softwary formal verified order compatible\\|updated\\)$"
	assert_no_match "$OUT" "PASS"
	conf_all true
	conf_set model_check "./softwary formal check"
	sw verify
	assert_eq "$RC" 1 "verify exit code"
	assert_match "$OUT" "^model_check +FAIL "
}

# AC-V8-02: a change that is not committed yet counts, and so does a new file
# in a covered directory that git does not track.
test_ac_v8_02_stale_working_tree() {
	need_tlc || return 0
	covered
	md_sub "| app/order.sh | $FNS |" "| app | $FNS |"
	commit_all "the model covers app/"
	verified_now
	sw formal check order
	assert_eq "$RC" 0 "exit code before the changes"
	printf '# edited\n' >>"$REPO/app/order.sh"
	printf 'new() { :; }\n' >"$REPO/app/new.sh"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: app/new\\.sh app/order\\.sh changed; "
}

# AC-V8-02: the model and its configurations are in the set, and so is the
# coverage table: a new row makes it stale, named as `## Coverage`.
test_ac_v8_02_stale_model_and_table() {
	need_tlc || return 0
	covered
	verified_now
	printf '\\* a comment\n' >>"$REPO/$F/order.tla"
	printf '\\* a comment\n' >>"$REPO/$F/order-shipunpaid.cfg"
	commit_all "the model changes"
	sw formal check order
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: architecture/formal/order-shipunpaid\\.cfg architecture/formal/order\\.tla changed; "
	verified_now
	sw formal check order
	assert_eq "$RC" 0 "exit code once verified again"
	printf 'extra() { :; }\n' >"$REPO/app/extra.sh"
	md_sub "| app/order.sh | $FNS |" "| app/order.sh | $FNS |
| app/extra.sh | extra |"
	commit_all "a row of the coverage table"
	sw formal check order
	assert_eq "$RC" 1 "exit code with a new row"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: ## Coverage app/extra\\.sh changed; "
}

# AC-V8-02: the record itself is not in the set: a change to its other
# sections, and the commit of the verdict, keep the model verified.
test_ac_v8_02_record_is_not_in_the_set() {
	need_tlc || return 0
	covered
	verified_now
	md_sub 'One order at a time;' 'One order at a time (said again);'
	commit_all "the record is reworded"
	sw formal check order
	assert_eq "$RC" 0 "exit code"
	assert_no_match "$OUT" "stale"
}

# AC-V8-03: a clean tree and a model that passes: the verdict is written on the
# first line of the section, the event is logged, nothing else of the record
# changes, and after the commit `formal check` is green.
test_ac_v8_03_records_the_verdict() {
	need_tlc || return 0
	covered
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order compatible
	assert_eq "$RC" 0 "exit code"
	head=$(git -C "$REPO" rev-parse HEAD)
	assert_match "$REPO/$MD" "^$head compatible [0-9a-f]{40} [0-9a-f]{40}$"
	diff "$T/before.md" "$REPO/$MD" >"$T/diff" || :
	assert_eq "$(grep -c '^[<>]' "$T/diff")" 2 "changed lines"
	assert_match "$REPO/$EVENTS_REL" '"event":"formal_verified".*"detail":"order compatible '"$(printf '%s' "$head" | cut -c1-7)"'"'
	assert_match "$OUT" "^formal verified: order compatible \\($(printf '%s' "$head" | cut -c1-7)\\)$"
	commit_all "verdict"
	sw formal check order
	assert_eq "$RC" 0 "formal check after the commit"
	assert_no_match "$OUT" "stale"
	assert_no_match "$OUT" "never verified"
}

# AC-V8-03: what is not committed in the set stops it, and nothing is written.
test_ac_v8_03_refuses_uncommitted() {
	covered
	printf '# edited\n' >>"$REPO/app/order.sh"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order compatible
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal verified: uncommitted changes in app/order\\.sh; commit them first$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
	git -C "$REPO" checkout -q app/order.sh
	printf 'extra() { :; }\n' >"$REPO/app/extra.sh"
	md_sub "| app/order.sh | $FNS |" "| app | $FNS |"
	commit_all "the model covers app/"
	printf 'new() { :; }\n' >"$REPO/app/new.sh"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order compatible
	assert_eq "$RC" 1 "exit code with a new file"
	assert_match "$OUT" "^formal verified: uncommitted changes in app/new\\.sh; commit them first$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
}

# AC-V8-03: a model TLC does not pass is not verified, and nothing is written.
test_ac_v8_03_refuses_a_red_model() {
	need_tlc || return 0
	covered
	cp "$FORMALFIX/broken/order.cfg" "$REPO/$F/order.cfg"
	commit_all "a model that breaks an invariant"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order updated
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^formal order: FAIL: ShippedWasPaid violated$"
	assert_match "$OUT" "^formal verified: formal check order fails; nothing was written$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
}

# AC-V8-03: `compatible` says the model did not change: it must not have; and
# `updated` says it did.
test_ac_v8_03_verdict_follows_the_model() {
	need_tlc || return 0
	covered
	verified_now
	printf 'x() { :; }\n' >>"$REPO/app/order.sh"
	commit_all "the code changes, the model does not"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order updated
	assert_eq "$RC" 1 "updated with an unchanged model"
	assert_match "$OUT" "^formal verified: updated needs the model to have changed since [0-9a-f]{7}, but architecture/formal/order\\.tla and its configurations are the same; use compatible$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
	printf '\\* a comment\n' >>"$REPO/$F/order.tla"
	commit_all "the model changes"
	sw formal verified order compatible
	assert_eq "$RC" 1 "compatible with a changed model"
	assert_match "$OUT" "^formal verified: compatible needs the model to be unchanged since [0-9a-f]{7}, but architecture/formal/order\\.tla changed; use updated$"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
	sw formal verified order updated
	assert_eq "$RC" 0 "updated with a changed model"
	assert_match "$REPO/$MD" "^$(git -C "$REPO" rev-parse HEAD) updated [0-9a-f]{40} [0-9a-f]{40}$"
}

# AC-V8-03: a record that was never verified takes either verdict.
test_ac_v8_03_never_takes_both_verdicts() {
	need_tlc || return 0
	covered
	sw formal verified order updated
	assert_eq "$RC" 0 "updated from never"
	git -C "$REPO" checkout -q "$MD"
	sw formal verified order compatible
	assert_eq "$RC" 0 "compatible from never"
}

# AC-V8-03: bug and blocked are the human's: usage error and where to go; an
# unknown verdict or specification, and a wrong number of words, are too.
test_ac_v8_03_usage_and_human_verdicts() {
	covered
	cp "$REPO/$MD" "$T/before.md"
	for v in bug blocked; do
		sw formal verified order $v
		assert_eq "$RC" 2 "exit code for $v"
		assert_match "$OUT" "^formal verified: bug and blocked go to the human \\(./softwary job escalate <job> <question>\\)$"
	done
	sw formal verified order maybe
	assert_eq "$RC" 2 "exit code for an unknown verdict"
	assert_match "$OUT" "^usage: ./softwary formal verified <spec> compatible\\|updated$"
	sw formal verified ghost compatible
	assert_eq "$RC" 2 "exit code for an unknown specification"
	assert_match "$OUT" "^formal verified: no specification 'ghost' "
	sw formal verified order
	assert_eq "$RC" 2 "exit code for a missing verdict"
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
}

# AC-V8-03: a commit that is not there, and no digests (the older form), tell
# nothing about the model: either verdict is accepted, and the record gets the
# digests.
test_ac_v8_03_unknown_commit_takes_either_verdict() {
	need_tlc || return 0
	covered
	lv_set 1234567890123456789012345678901234567890
	commit_all "verified at a commit nobody has"
	sw formal verified order compatible
	assert_eq "$RC" 0 "compatible: $(cat "$OUT")"
	assert_match "$REPO/$MD" "^[0-9a-f]{40} compatible [0-9a-f]{40} [0-9a-f]{40}$"
	git -C "$REPO" checkout -q "$MD"
	sw formal verified order updated
	assert_eq "$RC" 0 "updated: $(cat "$OUT")"
	assert_match "$REPO/$MD" "^[0-9a-f]{40} updated [0-9a-f]{40} [0-9a-f]{40}$"
}

# digests_of: the model digest and the code digest of the record, as words.
digests_of() {
	lv_get | cut -d' ' -f3,4
}

# AC-V8-03: with digests, the verdict is judged by the recorded model digest
# and not by the commit: the commit may be anything.
test_ac_v8_03_digest_decides_not_the_commit() {
	need_tlc || return 0
	covered
	sw formal verified order compatible
	assert_eq "$RC" 0 "first verdict: $(cat "$OUT")"
	d=$(digests_of)
	lv_set "1234567890123456789012345678901234567890 compatible $d"
	commit_all "a commit nobody has, the digests of the model and the code"
	sw formal check order
	assert_eq "$RC" 0 "formal check with equal digests: $(cat "$OUT")"
	assert_no_match "$OUT" "unknown|stale"
	cp "$REPO/$MD" "$T/before.md"
	sw formal verified order updated
	assert_eq "$RC" 1 "updated with an unchanged model digest"
	assert_match "$OUT" "^formal verified: updated needs the model to have changed since 1234567, but "
	cmp -s "$T/before.md" "$REPO/$MD" || fail "the record was written"
	printf '\\* a comment\n' >>"$REPO/$F/order.tla"
	commit_all "the model changes"
	sw formal verified order compatible
	assert_eq "$RC" 1 "compatible with a changed model digest"
	assert_match "$OUT" "^formal verified: compatible needs the model to be unchanged since 1234567, but .*architecture/formal/order\\.tla"
	sw formal verified order updated
	assert_eq "$RC" 0 "updated with a changed model digest: $(cat "$OUT")"
}

# AC-V8-02: a verdict with digests is stale when the code or the model differs
# from what was verified, whatever the commit says: the covered directory's
# untracked file, a deleted file and a new row of the coverage table count.
test_ac_v8_02_digest_working_tree() {
	need_tlc || return 0
	covered
	md_sub "| app/order.sh | $FNS |" "| app | $FNS |"
	commit_all "the model covers app/"
	sw formal verified order compatible
	assert_eq "$RC" 0 "verified: $(cat "$OUT")"
	commit_all "verdict"
	sw formal check order
	assert_eq "$RC" 0 "exit code before the changes"
	printf 'new() { :; }\n' >"$REPO/app/new.sh"
	sw formal check order
	assert_eq "$RC" 1 "exit code with an untracked file"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: app/new\\.sh changed; "
	rm "$REPO/app/new.sh"
	sw formal check order
	assert_eq "$RC" 0 "exit code once it is gone"
	for f in order.tla order-shipunpaid.cfg; do
		printf '\\* a comment\n' >>"$REPO/$F/$f"
		sw formal check order
		assert_eq "$RC" 1 "exit code with a changed $f"
		assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: $F/$(printf '%s' "$f" | sed 's/\./\\./') changed; "
		git -C "$REPO" checkout -q "$F/$f"
	done
	rm "$REPO/app/order.sh"
	sw formal check order
	assert_eq "$RC" 1 "exit code with a deleted file"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: app/order\\.sh changed; "
	git -C "$REPO" checkout -q app/order.sh
	md_sub "| app | $FNS |" "| app | $FNS |
| planned | - |"
	sw formal check order
	assert_eq "$RC" 1 "exit code with a new row"
	assert_match "$OUT" "^formal order: stale since [0-9a-f]{7}: ## Coverage changed; "
}

# AC-V8-02: the verdict outlives the commit it was written at. The job verifies
# on its branch, the branch is squash-merged and deleted and the repository is
# pruned: the commit is gone, the squashed branch passes and still sees a later
# change, and `formal verified` still judges by the digest.
test_ac_v8_02_survives_a_squash_merge() {
	need_tlc || return 0
	covered
	git -C "$REPO" checkout -q -b job
	printf '# a change of the job\n' >>"$REPO/app/order.sh"
	commit_all "the job changes the code"
	sw formal verified order compatible
	assert_eq "$RC" 0 "verified: $(cat "$OUT")"
	sha=$(lv_get | cut -d' ' -f1)
	commit_all "the job records the verdict"
	git -C "$REPO" checkout -q main
	git -C "$REPO" merge -q --squash job >/dev/null 2>&1 || fail "squash merge failed"
	commit_all "squashed"
	git -C "$REPO" branch -q -D job
	git -C "$REPO" reflog expire --expire=now --all
	git -C "$REPO" gc -q --prune=now
	git -C "$REPO" cat-file -e "$sha^{commit}" 2>/dev/null && fail "the verified commit is still there"
	sw formal check order
	assert_eq "$RC" 0 "formal check on the squashed branch: $(cat "$OUT")"
	assert_no_match "$OUT" "unknown|stale"
	sha7=$(printf '%s' "$sha" | cut -c1-7)
	printf '# a later change\n' >>"$REPO/app/order.sh"
	commit_all "the code changes"
	sw formal check order
	assert_eq "$RC" 1 "exit code after a later change"
	assert_match "$OUT" "^formal order: stale: the code or the model changed since it was verified \\($sha7\\): ## Coverage app/order\\.sh; check the model and record a verdict "
	sw formal verified order updated
	assert_eq "$RC" 1 "updated: the model digest is the recorded one"
	sw formal verified order compatible
	assert_eq "$RC" 0 "compatible: $(cat "$OUT")"
}

# AC-V8-02: the forms of the line: the commit alone, with a verdict, and with the
# two digests; anything else (a verdict that is not one, one digest, a digest
# that is not 40 digits) is a problem of the record.
test_ac_v8_02_line_forms() {
	covered
	sha=$(git -C "$REPO" rev-parse HEAD)
	d=0123456789012345678901234567890123456789
	for ok in "$sha" "$sha updated" "$sha compatible $d $d"; do
		lv_set "$ok"
		sw blueprint check
		assert_no_match "$OUT" "Last verified"
	done
	for bad in "$sha compatible $d" "$sha bug $d $d" "$sha compatible $d xyz" "$sha $d $d" "$sha compatible $d $d $d"; do
		lv_set "$bad"
		sw blueprint check
		assert_eq "$RC" 1 "exit code for [$bad]"
		assert_match "$OUT" "^$MD: '## Last verified' must be "
	done
}

run_tests "$0"
