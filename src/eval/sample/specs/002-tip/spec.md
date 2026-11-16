---
id: 002
title: Tip
status: approved
risk: R1
model: splitter
contracts:
---

# Tip

A tip in whole percent is added to the bill before it is split.

## Acceptance criteria

- **AC-002-01:** A tip of P percent is added to the total, rounded to the nearest cent, halves rounding up. Covers EX-F2-01.
- **AC-002-02:** A tip that is not a whole number from 0 to 100 is refused with status 2. Covers EX-F2-02.
- **AC-002-03:** A bill split with a tip has shares that add up to the total with the tip. Covers EX-F2-01.

## Open questions
