# shellcheck shell=sh
# Writing amounts.

# format_cents CENTS: prints CENTS as units and cents, 1234 as 12.34.
format_cents() {
	_fc_cents=$1
	printf '%s.%02d\n' "$((_fc_cents / 100))" "$((_fc_cents % 100))"
}
