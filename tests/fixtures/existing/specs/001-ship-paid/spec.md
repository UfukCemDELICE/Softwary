---
id: 001
title: Ship only paid orders
status: draft
risk: R1
model: orders
contracts:
---

# Ship only paid orders

An order that is not paid is not shipped.

## Scope

`order_ship` in `app/order.sh`.

## Acceptance criteria

- **AC-001-01:** Shipping an order that is created and not paid is refused and the order stays as it was. Covers EX-F5-01.
- **AC-001-02:** Shipping a paid order still ships it. Covers EX-F3-01.

## Open questions
