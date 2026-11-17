# Order

TLA+ record of the order's state machine (`architecture/states/order.json`).

## Invariants

| Name | Statement | Harm |
| --- | --- | --- |
| `ShippedWasPaid` | An order that is shipped has been paid for. | Goods leave the warehouse and nobody pays for them. |
| `CancelledNeverShipped` | An order that was shipped is never cancelled afterwards. | A customer is refunded for goods that have already left. |

## Actions

| Action | Statement |
| --- | --- |
| `Init` | A new order is created and has not been paid. |
| `pay` | The customer pays for a created order. |
| `ship` | A paid order is shipped. |
| `cancel` | A created or paid order is cancelled. |

## Coverage

| Path | Functions |
| --- | --- |
| planned | - |

## Bounds and assumptions

- One order at a time; a payment is all or nothing.
- Refunds, returns and partial shipments are not modelled.

## Last verified

never

## Variants

| File | Breaks |
| --- | --- |
| `order-shipunpaid.cfg` | `ShippedWasPaid` |
| `order-shipcancelled.cfg` | `CancelledNeverShipped` |
