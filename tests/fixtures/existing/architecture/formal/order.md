# Order

TLA+ record of the order's state machine (`architecture/states/order.json`), as
`app/order.sh` behaves today.

## Invariants

| Name | Statement | Harm |
| --- | --- | --- |
| `ShippedWasPaid` | An order that is shipped has been paid for. | Goods leave the shop and nobody pays for them. |
| `CancelledNeverShipped` | An order that was shipped is never cancelled afterwards. | A customer is refunded for goods that have already left. |

## Actions

| Action | Statement |
| --- | --- |
| `Init` | A new order is created and has not been paid. |
| `pay` | The clerk records the payment of a created order. |
| `ship` | An order is shipped. |
| `cancel` | A created or paid order is cancelled. |

## Coverage

| Path | Functions |
| --- | --- |
| app/order.sh | order_create, order_pay, order_ship, order_cancel |

## Bounds and assumptions

- One order at a time; a payment is all or nothing.
- Refunds, returns and partial shipments are not modelled.
- The model is the code as it is: `order_ship` ships a created order too.

## Last verified

never

## Variants

| File | Breaks |
| --- | --- |
| `order-shipunpaid.cfg` | `ShippedWasPaid` |
| `order-shipcancelled.cfg` | `CancelledNeverShipped` |

## Findings

| Invariant | Until | Reason |
| --- | --- | --- |
| `ShippedWasPaid` | 2999-12-31 | The old import path ships a created order that is not paid; feature F5 removes it. |
