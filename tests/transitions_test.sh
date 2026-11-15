#!/bin/sh
# Tests for lib/transitions.json and `job event` (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

TABLE=$PKG_ROOT/src/lib/transitions.json
JOB=001-S1
EVENTS_REL=.softwary/state/events.log

# put_job STATE [ROUND]: writes the job file of $JOB in STATE.
put_job() {
	mkdir -p "$REPO/.softwary/state/jobs/$JOB"
	printf 'state=%s\nround=%s\nstarted=%s\ntokens=0\nbranch=softwary/%s\n' "$1" "${2:-1}" "$(date +%s)" "$JOB" \
		>"$REPO/.softwary/state/jobs/$JOB/job"
}

job_state() {
	sed -n 's/^state=//p' "$REPO/.softwary/state/jobs/$JOB/job"
}

log_lines() {
	if [ -f "$REPO/$EVENTS_REL" ]; then wc -l <"$REPO/$EVENTS_REL" | tr -d ' '; else echo 0; fi
}

# AC-V2-07: the table is well formed.
test_ac_v2_07_table_is_well_formed() {
	jq -e . "$TABLE" >/dev/null || fail "transitions.json is not valid JSON"
	bad=$(jq -r '.states as $s | .terminal as $t | .transitions[]
		| select(((.from | IN($s[])) and (.to | IN($s[]))) | not) | "\(.from) \(.event) \(.to)"' "$TABLE")
	[ -z "$bad" ] || fail "transitions with unknown states: $bad"
	bad=$(jq -r '.terminal as $t | .transitions[] | select(.from | IN($t[])) | "\(.from) \(.event)"' "$TABLE")
	[ -z "$bad" ] || fail "transitions out of a final state: $bad"
	bad=$(jq -r '[.transitions[] | "\(.from) \(.event)"] | group_by(.) | map(select(length > 1) | .[0])[]' "$TABLE")
	[ -z "$bad" ] || fail "duplicate (from, event) pairs: $bad"
	bad=$(jq -r '. as $d | $d.terminal[] | select(. as $t | $d.states | index($t) == null)' "$TABLE")
	[ -z "$bad" ] || fail "terminal states not in states: $bad"
	bad=$(jq -r '.transitions[] | select(has("round") and (.round | IN("next", "reset") | not)) | .event' "$TABLE")
	[ -z "$bad" ] || fail "invalid round values on: $bad"
}

# AC-V2-07: the table is the one D-72 describes (a deleted or changed row fails here).
test_ac_v2_07_table_is_the_decided_one() {
	want='approving escalate escalated -
approving merged merged -
ci ci_fail implementing next
ci ci_pass reviewing -
ci escalate escalated -
escalated abandon abandoned -
escalated human_merged merged -
escalated resume implementing reset
gating escalate escalated -
gating gate_fail implementing next
gating gate_pass pr -
implementing escalate escalated -
implementing implemented gating -
pr escalate escalated -
pr pr_opened ci -
ready start implementing next
reviewing escalate escalated -
reviewing review_approve approving -
reviewing review_changes implementing next'
	got=$(jq -r '.transitions[] | "\(.from) \(.event) \(.to) \(.round // "-")"' "$TABLE" | LC_ALL=C sort)
	assert_eq "$got" "$(printf '%s\n' "$want" | LC_ALL=C sort)" "transitions"
	assert_eq "$(jq -r '.states | join(" ")' "$TABLE")" "ready implementing gating pr ci reviewing approving merged escalated abandoned" "states"
	assert_eq "$(jq -r '.terminal | join(" ")' "$TABLE")" "merged abandoned" "terminal"
}

# AC-V2-07: every (state, event) pair of the table: a transition in the table
# gives the new state and one log line, any other pair changes nothing.
test_ac_v2_07_every_pair() {
	setup_repo
	pairs=0
	for state in $(jq -r '.states[]' "$TABLE"); do
		for ev in $(jq -r '[.transitions[].event] | unique[]' "$TABLE"); do
			pairs=$((pairs + 1))
			put_job "$state"
			before=$(log_lines)
			sw job event "$JOB" "$ev"
			want=$(jq -r --arg f "$state" --arg e "$ev" '[.transitions[] | select(.from == $f and .event == $e)][0].to // empty' "$TABLE")
			if [ -n "$want" ]; then
				assert_eq "$RC" 0 "exit code for $state + $ev"
				assert_eq "$(job_state)" "$want" "state after $state + $ev"
				assert_eq "$(log_lines)" $((before + 1)) "log lines for $state + $ev"
				last=$(tail -n 1 "$REPO/$EVENTS_REL")
				assert_eq "$(printf '%s' "$last" | jq -r '[.job, .event, .from, .to] | join(" ")')" "$JOB $ev $state $want" "log line for $state + $ev"
				printf '%s' "$last" | jq -e '.time | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")' >/dev/null || fail "bad time in $last"
				printf '%s' "$last" | jq -e 'has("detail")' >/dev/null || fail "no detail in $last"
			else
				assert_eq "$RC" 1 "exit code for $state + $ev"
				assert_eq "$(job_state)" "$state" "state after the refused $state + $ev"
				assert_eq "$(log_lines)" "$before" "log lines after the refused $state + $ev"
			fi
		done
	done
	[ "$pairs" -ge 100 ] || fail "only $pairs pairs were tried"
}

# AC-V2-07: an unknown job and a missing argument exit 2.
test_ac_v2_07_unknown_job_exits_2() {
	setup_repo
	sw job event 009-S9 start
	assert_eq "$RC" 2 "exit code for an unknown job"
	assert_contains "$OUT" "unknown job 009-S9"
	sw job event "$JOB"
	assert_eq "$RC" 2 "exit code without an event"
	sw job
	assert_eq "$RC" 2 "exit code without a subcommand"
	[ ! -e "$REPO/$EVENTS_REL" ] || fail "an event was logged"
}

# AC-V2-07: a turn-opening transition counts rounds; resume starts again at 1.
test_ac_v2_07_rounds_count() {
	setup_repo
	put_job ready 0
	sw job event "$JOB" start
	assert_eq "$(sed -n 's/^round=//p' "$REPO/.softwary/state/jobs/$JOB/job")" 1 "round after start"
	sw job event "$JOB" implemented
	sw job event "$JOB" gate_fail
	assert_eq "$(sed -n 's/^round=//p' "$REPO/.softwary/state/jobs/$JOB/job")" 2 "round after gate_fail"
	sw job event "$JOB" escalate "which database?"
	assert_eq "$(cat "$REPO/.softwary/state/jobs/$JOB/escalation")" "which database?" "escalation file"
	sw job event "$JOB" resume
	assert_eq "$(sed -n 's/^round=//p' "$REPO/.softwary/state/jobs/$JOB/job")" 1 "round after resume"
}

run_tests "$0"
