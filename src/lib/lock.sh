# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: the state root and the locks. Sourced by bin/softwary. POSIX sh.
#
# State (jobs, the run, the event log, the merge queue, locks, logs) lives in
# the main checkout's .softwary/state/, whichever worktree a command runs
# from: SW_STATE_ROOT is that checkout. SOFTWARY_ROOT stays the tree a command
# checks (verify, guard, trace, ...).
#
# A lock is a directory made with mkdir under .softwary/state/locks/. Its
# `owner` file says who holds it: `pid=<n> host=<name> time=<epoch>`. There are
# two locks: `state` (short critical sections that write state files) and
# `merge` (the drainer of the merge queue). A lock whose owner is dead on this
# machine, or that never got an owner for SW_LOCK_STALE_SECONDS, is broken by
# the next process that wants it; a lock of another machine is never broken.

SW_STATE_REL=.softwary/state
SW_LOCKS_REL=.softwary/state/locks
SW_LOCK_STALE_SECONDS=60

# sw_state_root: prints the main checkout when SOFTWARY_ROOT is a linked
# worktree (its git directory is not the common one), else SOFTWARY_ROOT.
sw_state_root() {
	_sr_gd=$(git -C "$SOFTWARY_ROOT" rev-parse --git-dir 2>/dev/null) || { printf '%s\n' "$SOFTWARY_ROOT"; return 0; }
	_sr_cd=$(git -C "$SOFTWARY_ROOT" rev-parse --git-common-dir 2>/dev/null) || { printf '%s\n' "$SOFTWARY_ROOT"; return 0; }
	_sr_gd=$(cd "$SOFTWARY_ROOT" && cd "$_sr_gd" 2>/dev/null && pwd -P) || { printf '%s\n' "$SOFTWARY_ROOT"; return 0; }
	_sr_cd=$(cd "$SOFTWARY_ROOT" && cd "$_sr_cd" 2>/dev/null && pwd -P) || { printf '%s\n' "$SOFTWARY_ROOT"; return 0; }
	if [ "$_sr_gd" = "$_sr_cd" ] || [ "${_sr_cd##*/}" != .git ]; then
		printf '%s\n' "$SOFTWARY_ROOT"
		return 0
	fi
	printf '%s\n' "${_sr_cd%/*}"
}

sw_host() {
	uname -n 2>/dev/null || printf 'unknown'
}

sw_lock_dir() {
	printf '%s/%s/%s' "$SW_STATE_ROOT" "$SW_LOCKS_REL" "$1"
}

# sw_lock_held NAME: true while this process holds the lock (a variable of
# this shell, never exported: a child process is another process).
sw_lock_held() {
	eval "[ \"\${SW_HOLD_$1:-0}\" -eq 1 ]"
}

sw_lock_mark() {
	eval "SW_HOLD_$1=$2"
}

# sw_lock_field OWNER KEY: the value of KEY in an owner line.
sw_lock_field() {
	for _lf in $1; do
		case $_lf in "$2="*) printf '%s' "${_lf#*=}"; return 0 ;; esac
	done
	return 0
}

# sw_lock_mtime PATH: the modification time of PATH in epoch seconds.
sw_lock_mtime() {
	if stat -c %Y / >/dev/null 2>&1; then
		stat -c %Y "$1" 2>/dev/null
	else
		stat -f %m "$1" 2>/dev/null
	fi
}

sw_lock_write_owner() {
	printf 'pid=%s host=%s time=%s\n' "$$" "$(sw_host)" "$(date +%s)" >"$1/owner.$$" && mv -f "$1/owner.$$" "$1/owner"
}

# sw_lock_probe NAME: sets SW_LOCK_OWNER (the owner line) and SW_LOCK_STATUS:
# free, live (owner alive here), dead (owner gone), foreign (another
# machine), young (no owner yet) or orphan (no owner for too long).
sw_lock_probe() {
	_lp_d=$(sw_lock_dir "$1")
	SW_LOCK_OWNER=
	if [ ! -d "$_lp_d" ]; then
		SW_LOCK_STATUS=free
		return 0
	fi
	SW_LOCK_OWNER=$(cat "$_lp_d/owner" 2>/dev/null) || SW_LOCK_OWNER=
	if [ -z "$SW_LOCK_OWNER" ]; then
		_lp_m=$(sw_lock_mtime "$_lp_d")
		SW_LOCK_STATUS=young
		case $_lp_m in '' | *[!0-9]*) return 0 ;; esac
		if [ $(($(date +%s) - _lp_m)) -gt "$SW_LOCK_STALE_SECONDS" ]; then
			SW_LOCK_STATUS=orphan
		fi
		return 0
	fi
	_lp_pid=$(sw_lock_field "$SW_LOCK_OWNER" pid)
	if [ "$(sw_lock_field "$SW_LOCK_OWNER" host)" != "$(sw_host)" ]; then
		SW_LOCK_STATUS=foreign
	elif [ -n "$_lp_pid" ] && kill -0 "$_lp_pid" 2>/dev/null; then
		SW_LOCK_STATUS=live
	else
		SW_LOCK_STATUS=dead
	fi
}

# sw_lock_stale NAME: true when the lock is absent or its owner is gone.
sw_lock_stale() {
	sw_lock_probe "$1"
	case $SW_LOCK_STATUS in free | dead | orphan) return 0 ;; esac
	return 1
}

# sw_lock_describe NAME: one line that says who holds the lock (after a probe).
sw_lock_describe() {
	if [ -z "$SW_LOCK_OWNER" ]; then
		printf '%s is locked (no owner recorded yet)' "$1"
		return 0
	fi
	_ld_t=$(sw_lock_field "$SW_LOCK_OWNER" time)
	printf '%s is locked by pid %s on %s since %s' "$1" "$(sw_lock_field "$SW_LOCK_OWNER" pid)" \
		"$(sw_lock_field "$SW_LOCK_OWNER" host)" "$(sw_run_time "$_ld_t")"
	[ "$SW_LOCK_STATUS" != foreign ] || printf ' (another machine: not broken)'
}

# sw_lock_break NAME OWNER: removes the lock that was judged stale; true when
# this process removed it. Breakers take turns on `<name>.breaking` (a
# directory too), and judge again once they have it: the owner is the one that
# was seen and is still gone, and nobody but a breaker can remove the lock of a
# dead owner, so what is removed is the lock that was judged. A `.breaking`
# directory that a dead breaker left is removed after SW_LOCK_STALE_SECONDS.
sw_lock_break() {
	_lb_d=$(sw_lock_dir "$1")
	if ! mkdir "$_lb_d.breaking" 2>/dev/null; then
		_lb_m=$(sw_lock_mtime "$_lb_d.breaking")
		case $_lb_m in '' | *[!0-9]*) return 1 ;; esac
		if [ $(($(date +%s) - _lb_m)) -gt "$SW_LOCK_STALE_SECONDS" ]; then
			rmdir "$_lb_d.breaking" 2>/dev/null
		fi
		return 1
	fi
	_lb_rc=1
	sw_lock_probe "$1"
	case $SW_LOCK_STATUS in
	dead | orphan)
		if [ "$SW_LOCK_OWNER" = "$2" ]; then
			rm -rf "$_lb_d"
			_lb_rc=0
		fi
		;;
	esac
	rmdir "$_lb_d.breaking" 2>/dev/null
	return "$_lb_rc"
}

# sw_lock_try NAME: takes the lock at once if it is free or stale (a stale
# one is broken first and `lock_broken` is logged). 0 taken, 1 held by
# another process, 2 the lock directory cannot be made.
sw_lock_try() {
	_lt_n=$1
	_lt_d=$(sw_lock_dir "$_lt_n")
	mkdir -p "$SW_STATE_ROOT/$SW_LOCKS_REL" || return 2
	_lt_broken=
	_lt_i=0
	while [ "$_lt_i" -lt 5 ]; do
		_lt_i=$((_lt_i + 1))
		if mkdir "$_lt_d" 2>/dev/null; then
			sw_lock_write_owner "$_lt_d" || { rm -rf "$_lt_d"; return 2; }
			sw_lock_mark "$_lt_n" 1
			[ -z "$_lt_broken" ] || sw_event - lock_broken - - "$_lt_broken" || :
			return 0
		fi
		sw_lock_probe "$_lt_n"
		case $SW_LOCK_STATUS in
		free) ;;
		dead | orphan)
			_lt_o=$SW_LOCK_OWNER
			if sw_lock_break "$_lt_n" "$_lt_o"; then
				_lt_broken="$_lt_n (was: ${_lt_o:-no owner})"
			fi
			;;
		*) return 1 ;;
		esac
	done
	return 1
}

sw_lock_sleep() {
	if [ -z "${SW_SLEEP_STEP:-}" ]; then
		SW_SLEEP_STEP=1
		sleep 0.1 2>/dev/null && SW_SLEEP_STEP=0.1
		return 0
	fi
	sleep "$SW_SLEEP_STEP"
}

# sw_lock_acquire NAME TIMEOUT: waits up to TIMEOUT seconds for the lock. 2
# (with the owner named) when it cannot be had.
sw_lock_acquire() {
	_la_end=$(($(date +%s) + $2))
	while :; do
		_la_rc=0
		sw_lock_try "$1" || _la_rc=$?
		[ "$_la_rc" -ne 0 ] || return 0
		[ "$_la_rc" -eq 1 ] || return 2
		if [ "$(date +%s)" -ge "$_la_end" ]; then
			sw_lock_probe "$1"
			printf '%s\n' "$(sw_lock_describe "$1")"
			return 2
		fi
		sw_lock_sleep
	done
}

# sw_lock_release NAME: removes the lock when this process owns it.
sw_lock_release() {
	sw_lock_mark "$1" 0
	_lr_d=$(sw_lock_dir "$1")
	_lr_o=$(cat "$_lr_d/owner" 2>/dev/null) || _lr_o=
	[ "$(sw_lock_field "$_lr_o" pid)" = "$$" ] || return 0
	[ "$(sw_lock_field "$_lr_o" host)" = "$(sw_host)" ] || return 0
	rm -rf "$_lr_d"
}

# sw_lock_release_all: releases every lock this process owns (the exit trap).
sw_lock_release_all() {
	[ -n "${SW_STATE_ROOT:-}" ] || return 0
	for _ra in "$SW_STATE_ROOT/$SW_LOCKS_REL"/*; do
		[ -d "$_ra" ] || continue
		case ${_ra##*/} in *.breaking) continue ;; esac
		sw_lock_release "${_ra##*/}"
	done
}

sw_lock_install_traps() {
	trap 'sw_lock_release_all' EXIT
	trap 'exit 129' HUP
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

# sw_lock_sweep: breaks every lock whose owner is gone (run start).
sw_lock_sweep() {
	for _sw in "$SW_STATE_ROOT/$SW_LOCKS_REL"/*; do
		[ -d "$_sw" ] || continue
		_sw=${_sw##*/}
		case $_sw in *.breaking) continue ;; esac
		sw_lock_probe "$_sw"
		case $SW_LOCK_STATUS in
		dead | orphan)
			if sw_lock_break "$_sw" "$SW_LOCK_OWNER"; then
				sw_event - lock_broken - - "$_sw (was: ${SW_LOCK_OWNER:-no owner})" || :
			fi
			;;
		esac
	done
}

# sw_state_locked COMMAND [ARGS]: runs COMMAND (a function) holding the state
# lock and returns its status; 2 when the lock cannot be had. It can be
# entered again from inside: the outermost call releases.
sw_state_locked() {
	if sw_lock_held state; then
		"$@"
		return $?
	fi
	sw_lock_acquire state "${SW_LOCK_TIMEOUT:-30}" || return 2
	"$@"
	_sl_rc=$?
	sw_lock_release state
	return "$_sl_rc"
}
