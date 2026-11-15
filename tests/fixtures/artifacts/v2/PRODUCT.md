# Taskly

## Problem

Small teams lose track of who does what.

## Users

Team members and their lead.

## Scope

- Sign in.
- A shared task list.

## Out of scope

- Billing.

## Features

### F1: Sign in

Members sign in with email and password.

- **EX-F1-01:** Given a registered member, when they send the right password, then they are signed in.
- **EX-F1-02:** Given a registered member, when they send a wrong password, then sign-in is refused.

### F2: Task list

Members keep a shared list of tasks.

- **EX-F2-01:** Given a signed-in member, when they add a task, then it appears in the list.

## Non-functional requirements

- The list loads in under one second for 1000 tasks.

## Constraints

- Runs on one small server.

## Success metrics

- A team uses it daily for a month.

## Open questions

None.
