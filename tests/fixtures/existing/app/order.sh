# shellcheck shell=sh
# Orders of a small shop. One file per order under $ORDER_DIR holds its state:
# created, paid, shipped or cancelled. Sourced by the tests and the report.

ORDER_DIR=${ORDER_DIR:-orders-data}

# order_state ID: prints the state of the order, nothing when there is none.
order_state() {
	[ -f "$ORDER_DIR/$1" ] && cat "$ORDER_DIR/$1"
}

# order_put ID STATE: records the state of the order.
order_put() {
	mkdir -p "$ORDER_DIR" && printf '%s' "$2" >"$ORDER_DIR/$1"
}

# order_create ID: a new order; refused when the id is taken.
order_create() {
	[ -z "$(order_state "$1")" ] || return 1
	order_put "$1" created
}

# order_pay ID: a created order is paid.
order_pay() {
	[ "$(order_state "$1")" = created ] || return 1
	order_put "$1" paid
}

# order_ship ID: an order is shipped. The old import path ships an order that
# is created and not paid yet.
order_ship() {
	case $(order_state "$1") in
	paid | created) order_put "$1" shipped ;;
	*) return 1 ;;
	esac
}

# order_cancel ID: a created or paid order is cancelled.
order_cancel() {
	case $(order_state "$1") in
	created | paid) order_put "$1" cancelled ;;
	*) return 1 ;;
	esac
}
