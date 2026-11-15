# shellcheck shell=sh
# softwary: `job`. Sourced by bin/softwary. POSIX sh.
#
# A job is one slice (NNN-S<n>) on its way to the integration branch. Its
# state lives in .softwary/state/jobs/<job>/job (key=value lines: state,
# round, started, tokens, branch, pr); the only writer of `state` is
# sw_job_apply, which follows lib/transitions.json and logs every change in
# the event log. The run (.softwary/state/run: started, tokens, stopped)
# bounds the jobs together.

SW_JOBS_REL=.softwary/state/jobs
SW_RUN_REL=.softwary/state/run
SW_GATE_FLAKY="flaky gate: failed once, passed on retry"

sw_job_tbl() {
	printf '%s' "$SOFTWARY_HOME/lib/transitions.json"
}

# sw_kvf_get FILE KEY / sw_kvf_put FILE KEY VALUE: key=value state files.
sw_kvf_get() {
	[ -f "$1" ] || return 0
	awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1"
}

sw_kvf_put() {
	mkdir -p "$(dirname "$1")" || return 2
	[ -f "$1" ] || : >"$1"
	_kp_k=$2 _kp_v=$3 awk '
		BEGIN { k = ENVIRON["_kp_k"]; v = ENVIRON["_kp_v"] }
		index($0, k "=") == 1 { print k "=" v; done = 1; next }
		{ print }
		END { if (!done) print k "=" v }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

sw_job_file() {
	printf '%s' "$SOFTWARY_ROOT/$SW_JOBS_REL/$1/job"
}

sw_job_get() {
	sw_kvf_get "$(sw_job_file "$1")" "$2"
}

sw_job_put() {
	sw_kvf_put "$(sw_job_file "$1")" "$2" "$3"
}

# sw_job_valid_id ID: NNN-S<n>.
sw_job_valid_id() {
	printf '%s\n' "$1" | grep -Eq '^[0-9]{3}-S[1-9][0-9]*$'
}

# sw_run_open: true while a run is open (started and not stopped).
sw_run_open() {
	[ -f "$SOFTWARY_ROOT/$SW_RUN_REL" ] && [ -z "$(sw_kvf_get "$SOFTWARY_ROOT/$SW_RUN_REL" stopped)" ]
}

sw_run_get() {
	sw_kvf_get "$SOFTWARY_ROOT/$SW_RUN_REL" "$1"
}

# sw_job_target FROM EVENT: prints "<to> <round>" of the table's transition
# (round is next, reset or -); nothing when the table has none.
sw_job_target() {
	jq -r --arg f "$1" --arg e "$2" '[.transitions[] | select(.from == $f and .event == $e)][0]
		| if . == null then empty else "\(.to) \(.round // "-")" end' "$(sw_job_tbl)"
}

# sw_job_terminal STATE: true for a state with no way out (merged, abandoned).
sw_job_terminal() {
	jq -e --arg s "$1" '.terminal | index($s) != null' "$(sw_job_tbl)" >/dev/null
}

# sw_job_budget JOB: prints "budget: <key> <limit>" for the first limit that
# is exceeded (loop.conf must be loaded); nothing when all hold.
sw_job_budget() {
	_jb_now=$(date +%s)
	_jb_s=$(sw_job_get "$1" started)
	_jb_l=$(sw_loop_num max_job_minutes)
	if [ -n "$_jb_s" ] && [ -n "$_jb_l" ] && [ $((_jb_now - _jb_s)) -gt $((_jb_l * 60)) ]; then
		printf 'budget: max_job_minutes %s\n' "$_jb_l"
		return 0
	fi
	if sw_run_open; then
		_jb_s=$(sw_run_get started)
		_jb_l=$(sw_loop_num max_run_minutes)
		if [ -n "$_jb_s" ] && [ -n "$_jb_l" ] && [ $((_jb_now - _jb_s)) -gt $((_jb_l * 60)) ]; then
			printf 'budget: max_run_minutes %s\n' "$_jb_l"
			return 0
		fi
	fi
	_jb_t=$(sw_job_get "$1" tokens)
	_jb_l=$(sw_loop_num max_job_tokens)
	if [ -n "$_jb_l" ] && [ "${_jb_t:-0}" -gt "$_jb_l" ]; then
		printf 'budget: max_job_tokens %s\n' "$_jb_l"
		return 0
	fi
	if sw_run_open; then
		_jb_t=$(sw_run_get tokens)
		_jb_l=$(sw_loop_num max_run_tokens)
		if [ -n "$_jb_l" ] && [ "${_jb_t:-0}" -gt "$_jb_l" ]; then
			printf 'budget: max_run_tokens %s\n' "$_jb_l"
			return 0
		fi
	fi
	return 0
}

# sw_job_apply JOB EVENT [DETAIL]: the one function that changes a job's state.
# Applies the table's transition, or escalates the job when a limit is
# exceeded (the limits are not checked for escalate, resume, abandon and
# human_merged). Returns 0 applied (an escalation counts), 1 no such
# transition (nothing changes), 2 unknown job or unusable loop.conf.
sw_job_apply() {
	_ja_job=$1
	_ja_ev=$2
	_ja_detail=${3-}
	if [ ! -f "$(sw_job_file "$_ja_job")" ]; then
		printf 'job: unknown job %s\n' "$_ja_job"
		return 2
	fi
	if ! sw_loop_load; then
		printf '%s' "$SW_LOOP_ERRORS"
		return 2
	fi
	_ja_from=$(sw_job_get "$_ja_job" state)
	_ja_row=$(sw_job_target "$_ja_from" "$_ja_ev")
	if [ -z "$_ja_row" ]; then
		printf 'job %s: no transition for event %s in state %s\n' "$_ja_job" "$_ja_ev" "$_ja_from"
		return 1
	fi
	_ja_to=${_ja_row% *}
	_ja_rk=${_ja_row#* }
	_ja_round=$(sw_job_get "$_ja_job" round)
	_ja_round=${_ja_round:-0}
	_ja_started=
	case $_ja_ev in
	escalate | resume | abandon | human_merged) ;;
	*)
		if [ -n "$(sw_job_target "$_ja_from" escalate)" ]; then
			_ja_over=$(sw_job_budget "$_ja_job")
			if [ -z "$_ja_over" ] && [ "$_ja_rk" = next ] && [ $((_ja_round + 1)) -gt "$(sw_loop_num max_rounds)" ]; then
				_ja_over="round limit $(sw_loop_num max_rounds)"
			fi
			if [ -n "$_ja_over" ]; then
				_ja_ev=escalate
				_ja_to=escalated
				_ja_rk=-
				_ja_detail=$_ja_over
			fi
		fi
		;;
	esac
	case $_ja_rk in
	next) _ja_round=$((_ja_round + 1)) ;;
	reset)
		_ja_round=1
		_ja_started=$(date +%s)
		;;
	esac
	sw_job_put "$_ja_job" state "$_ja_to" || return 2
	sw_job_put "$_ja_job" round "$_ja_round" || return 2
	[ -z "$_ja_started" ] || sw_job_put "$_ja_job" started "$_ja_started"
	if [ "$_ja_to" = escalated ] && [ -n "$_ja_detail" ]; then
		printf '%s\n' "$_ja_detail" >"$SOFTWARY_ROOT/$SW_JOBS_REL/$_ja_job/escalation"
	fi
	sw_event "$_ja_job" "$_ja_ev" "$_ja_from" "$_ja_to" "$_ja_detail" || return 2
	printf 'job %s: %s -> %s%s\n' "$_ja_job" "$_ja_from" "$_ja_to" "${_ja_detail:+ ($_ja_detail)}"
}

# sw_job_locate JOB: sets SW_JOB_SPEC (directory name under specs/), SW_JOB_SLICE
# (S<n>) and SW_JOB_SLICEFILE; returns 1 when the job names no slice.
sw_job_locate() {
	sw_job_valid_id "$1" || return 1
	SW_JOB_SPEC=$(sw_plan_spec_dir "${1%%-*}") || return 1
	SW_JOB_SLICE=${1#*-}
	SW_JOB_SLICEFILE=$SOFTWARY_ROOT/specs/$SW_JOB_SPEC/slices/$SW_JOB_SLICE.md
	[ -f "$SW_JOB_SLICEFILE" ]
}

# sw_job_integration: prints the integration branch (commands.conf).
sw_job_integration() {
	sw_conf_load "$SOFTWARY_ROOT/$SW_CONF_REL"
	sw_conf_is_unset integration_branch && return 1
	sw_conf_get integration_branch
}

sw_job_branch_now() {
	git -C "$SOFTWARY_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null
}

sw_job_clean() {
	[ -z "$(git -C "$SOFTWARY_ROOT" status --porcelain 2>/dev/null)" ]
}

# sw_job_active: prints the jobs that are neither final nor waiting for a human.
sw_job_active() {
	for _jx in "$SOFTWARY_ROOT/$SW_JOBS_REL"/*/job; do
		[ -f "$_jx" ] || continue
		_jx_s=$(sw_kvf_get "$_jx" state)
		sw_job_terminal "$_jx_s" && continue
		[ "$_jx_s" != escalated ] || continue
		_jx=${_jx%/job}
		printf '%s\n' "${_jx##*/}"
	done
}

sw_job_refuse() {
	printf 'job %s: %s\n' "$1" "$2"
	return 1
}

# sw_job_start JOB: opens softwary/<job> and takes the job into its first round.
sw_job_start() {
	_js_job=$1
	sw_job_locate "$_js_job" || { printf 'job start: no slice %s\n' "$_js_job"; return 2; }
	_js_base=$(sw_job_integration) || { printf 'job start: integration_branch is not set in %s\n' "$SW_CONF_REL"; return 2; }
	_js_spec=$SW_JOB_SPEC
	_js_sfile=$SW_JOB_SLICEFILE
	[ ! -e "$(sw_job_file "$_js_job")" ] || { sw_job_refuse "$_js_job" "the job already exists"; return 1; }
	sw_run_open || { sw_job_refuse "$_js_job" "no open run (./softwary run start)"; return 1; }
	_js_act=$(sw_job_active)
	[ -z "$_js_act" ] || { sw_job_refuse "$_js_job" "another job is active: $(printf '%s' "$_js_act" | paste -sd' ' -)"; return 1; }
	[ "$(sw_job_branch_now)" = "$_js_base" ] || { sw_job_refuse "$_js_job" "not on the integration branch $_js_base"; return 1; }
	sw_job_clean || { sw_job_refuse "$_js_job" "working tree is not clean"; return 1; }
	if git -C "$SOFTWARY_ROOT" remote get-url origin >/dev/null 2>&1; then
		git -C "$SOFTWARY_ROOT" pull -q --ff-only origin "$_js_base" >/dev/null 2>&1 ||
			{ sw_job_refuse "$_js_job" "could not fast-forward $_js_base from origin"; return 1; }
	fi
	if git -C "$SOFTWARY_ROOT" rev-parse -q --verify "refs/heads/softwary/$_js_job" >/dev/null 2>&1; then
		sw_job_refuse "$_js_job" "branch softwary/$_js_job exists"
		return 1
	fi
	sw_fm_read "$_js_sfile"
	[ "$(sw_fm_get status)" = planned ] || { sw_job_refuse "$_js_job" "slice is not planned"; return 1; }
	sw_fm_read "$SOFTWARY_ROOT/specs/$_js_spec/spec.md"
	[ "$(sw_fm_get status)" = approved ] || { sw_job_refuse "$_js_job" "spec ${_js_job%%-*} is not approved"; return 1; }
	sw_fm_read "$_js_sfile"
	for _js_d in $(sw_list "$(sw_fm_get depends_on)"); do
		case $_js_d in S*) _js_d=${_js_job%%-*}-$_js_d ;; esac
		_js_df=
		for _js_x in "$SOFTWARY_ROOT"/specs/"${_js_d%%-*}"-*/slices/"${_js_d#*-}".md; do
			[ -f "$_js_x" ] && _js_df=$_js_x
		done
		_js_ds=
		if [ -n "$_js_df" ]; then
			sw_fm_read "$_js_df"
			_js_ds=$(sw_fm_get status)
		fi
		[ "$_js_ds" = "done" ] || { sw_job_refuse "$_js_job" "dependency $_js_d is not done"; return 1; }
		sw_fm_read "$_js_sfile"
	done
	for _js_k in $SW_APPROVAL_KINDS; do
		_js_a=$(sw_approval_state "$_js_k") || { sw_job_refuse "$_js_job" "approvals.conf is malformed"; return 1; }
		[ "$_js_a" = approved ] || { sw_job_refuse "$_js_job" "$_js_k approval is $_js_a"; return 1; }
	done
	git -C "$SOFTWARY_ROOT" checkout -q -b "softwary/$_js_job" || return 2
	mkdir -p "$SOFTWARY_ROOT/$SW_JOBS_REL/$_js_job" || return 2
	sw_job_put "$_js_job" state ready
	sw_job_put "$_js_job" round 0
	sw_job_put "$_js_job" started "$(date +%s)"
	sw_job_put "$_js_job" tokens 0
	sw_job_put "$_js_job" branch "softwary/$_js_job"
	sw_job_apply "$_js_job" start "softwary/$_js_job"
}

# sw_job_verify_base BASE: the ref verify compares with.
sw_job_verify_base() {
	if git -C "$SOFTWARY_ROOT" rev-parse -q --verify "refs/remotes/origin/$1" >/dev/null 2>&1; then
		printf 'origin/%s\n' "$1"
	else
		printf '%s\n' "$1"
	fi
}

# sw_job_on_branch JOB: returns 2 (with a message) unless the job's branch is
# checked out in a clean tree.
sw_job_on_branch() {
	[ "$(sw_job_branch_now)" = "softwary/$1" ] || { printf 'job %s: not on branch softwary/%s\n' "$1" "$1"; return 2; }
	sw_job_clean || { printf 'job %s: working tree is not clean\n' "$1"; return 2; }
}

# sw_job_gate JOB: the full verify on the job branch; one retry tells a flaky
# test from a failing one.
sw_job_gate() {
	_jg_job=$1
	[ -f "$(sw_job_file "$_jg_job")" ] || { printf 'job: unknown job %s\n' "$_jg_job"; return 2; }
	_jg_st=$(sw_job_get "$_jg_job" state)
	[ "$_jg_st" = gating ] || { sw_job_refuse "$_jg_job" "state is $_jg_st, not gating"; return 1; }
	sw_job_on_branch "$_jg_job" || return 2
	_jg_base=$(sw_job_verify_base "$(sw_job_integration)")
	_jg_log=$SOFTWARY_ROOT/$SW_JOBS_REL/$_jg_job/gate-$(sw_job_get "$_jg_job" round).log
	_jg_rc=0
	sh "$SOFTWARY_HOME/bin/softwary" verify --base "$_jg_base" >"$_jg_log" 2>&1 || _jg_rc=$?
	if [ "$_jg_rc" -eq 0 ]; then
		sw_job_apply "$_jg_job" gate_pass
		return $?
	fi
	[ "$_jg_rc" -ne 2 ] || { cat "$_jg_log"; return 2; }
	_jg_rc=0
	sh "$SOFTWARY_HOME/bin/softwary" verify --base "$_jg_base" >"$_jg_log.retry" 2>&1 || _jg_rc=$?
	if [ "$_jg_rc" -eq 0 ]; then
		sw_job_apply "$_jg_job" escalate "$SW_GATE_FLAKY"
	else
		sw_job_apply "$_jg_job" gate_fail "verify failed (see $SW_JOBS_REL/$_jg_job/gate-$(sw_job_get "$_jg_job" round).log)"
	fi
}

# sw_job_tokens JOB N: adds N to the job's and the run's token totals.
sw_job_tokens() {
	[ -f "$(sw_job_file "$1")" ] || { printf 'job: unknown job %s\n' "$1"; return 2; }
	sw_positive_int "$2" || { printf 'usage: ./softwary job tokens <job> <n>\n' >&2; return 2; }
	sw_job_put "$1" tokens $(($(sw_job_get "$1" tokens) + $2))
	if sw_run_open; then
		sw_kvf_put "$SOFTWARY_ROOT/$SW_RUN_REL" tokens $(($(sw_run_get tokens) + $2))
	fi
	_jt_st=$(sw_job_get "$1" state)
	sw_event "$1" tokens "$_jt_st" "$_jt_st" "$2" || return 2
	printf 'job %s: +%s tokens (job total %s)\n' "$1" "$2" "$(sw_job_get "$1" tokens)"
}

# sw_job_state_is JOB STATE: refuses (return 1) unless the job is in STATE.
sw_job_state_is() {
	_jsi=$(sw_job_get "$1" state)
	[ "$_jsi" = "$2" ] || { sw_job_refuse "$1" "state is $_jsi, not $2"; return 1; }
}

# sw_job_known JOB: returns 2 (with a message) for a job that does not exist.
sw_job_known() {
	[ -f "$(sw_job_file "$1")" ] || { printf 'job: unknown job %s\n' "$1"; return 2; }
}

# sw_job_push JOB: pushes the job's branch (the script gates itself, so the
# git hooks are skipped).
sw_job_push() {
	if ! _jpo=$(git -C "$SOFTWARY_ROOT" push -q --no-verify -u origin "softwary/$1" 2>&1); then
		printf 'job %s: push failed: %s\n' "$1" "$_jpo"
		return 1
	fi
}

# sw_job_pr JOB: pushes the branch and opens the PR (once), then pr_opened.
sw_job_pr() {
	_jp_job=$1
	sw_job_known "$_jp_job" || return 2
	sw_job_state_is "$_jp_job" pr || return 1
	[ "$(sw_job_branch_now)" = "softwary/$_jp_job" ] || { printf 'job %s: not on branch softwary/%s\n' "$_jp_job" "$_jp_job"; return 2; }
	_jp_base=$(sw_job_integration) || { printf 'job pr: integration_branch is not set\n'; return 2; }
	sw_job_push "$_jp_job" || return 1
	_jp_n=$(sw_job_get "$_jp_job" pr)
	if [ -z "$_jp_n" ]; then
		sw_job_locate "$_jp_job" || return 2
		sw_fm_read "$SW_JOB_SLICEFILE"
		_jp_goal=$(sw_fm_get goal)
		if ! _jp_out=$(gh pr create --base "$_jp_base" --head "softwary/$_jp_job" --title "$_jp_job: $_jp_goal" \
			--body "Spec: specs/$SW_JOB_SPEC/spec.md. Slice: specs/$SW_JOB_SPEC/slices/$SW_JOB_SLICE.md." 2>&1); then
			sw_job_refuse "$_jp_job" "gh pr create failed: $_jp_out"
			return 1
		fi
		_jp_url=$(printf '%s\n' "$_jp_out" | tail -n 1)
		_jp_n=${_jp_url##*/}
		sw_positive_int "$_jp_n" || { sw_job_refuse "$_jp_job" "gh pr create printed no PR number: $_jp_url"; return 1; }
		sw_job_put "$_jp_job" pr "$_jp_n"
	fi
	sw_job_apply "$_jp_job" pr_opened "PR #$_jp_n"
}

# sw_job_pr_green JOB SHA: true when the PR's head is SHA and its checks pass.
# On failure SW_JOB_WHY says which.
sw_job_pr_green() {
	_jq_n=$(sw_job_get "$1" pr)
	_jq_head=$(gh pr view "$_jq_n" --json headRefOid --jq .headRefOid 2>/dev/null) || _jq_head=
	if [ "$_jq_head" != "$2" ]; then
		SW_JOB_WHY="PR head is not ${3:-HEAD}"
		return 1
	fi
	if ! gh pr checks "$_jq_n" --watch >"$SOFTWARY_ROOT/$SW_JOBS_REL/$1/ci.log" 2>&1; then
		SW_JOB_WHY="CI checks are not green"
		return 1
	fi
}

# sw_job_ci JOB: ci_pass when the PR's head is HEAD and its checks pass.
sw_job_ci() {
	_jc_job=$1
	sw_job_known "$_jc_job" || return 2
	sw_job_state_is "$_jc_job" ci || return 1
	[ "$(sw_job_branch_now)" = "softwary/$_jc_job" ] || { printf 'job %s: not on branch softwary/%s\n' "$_jc_job" "$_jc_job"; return 2; }
	[ -n "$(sw_job_get "$_jc_job" pr)" ] || { sw_job_refuse "$_jc_job" "no PR recorded"; return 1; }
	if sw_job_pr_green "$_jc_job" "$(git -C "$SOFTWARY_ROOT" rev-parse HEAD)"; then
		sw_job_apply "$_jc_job" ci_pass
	else
		sw_job_apply "$_jc_job" ci_fail "$SW_JOB_WHY"
	fi
}

# sw_fm_status_set FILE VALUE: sets the front matter's status line.
sw_fm_status_set() {
	awk -v v="$2" '
		NR == 1 { print; next }
		!closed && $0 ~ /^---[ \t\r]*$/ { closed = 1 }
		!closed && !done && /^status:/ { print "status: " v ($0 ~ /\r$/ ? "\r" : ""); done = 1; next }
		{ print }' "$1" >"$1.tmp" && cat "$1.tmp" >"$1" && rm -f "$1.tmp"
}

# sw_job_review JOB: reads the slice's review record; approve makes the slice
# done, both commit and push the record before the transition.
sw_job_review() {
	_jr_job=$1
	sw_job_known "$_jr_job" || return 2
	sw_job_state_is "$_jr_job" reviewing || return 1
	sw_job_locate "$_jr_job" || return 2
	_jr_rel=specs/$SW_JOB_SPEC/reviews/$SW_JOB_SLICE.md
	[ -f "$SOFTWARY_ROOT/$_jr_rel" ] || { sw_job_refuse "$_jr_job" "no review record ($_jr_rel)"; return 1; }
	sw_fm_read "$SOFTWARY_ROOT/$_jr_rel"
	_jr_dec=$(sw_fm_get decision)
	if [ -n "$(sw_fm_errors)" ] || [ "$(sw_fm_get slice)" != "$SW_JOB_SLICE" ] || ! sw_in_list "$_jr_dec" "$SW_REVIEW_DECISIONS"; then
		sw_job_refuse "$_jr_job" "the review record $_jr_rel is invalid (slice: $SW_JOB_SLICE, decision: approve or changes)"
		return 1
	fi
	[ "$(sw_job_branch_now)" = "softwary/$_jr_job" ] || { printf 'job %s: not on branch softwary/%s\n' "$_jr_job" "$_jr_job"; return 2; }
	_jr_files=$_jr_rel
	_jr_msg="$_jr_job: review requested changes"
	if [ "$_jr_dec" = approve ]; then
		sw_fm_status_set "$SW_JOB_SLICEFILE" "done"
		_jr_files="$_jr_rel specs/$SW_JOB_SPEC/slices/$SW_JOB_SLICE.md"
		_jr_msg="$_jr_job: review approved"
	fi
	# shellcheck disable=SC2086 # two repo-relative paths without whitespace
	git -C "$SOFTWARY_ROOT" add -- $_jr_files || return 2
	if ! git -C "$SOFTWARY_ROOT" diff --cached --quiet; then
		git -C "$SOFTWARY_ROOT" commit -q --no-verify -m "$_jr_msg" || { printf 'job %s: commit failed\n' "$_jr_job"; return 2; }
	fi
	sw_job_push "$_jr_job" || return 1
	sw_job_apply "$_jr_job" "review_$_jr_dec" "$_jr_dec"
}

# sw_job_text JOB EVENT TEXT FILE: an event that carries the human's or the
# agent's words, kept in FILE of the job directory too.
sw_job_text() {
	sw_job_known "$1" || return 2
	[ -n "$3" ] || { sw_job_usage; return 2; }
	sw_job_apply "$1" "$2" "$3" || return $?
	[ -z "$4" ] || printf '%s\n' "$3" >"$SOFTWARY_ROOT/$SW_JOBS_REL/$1/$4"
}

# sw_job_merged JOB: a human merged the PR (an R3 change, or a refused merge).
sw_job_merged() {
	sw_job_known "$1" || return 2
	sw_job_state_is "$1" escalated || return 1
	_jm_n=$(sw_job_get "$1" pr)
	[ -n "$_jm_n" ] || { sw_job_refuse "$1" "no PR recorded"; return 1; }
	_jm_st=$(gh pr view "$_jm_n" --json state --jq .state 2>/dev/null) || _jm_st=
	[ "$_jm_st" = MERGED ] || { sw_job_refuse "$1" "PR #$_jm_n is ${_jm_st:-not readable}, not MERGED"; return 1; }
	sw_job_apply "$1" human_merged "PR #$_jm_n"
}

# sw_job_show JOB: the job file, the open question and the last events.
sw_job_show() {
	sw_job_known "$1" || return 2
	cat "$(sw_job_file "$1")"
	_jh_q=$SOFTWARY_ROOT/$SW_JOBS_REL/$1/escalation
	[ "$(sw_job_get "$1" state)" != escalated ] || [ ! -f "$_jh_q" ] || printf 'question: %s\n' "$(cat "$_jh_q")"
	[ ! -f "$SOFTWARY_ROOT/$SW_EVENTS_REL" ] || jq -c --arg j "$1" 'select(.job == $j)' "$SOFTWARY_ROOT/$SW_EVENTS_REL" | tail -n 5
	return 0
}

sw_job_usage() {
	printf 'usage: ./softwary job start|gate|pr|ci|review|merged|show <job>, job escalate|resume|abandon <job> <text>,\n       job event <job> <event> [detail], job tokens <job> <n>\n' >&2
}

# sw_job SUBCOMMAND JOB [ARGS]
sw_job() {
	_jc=${1:-}
	[ $# -ge 2 ] || { sw_job_usage; return 2; }
	shift
	_jj=$1
	shift
	case $_jc in
	event)
		[ $# -ge 1 ] || { sw_job_usage; return 2; }
		_je=$1
		shift
		sw_job_apply "$_jj" "$_je" "$*"
		;;
	start)
		[ $# -eq 0 ] || { sw_job_usage; return 2; }
		sw_job_start "$_jj"
		;;
	gate)
		[ $# -eq 0 ] || { sw_job_usage; return 2; }
		sw_job_gate "$_jj"
		;;
	tokens)
		[ $# -eq 1 ] || { sw_job_usage; return 2; }
		sw_job_tokens "$_jj" "$1"
		;;
	pr | ci | review | merged | show)
		[ $# -eq 0 ] || { sw_job_usage; return 2; }
		"sw_job_$_jc" "$_jj"
		;;
	escalate) sw_job_text "$_jj" escalate "$*" "" ;;
	resume) sw_job_text "$_jj" resume "$*" answer ;;
	abandon) sw_job_text "$_jj" abandon "$*" "" ;;
	*)
		sw_job_usage
		return 2
		;;
	esac
}
