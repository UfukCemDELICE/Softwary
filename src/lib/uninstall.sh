# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_UN_* globals are read by the final step
# softwary: `uninstall` command. Sourced by bin/softwary. POSIX sh.
#
# Removes the package from the project and nothing of the project's: the
# managed files (.softwary/bin, lib, rules, targets, skills, agents, hooks,
# templates, eval, VERSION and .gitignore), the wrapper, the files and blocks
# that `sync` generated (the ones .softwary/generated lists and that nobody
# changed since: their cksum is the recorded one) and core.hooksPath when it
# points at the package's hooks. .softwary/config, local and state, product/,
# architecture/, specs/, CONTEXT.md and the project's own files stay.
#
# Without --yes it lists what it would remove and writes nothing. It stops
# (1) while a run is open or a job is not finished. The managed files go last,
# in a process of its own (`exec sh -c`), because they include this code.
# Exit: 0, 1 (a run or a job), 2 (usage).

SW_UN_TREES="bin lib rules targets skills agents hooks templates eval"
SW_UN_HOOKS=.softwary/hooks

# sw_un_usage
sw_un_usage() {
	printf 'usage: ./softwary uninstall [--yes]\n' >&2
}

# sw_un_open: prints why a run or a job stops the uninstall; true when it does.
sw_un_open() {
	if sw_run_open; then
		printf 'uninstall: a run is open (./softwary run stop)\n'
		return 0
	fi
	for _un_j in "$SW_STATE_ROOT/$SW_JOBS_REL"/*/job; do
		[ -f "$_un_j" ] || continue
		_un_s=$(sw_kvf_get "$_un_j" state)
		sw_job_terminal "$_un_s" && continue
		_un_j=${_un_j%/job}
		printf 'uninstall: job %s is %s; finish or abandon it first\n' "${_un_j##*/}" "$_un_s"
		return 0
	done
	return 1
}

# sw_un_safe PATH: true for a path the manifest may name: relative, inside the
# project, not git's and not the project's configuration, local files or state.
sw_un_safe() {
	case /$1/ in
	//* | */../* | /./* | */./*) return 1 ;;
	esac
	case $1 in
	.git | .git/* | .softwary/config/* | .softwary/local/* | .softwary/state/*) return 1 ;;
	esac
	return 0
}

# sw_un_block_leaves FILE: true when FILE has something besides its softwary block.
sw_un_block_leaves() {
	awk '/^<!-- softwary:begin/ { skip = 1; next }
		skip && /^<!-- softwary:end -->$/ { skip = 0; next }
		!skip && /[^[:space:]]/ { found = 1 }
		END { exit !found }' "$1"
}

# sw_un_plan: fills $SW_WORK/generated (lines "file PATH", "block PATH LEAVES"
# or "keep LABEL REASON"), $SW_WORK/managed (paths, one per line) and
# $SW_WORK/notes (what is kept for another reason).
sw_un_plan() {
	: >"$SW_WORK/generated"
	: >"$SW_WORK/managed"
	: >"$SW_WORK/notes"
	if [ ! -f "$SOFTWARY_ROOT/$SW_MANIFEST_REL" ]; then
		printf 'kept the generated files: %s is missing, so none can be told from the project'"'"'s own\n' "$SW_MANIFEST_REL" >>"$SW_WORK/notes"
	else
		while read -r _un_k _un_ck _un_sz _un_p; do
			case $_un_k in file | block) ;; *) continue ;; esac
			if ! sw_un_safe "$_un_p"; then
				printf 'keep %s (not a path softwary may remove)\n' "$_un_p" >>"$SW_WORK/generated"
				continue
			fi
			_un_d=$SOFTWARY_ROOT/$_un_p
			if [ "$_un_k" = file ]; then
				[ -f "$_un_d" ] || continue
				if [ "$(sw_cksum "$_un_d")" = "$_un_ck $_un_sz" ]; then
					printf 'file %s\n' "$_un_p" >>"$SW_WORK/generated"
				else
					printf 'keep %s (changed by hand)\n' "$_un_p" >>"$SW_WORK/generated"
				fi
				continue
			fi
			_un_rc=0
			sw_block_extract "$_un_d" "$SW_WORK/block" || _un_rc=$?
			case $_un_rc in
			1) continue ;;
			2)
				printf 'keep %s (block) (the markers are broken)\n' "$_un_p" >>"$SW_WORK/generated"
				continue
				;;
			esac
			if [ "$(sw_cksum "$SW_WORK/block")" != "$_un_ck $_un_sz" ]; then
				printf 'keep %s (block) (changed by hand)\n' "$_un_p" >>"$SW_WORK/generated"
			elif sw_un_block_leaves "$_un_d"; then
				printf 'block %s leaves\n' "$_un_p" >>"$SW_WORK/generated"
			else
				printf 'block %s alone\n' "$_un_p" >>"$SW_WORK/generated"
			fi
		done <"$SOFTWARY_ROOT/$SW_MANIFEST_REL"
	fi
	for _un_t in $SW_UN_TREES; do
		[ -d "$SOFTWARY_ROOT/.softwary/$_un_t" ] || continue
		(cd "$SOFTWARY_ROOT" && find ".softwary/$_un_t" \( -type f -o -type l \)) | sort >>"$SW_WORK/managed"
	done
	for _un_f in .softwary/VERSION .softwary/.gitignore; do
		[ -f "$SOFTWARY_ROOT/$_un_f" ] && printf '%s\n' "$_un_f" >>"$SW_WORK/managed"
	done
	# The manifest goes when everything it lists went; while a generated file
	# is kept it stays, so that a later sync still knows that file.
	if [ -f "$SOFTWARY_ROOT/$SW_MANIFEST_REL" ] && ! grep -q '^keep ' "$SW_WORK/generated"; then
		printf '%s\n' "$SW_MANIFEST_REL" >>"$SW_WORK/managed"
	fi
	return 0
}

# sw_un_wrapper: true when the root `softwary` is the package's wrapper.
sw_un_wrapper() {
	[ -f "$SOFTWARY_ROOT/softwary" ] && head -n 2 "$SOFTWARY_ROOT/softwary" | grep -Fq '# softwary wrapper. Managed by softwary'
}

# sw_uninstall [--yes]
sw_uninstall() {
	_un_yes=0
	for _un_a in "$@"; do
		case $_un_a in
		--yes) _un_yes=1 ;;
		*)
			sw_un_usage
			return 2
			;;
		esac
	done
	_un_why=$(sw_un_open) && {
		printf '%s\n' "$_un_why"
		return 1
	}
	SW_WORK=$(mktemp -d "${TMPDIR:-/tmp}/softwary-uninstall.XXXXXX") || return 2
	trap 'sw_lock_release_all; rm -rf "${SW_WORK:?}"' EXIT
	sw_un_plan

	_un_hp=
	[ "$(git -C "$SOFTWARY_ROOT" config --get core.hooksPath 2>/dev/null)" != "$SW_UN_HOOKS" ] || _un_hp=$SW_UN_HOOKS
	if [ "$_un_yes" -eq 0 ]; then
		printf 'uninstall: these would be removed (nothing was written; run ./softwary uninstall --yes to remove them)\n'
		_un_verb='  remove'
	else
		_un_verb=removed
	fi
	# 1. what sync generated
	while read -r _un_w _un_p _un_x; do
		case $_un_w in
		keep) printf 'kept %s %s\n' "$_un_p" "$_un_x" ;;
		file)
			if [ "$_un_yes" -eq 1 ]; then
				rm -f "${SOFTWARY_ROOT:?}/$_un_p" || return 1
				sw_prune "$(dirname "$_un_p")"
			fi
			printf '%s %s\n' "$_un_verb" "$_un_p"
			;;
		block)
			if [ "$_un_x" = alone ]; then _un_l="$_un_p (block; nothing else was in the file)"; else _un_l="$_un_p (block)"; fi
			if [ "$_un_yes" -eq 1 ]; then
				sw_block_remove "$SOFTWARY_ROOT/$_un_p" || return 1
			fi
			printf '%s %s\n' "$_un_verb" "$_un_l"
			;;
		esac
	done <"$SW_WORK/generated"
	cat "$SW_WORK/notes"
	# 2. core.hooksPath
	if [ -n "$_un_hp" ]; then
		[ "$_un_yes" -eq 0 ] || git -C "$SOFTWARY_ROOT" config --unset core.hooksPath || return 1
		printf '%s core.hooksPath (%s)\n' "$_un_verb" "$_un_hp"
	fi
	# 3. the managed files and the wrapper, last
	_un_wrap=0
	if [ -e "$SOFTWARY_ROOT/softwary" ] || [ -L "$SOFTWARY_ROOT/softwary" ]; then
		if sw_un_wrapper; then
			_un_wrap=1
		else
			printf "kept softwary (not softwary's wrapper)\n"
		fi
	fi
	if [ "$_un_yes" -eq 0 ]; then
		sed 's/^/  remove /' "$SW_WORK/managed"
		[ "$_un_wrap" -eq 0 ] || printf '  remove softwary\n'
		return 0
	fi
	cp "$SW_WORK/managed" "$SW_WORK/all"
	[ "$_un_wrap" -eq 0 ] || printf 'softwary\n' >>"$SW_WORK/all"
	# The managed files include the code that is running: they are removed by a
	# process that has none of it open, which also removes the work directory.
	trap - EXIT
	sw_lock_release_all
	exec sh -c '
		work=$1
		root=$2
		trees=$3
		rc=0
		while IFS= read -r f; do
			if rm -f "$root/$f"; then printf "removed %s\n" "$f"; else rc=1; printf "uninstall: could not remove %s\n" "$f"; fi
		done <"$work/all"
		for t in $trees; do
			[ -d "$root/.softwary/$t" ] && find "$root/.softwary/$t" -depth -type d -exec rmdir {} \; 2>/dev/null
		done
		rm -rf "${work:?}"
		[ "$rc" -eq 0 ] && printf "uninstall: done; the project'"'"'s own files, .softwary/config, local and state were left\n"
		exit "$rc"
	' softwary-uninstall "$SW_WORK" "$SOFTWARY_ROOT" "$SW_UN_TREES"
}
