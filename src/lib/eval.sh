# shellcheck shell=sh
# softwary: `eval prepare` and `eval score`. Sourced by bin/softwary. POSIX sh.
#
# The evaluation measures how many deliberately broken changes the reviewer
# catches. The package ships a small sample project (eval/sample) and cases
# (eval/cases/<name>/: diff.patch, expect, kind). `eval prepare <dir>` builds
# one git repository per case: the sample with the installed softwary on
# `main`, the case's diff on `review`. The reviewer is run once per case, in
# a clean context, and writes its record there; `eval score <dir>` reads the
# records, lets `guard` catch what it catches and writes eval.conf.

SW_EVAL_REL=.softwary/state/eval
SW_EVAL_CONF_REL=.softwary/config/eval.conf
SW_EVAL_JOB=002-S1
SW_EVAL_RECORD=specs/002-tip/reviews/S1.md
SW_EVAL_IDENT="-c user.name=softwary-eval -c user.email=softwary-eval@example.invalid"

sw_eval_usage() {
	printf 'usage: ./softwary eval prepare <dir> | eval score <dir>\n' >&2
}

# sw_eval_cases: prints the names of the cases, in the order of the hash of
# their names (stable, and the order does not tell the kind).
sw_eval_cases() {
	for _ec in "$SOFTWARY_HOME"/eval/cases/*/; do
		[ -d "$_ec" ] || continue
		_ec=${_ec%/}
		_ec=${_ec##*/}
		printf '%s %s\n' "$(printf '%s' "$_ec" | git hash-object --stdin)" "$_ec"
	done | LC_ALL=C sort | while read -r _eh _ec; do
		printf '%s\n' "$_ec"
	done
}

# sw_eval_build CASEDIR NAME: one case repository (see the top of the file).
sw_eval_build() {
	_eb=$1
	mkdir -p "$_eb/.softwary" || return 1
	cp -R "$SOFTWARY_HOME/eval/sample/." "$_eb/" || return 1
	mv "$_eb/.softwary-config" "$_eb/.softwary/config" || return 1
	for _et in bin lib rules targets skills agents hooks templates local; do
		[ -d "$SOFTWARY_HOME/$_et" ] || continue
		cp -R "$SOFTWARY_HOME/$_et" "$_eb/.softwary/$_et" || return 1
	done
	for _ef in VERSION .gitignore; do
		[ -f "$SOFTWARY_HOME/$_ef" ] && { cp "$SOFTWARY_HOME/$_ef" "$_eb/.softwary/$_ef" || return 1; }
	done
	# the project's own choice of tools and models, so that the reviewer of
	# the case is the project's reviewer
	for _ef in tools.conf models.conf; do
		[ -f "$SOFTWARY_ROOT/.softwary/config/$_ef" ] && { cp "$SOFTWARY_ROOT/.softwary/config/$_ef" "$_eb/.softwary/config/$_ef" || return 1; }
	done
	cp "$SOFTWARY_ROOT/softwary" "$_eb/softwary" || return 1
	chmod +x "$_eb/softwary" "$_eb/.softwary/bin/softwary"
	git -C "$_eb" init -q || return 1
	git -C "$_eb" symbolic-ref HEAD refs/heads/main
	(
		cd "$_eb" || exit 1
		./softwary sync && ./softwary views && ./softwary approve product && ./softwary approve blueprint
	) >"$_eb.log" 2>&1 || { cat "$_eb.log"; return 1; }
	rm -f "$_eb.log"
	git -C "$_eb" add -A || return 1
	# shellcheck disable=SC2086 # SW_EVAL_IDENT is a list of git options
	git -C "$_eb" $SW_EVAL_IDENT commit -q -m "Initial import" || return 1
	git -C "$_eb" checkout -q -b review || return 1
	git -C "$_eb" apply "$SOFTWARY_HOME/eval/cases/$2/diff.patch" || return 1
	git -C "$_eb" add -A || return 1
	# shellcheck disable=SC2086
	git -C "$_eb" $SW_EVAL_IDENT commit -q -m "Implement slice S1" || return 1
}

# sw_eval_prepare DIR
sw_eval_prepare() {
	[ $# -eq 1 ] || { sw_eval_usage; return 2; }
	if [ ! -d "$SOFTWARY_HOME/eval/sample" ] || [ -z "$(sw_eval_cases)" ]; then
		printf 'eval prepare: this installation has no evaluation files (rerun install.sh)\n'
		return 2
	fi
	if [ -e "$1" ] && { [ ! -d "$1" ] || [ -n "$(ls -A "$1")" ]; }; then
		printf 'eval prepare: %s is not an empty directory\n' "$1"
		return 2
	fi
	mkdir -p "$1" || return 2
	_ep_dir=$(cd "$1" && pwd -P) || return 2
	_ep_map=
	_ep_n=0
	for _ep_name in $(sw_eval_cases); do
		_ep_n=$((_ep_n + 1))
		_ep_id=$(printf 'case-%02d' "$_ep_n")
		if ! sw_eval_build "$_ep_dir/$_ep_id" "$_ep_name"; then
			printf 'eval prepare: could not build %s\n' "$_ep_id"
			return 2
		fi
		_ep_map="${_ep_map}$_ep_id $_ep_name
"
	done
	mkdir -p "$SOFTWARY_ROOT/$SW_EVAL_REL" || return 2
	printf '%s' "$_ep_map" >"$SOFTWARY_ROOT/$SW_EVAL_REL/map"
	printf '%s\n' "$_ep_dir" >"$SOFTWARY_ROOT/$SW_EVAL_REL/dir"
	printf 'eval prepare: %s cases in %s\n' "$_ep_n" "$_ep_dir"
	printf 'Review each case in a clean context, in its own directory only:\n'
	printf '  base main, slice %s (specs/002-tip/slices/S1.md); the review record is %s\n' "S1" "$SW_EVAL_RECORD"
	printf '%s' "$_ep_map" | while read -r _ep_id _ep_name; do
		printf '  %s/%s\n' "$_ep_dir" "$_ep_id"
	done
}

# sw_eval_model: the reviewer's model in models.conf (nothing when unknown).
sw_eval_model() {
	sw_models_load >/dev/null 2>&1 || :
	sw_kv_get SW_MODELS reviewer 2>/dev/null || :
}

# sw_eval_digest: the digest of the reviewer: its agent file, the project's
# own version of it, if any, and its model (the method of the approvals).
sw_eval_digest() {
	{
		for _ed in .softwary/agents/reviewer.md .softwary/local/agents/reviewer.md; do
			[ -f "$SOFTWARY_ROOT/$_ed" ] || continue
			printf '%s %s\n' "$(git -C "$SOFTWARY_ROOT" hash-object -- "$_ed")" "$_ed"
		done
		printf 'model %s\n' "$(sw_eval_model)"
	} | git -C "$SOFTWARY_ROOT" hash-object --stdin
}

# sw_eval_score DIR
sw_eval_score() {
	[ $# -eq 1 ] || { sw_eval_usage; return 2; }
	_es_map=$SOFTWARY_ROOT/$SW_EVAL_REL/map
	if [ ! -f "$_es_map" ] || [ ! -f "$SOFTWARY_ROOT/$SW_EVAL_REL/dir" ]; then
		printf 'eval score: nothing is prepared (run ./softwary eval prepare <dir>)\n'
		return 2
	fi
	_es_dir=$(cd "$1" 2>/dev/null && pwd -P) || { printf 'eval score: %s is not a directory\n' "$1"; return 2; }
	if [ "$_es_dir" != "$(cat "$SOFTWARY_ROOT/$SW_EVAL_REL/dir")" ]; then
		printf 'eval score: %s is not the prepared directory (%s)\n' "$1" "$(cat "$SOFTWARY_ROOT/$SW_EVAL_REL/dir")"
		return 2
	fi
	_es_problems=
	_es_rows=
	_es_caught=0 _es_broken=0 _es_false=0 _es_clean=0
	while read -r _es_id _es_name; do
		[ -n "$_es_id" ] || continue
		_es_c=$_es_dir/$_es_id
		_es_pkg=$SOFTWARY_HOME/eval/cases/$_es_name
		_es_expect=$(cat "$_es_pkg/expect" 2>/dev/null) || _es_expect=
		_es_kind=$(cat "$_es_pkg/kind" 2>/dev/null) || _es_kind=
		case $_es_expect in
		approve | changes) ;;
		*)
			_es_problems="${_es_problems}$_es_id: the case is not in this installation (rerun eval prepare)
"
			continue
			;;
		esac
		if [ ! -f "$_es_c/$SW_EVAL_RECORD" ]; then
			_es_problems="${_es_problems}$_es_id: no review record ($SW_EVAL_RECORD)
"
			continue
		fi
		sw_fm_read "$_es_c/$SW_EVAL_RECORD"
		_es_dec=$(sw_fm_get decision)
		if [ -n "$(sw_fm_errors)" ] || [ "$(sw_fm_get slice)" != S1 ] || ! sw_in_list "$_es_dec" "$SW_REVIEW_DECISIONS"; then
			_es_problems="${_es_problems}$_es_id: the review record is invalid (slice: S1, decision: approve or changes)
"
			continue
		fi
		# the case's own softwary decides what guard catches
		_es_grc=0
		_es_g=$(cd "$_es_c" && git checkout -q review && ./softwary guard "$SW_EVAL_JOB" --base main 2>&1) || _es_grc=$?
		if [ "$_es_grc" -gt 1 ]; then
			_es_problems="${_es_problems}$_es_id: guard could not run: $(printf '%s\n' "$_es_g" | head -n 1)
"
			continue
		fi
		_es_gtxt=pass
		[ "$_es_grc" -eq 0 ] || _es_gtxt=violation
		if [ "$_es_expect" = changes ]; then
			_es_broken=$((_es_broken + 1))
			if [ "$_es_grc" -eq 1 ] || [ "$_es_dec" = changes ]; then
				_es_caught=$((_es_caught + 1))
				_es_res=caught
			else
				_es_res=missed
			fi
		else
			_es_clean=$((_es_clean + 1))
			_es_res=ok
			if [ "$_es_dec" = changes ]; then
				_es_false=$((_es_false + 1))
				_es_res="false alarm"
			fi
		fi
		_es_rows="${_es_rows}$(printf '%-8s %-6s guard %-9s review %-8s %s' "$_es_id" "$_es_kind" "$_es_gtxt" "$_es_dec" "$_es_res")
"
	done <"$_es_map"
	if [ -n "$_es_problems" ]; then
		printf '%s' "$_es_problems"
		printf 'eval score: nothing was written; every case needs a valid review record\n'
		return 1
	fi
	printf '%s' "$_es_rows"
	_es_conf=$SOFTWARY_ROOT/$SW_EVAL_CONF_REL
	{
		printf '# softwary evaluation of the reviewer. Written only by ./softwary eval score.\n'
		printf 'caught = %s\n' "$_es_caught"
		printf 'broken = %s\n' "$_es_broken"
		printf 'false_alarms = %s\n' "$_es_false"
		printf 'clean = %s\n' "$_es_clean"
		printf 'digest = %s\n' "$(sw_eval_digest)"
		printf 'date = %s\n' "$(date -u +%Y-%m-%d)"
	} >"$_es_conf.tmp" && mv "$_es_conf.tmp" "$_es_conf" || return 2
	printf 'eval score: caught %s of %s broken, %s false alarm(s) in %s clean (%s)\n' "$_es_caught" "$_es_broken" "$_es_false" "$_es_clean" "$SW_EVAL_CONF_REL"
}

# sw_eval prepare <dir> | score <dir>
sw_eval() {
	case ${1:-} in
	prepare | score)
		_ev_cmd=$1
		shift
		"sw_eval_$_ev_cmd" "$@"
		;;
	*)
		sw_eval_usage
		return 2
		;;
	esac
}
