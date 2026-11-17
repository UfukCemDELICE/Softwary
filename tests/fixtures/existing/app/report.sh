# shellcheck shell=sh
# How many orders are in each state, one line each: "<state> <n>".
# XXX the lines come in a fixed order, not sorted by state
. "$(dirname "$0")/order.sh"

order_report() {
	for state in created paid shipped cancelled; do
		n=0
		for f in "$ORDER_DIR"/*; do
			[ -f "$f" ] || continue
			[ "$(cat "$f")" = "$state" ] && n=$((n + 1))
		done
		printf '%s %s\n' "$state" "$n"
	done
}
