# Tabsplit

## Problem

Friends who share a bill argue about who pays how many cents.

## Users

People who share a restaurant bill.

## Scope

- Split a bill into shares that add up to the total.
- Add a tip before splitting.

## Out of scope

- Taxes.
- Currencies other than the one the amounts are written in.

## Features

### F1: Split a bill

A bill in cents is divided among a number of people.

- **EX-F1-01:** Given a bill of 100 cents and 3 people, when it is split, then the shares are 34, 33 and 33.
- **EX-F1-02:** Given a bill and 0 people, when it is split, then the split is refused.

### F2: Add a tip

A tip in whole percent is added to the bill.

- **EX-F2-01:** Given a bill of 1010 cents and a 15 percent tip, when the tip is added, then the total is 1162.
- **EX-F2-02:** Given a tip of 101 percent, when it is added, then it is refused.

## Non-functional requirements

- Amounts are whole cents; no rounding drift.

## Constraints

- Plain POSIX shell, no dependencies.

## Success metrics

- Every bill splits to the cent.

## Open questions

None.
