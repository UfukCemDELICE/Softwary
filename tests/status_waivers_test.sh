#!/bin/sh
# Tests for the section "Waivers and findings" of `status` and `handoff` (V6).
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

WAIVERS_REL=.softwary/config/waivers.conf
MD=architecture/formal/order.md

# tomorrow: tomorrow's date as YYYY-MM-DD (GNU or BSD date).
tomorrow() {
	date -d '+1 day' +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d
}

# days_of LINE: the number of days left that a line says.
days_of() {
	printf '%s\n' "$1" | sed -n 's/.*(\([0-9][0-9]*\) days\{0,1\} left).*/\1/p'
}

# AC-V6-09: status lists every waiver and every finding with its date, the
# days left (or expired) and its reason.
test_ac_v6_09_status_lists_waivers_and_findings() {
	setup_repo
	add_product
	add_blueprint
	add_formal
	today=$(date +%Y-%m-%d)
	cat >"$REPO/$WAIVERS_REL" <<EOF
lint = 2999-12-31: legacy lint debt
test = $today: flaky suite, fixed today
build = $(tomorrow): slow build
security = 2000-01-01: scanner licence
EOF
	printf '\n## Findings\n\n| Invariant | Until | Reason |\n| --- | --- | --- |\n| `ShippedWasPaid` | 2999-12-31 | The old order code ships a created order. |\n| `CancelledNeverShipped` | 2000-01-02 | Refund path. |\n' >>"$REPO/$MD"
	snapshot >"$T/before"
	sw status
	assert_eq "$RC" 0 "exit code"
	snapshot >"$T/after"
	assert_eq "$(changed_paths "$T/before" "$T/after")" "" "status writes nothing"
	assert_match "$OUT" "^Waivers and findings:$"
	assert_match "$OUT" "^  waiver lint: until 2999-12-31 \\([0-9]+ days left\\): legacy lint debt$"
	assert_match "$OUT" "^  waiver test: until $today \\(0 days left\\): flaky suite, fixed today$"
	assert_match "$OUT" "^  waiver build: until $(tomorrow) \\(1 day left\\): slow build$"
	assert_match "$OUT" "^  waiver security: until 2000-01-01 \\(expired\\): scanner licence$"
	assert_match "$OUT" "^  finding order/ShippedWasPaid: until 2999-12-31 \\([0-9]+ days left\\): The old order code ships a created order\\.$"
	assert_match "$OUT" "^  finding order/CancelledNeverShipped: until 2000-01-02 \\(expired\\): Refund path\\.$"
	assert_no_match "$OUT" "\\(none\\)"
}

# AC-V6-09: with nothing to list the section says so, in status and handoff.
test_ac_v6_09_none() {
	setup_repo
	sw status
	assert_match "$OUT" "^Waivers and findings:$"
	assert_match "$OUT" "^  \\(none\\)$"
	sw handoff
	assert_eq "$RC" 0 "handoff exit code"
	f=$REPO/.softwary/state/handoff.md
	assert_eq "$(awk '/^## Waivers and findings$/ { on = 1; next } on && /^## / { exit } on && NF { print }' "$f")" "(none)" "the handoff's section"
}

# AC-V6-09: handoff has the section with the same lines, between the approvals
# and the jobs.
test_ac_v6_09_handoff_section() {
	setup_repo
	add_product
	add_blueprint
	add_formal
	printf 'lint = 2999-12-31: legacy lint debt\nsecurity = 2000-01-01: scanner licence\n' >"$REPO/$WAIVERS_REL"
	printf '\n## Findings\n\n| Invariant | Until | Reason |\n| --- | --- | --- |\n| `ShippedWasPaid` | 2999-12-31 | The old order code ships a created order. |\n' >>"$REPO/$MD"
	sw handoff
	assert_eq "$RC" 0 "exit code"
	f=$REPO/.softwary/state/handoff.md
	assert_match "$f" "^## Waivers and findings$"
	assert_match "$f" "^waiver lint: until 2999-12-31 \\([0-9]+ days left\\): legacy lint debt$"
	assert_match "$f" "^waiver security: until 2000-01-01 \\(expired\\): scanner licence$"
	assert_match "$f" "^finding order/ShippedWasPaid: until 2999-12-31 \\([0-9]+ days left\\): The old order code ships a created order\\.$"
	a=$(grep -n '^## Approvals$' "$f" | cut -d: -f1)
	w=$(grep -n '^## Waivers and findings$' "$f" | cut -d: -f1)
	j=$(grep -n '^## Jobs$' "$f" | cut -d: -f1)
	[ "$a" -lt "$w" ] && [ "$w" -lt "$j" ] || fail "the section is not between Approvals and Jobs ($a $w $j)"
}

# AC-V6-09: the days are counted by the calendar: a leap year has its 29th of
# February, a year ends on the 31st of December.
test_ac_v6_09_days_left_by_the_calendar() {
	setup_repo
	cat >"$REPO/$WAIVERS_REL" <<'EOF'
lint = 2096-02-28: leap year, before
test = 2096-03-01: leap year, after
build = 2095-02-28: common year, before
security = 2095-03-01: common year, after
format_check = 2999-12-31: end of a year
typecheck = 3000-01-01: start of the next
EOF
	sw status
	n() { days_of "$(grep "waiver $1:" "$OUT")"; }
	assert_eq $(($(n test) - $(n lint))) 2 "28 February to 1 March in a leap year"
	assert_eq $(($(n security) - $(n build))) 1 "28 February to 1 March in a common year"
	assert_eq $(($(n typecheck) - $(n format_check))) 1 "31 December to 1 January"
	# 2096-02-28 is later than 2095-03-01 by 364 days (the year between has no 29 February)
	assert_eq $(($(n lint) - $(n security))) 364 "a year apart"
}

run_tests "$0"
