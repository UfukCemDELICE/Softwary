#!/bin/sh
# A new order is created; the same id again is refused.
. "$(dirname "$0")/../app/order.sh"
ORDER_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$ORDER_DIR"' EXIT
order_create 7 || exit 1
[ "$(order_state 7)" = created ] || exit 1
! order_create 7 || exit 1
