# Shop orders

A small shop keeps its orders in files: one file per order holds its state.

- `app/order.sh`: create, pay, ship and cancel an order.
- `app/report.sh`: how many orders are in each state.
- `checks/lint.sh`: reports lines that hold a marker (`XXX`) in the files it is given.
- `checks/test.sh`: runs the test scripts it is given, or all of `tests/`.
- `tests/`: the tests that exist.

Run the checks from this directory: `sh checks/lint.sh`, `sh checks/test.sh`.
