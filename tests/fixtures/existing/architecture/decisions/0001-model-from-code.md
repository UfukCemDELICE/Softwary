---
id: 0001
title: The model, drawn from the code
status: proposed
affects: architecture/model/system.calm.json
---

# 0001: The model, drawn from the code

The model describes the shop's order scripts as they are today. Each component
is drawn from these paths:

- `orders`: `app/order.sh` (the order's states) and `app/report.sh` (the
  count of orders by state).

The order's state machine and its TLA+ record are drawn from `app/order.sh`.
The code ships an order that is created and not paid: that is the finding of
`architecture/formal/order.md`.
