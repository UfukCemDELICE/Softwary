# Shop orders

## Problem

A small shop keeps its orders in files and wants to know that an order moves
from placed to paid to shipped, and that nothing ships without being paid.

## Users

The shop's clerk.

## Scope

- Place, pay, ship and cancel an order.
- Count the orders in each state.

## Out of scope

- Refunds, returns and partial shipments.

## Features

### F1: Place an order

The clerk places an order with an id.

- **EX-F1-01:** Given no order with that id, when the clerk places it, then the order is created.
- **EX-F1-02:** Given an order with that id, when the clerk places it again, then it is refused.

### F2: Pay an order

The clerk records the payment of an order.

- **EX-F2-01:** Given a created order, when the clerk pays it, then it is paid.
- **EX-F2-02:** Given an order that is not created, when the clerk pays it, then it is refused.

### F3: Ship an order

The clerk ships an order. (Today's behaviour.)

- **EX-F3-01:** Given a paid order, when the clerk ships it, then it is shipped.
- **EX-F3-02:** Given a created order that is not paid, when the clerk ships it, then it is shipped: the old import path never asked for payment. The shop wants this changed (F5).

### F4: Cancel an order

The clerk cancels an order that has not left the shop.

- **EX-F4-01:** Given a created or a paid order, when the clerk cancels it, then it is cancelled.
- **EX-F4-02:** Given a shipped order, when the clerk cancels it, then it is refused.

### F5: Ship only paid orders

New request: an order that is not paid is not shipped.

- **EX-F5-01:** Given a created order that is not paid, when the clerk ships it, then it is refused and the order stays as it was.

## Non-functional requirements

- Every command answers in under a second for 1000 orders.

## Constraints

- Plain `sh`, files only: no server and no database.

## Success metrics

- No order leaves the shop unpaid.

## Open questions

None.
