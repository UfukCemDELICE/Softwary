#!/bin/sh
# The report lists the states in alphabetical order. (It does not: the report
# has never sorted them, and nobody has fixed this test or the report.)
. "$(dirname "$0")/../app/report.sh"
ORDER_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$ORDER_DIR"' EXIT
order_create 1 && order_create 2 && order_pay 2 || exit 1
first=$(order_report | sed -n 1p)
[ "$first" = "cancelled 0" ] || exit 1
