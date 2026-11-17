#!/bin/sh
# A created order is paid; a paid one is not paid twice.
. "$(dirname "$0")/../app/order.sh"
ORDER_DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$ORDER_DIR"' EXIT
order_create 7 && order_pay 7 || exit 1
[ "$(order_state 7)" = paid ] || exit 1
! order_pay 7 || exit 1
