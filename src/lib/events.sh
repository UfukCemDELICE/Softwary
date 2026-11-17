# shellcheck shell=sh
# softwary: the event log. Sourced by bin/softwary. POSIX sh.
#
# .softwary/state/events.log of the main checkout has one JSON object per
# line: time, job, event, from, to and detail. State is local
# (.softwary/.gitignore ignores state/). A line is written under the state
# lock, so that lines of commands that run together never mix.

SW_EVENTS_REL=.softwary/state/events.log

# sw_event JOB EVENT FROM TO DETAIL: appends one line to the event log.
# Events that are not about a job use "-" for JOB, FROM and TO.
sw_event() {
	sw_state_locked sw_event_write "$@"
}

sw_event_write() {
	mkdir -p "$SW_STATE_ROOT/$SW_STATE_REL" || return 2
	jq -nc --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg job "$1" --arg event "$2" \
		--arg from "${3:--}" --arg to "${4:--}" --arg detail "${5-}" \
		'{time: $time, job: $job, event: $event, from: $from, to: $to, detail: $detail}' \
		>>"$SW_STATE_ROOT/$SW_EVENTS_REL"
}
