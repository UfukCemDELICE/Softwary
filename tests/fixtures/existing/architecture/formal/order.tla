------------------------------ MODULE order ------------------------------
(***************************************************************************)
(* A small order: it is created, paid, shipped or cancelled. `Bug` picks  *)
(* a broken variant: "none" is the model as it should be.                  *)
(***************************************************************************)
EXTENDS Naturals

CONSTANT Bug  \* "none" | "shipunpaid" | "shipcancelled"

VARIABLES status,       \* the order's state
          paid,         \* the customer has paid
          everShipped   \* history: the order has been shipped

vars == <<status, paid, everShipped>>

States == {"created", "paid", "shipped", "cancelled"}

TypeOK == /\ status \in States
          /\ paid \in BOOLEAN
          /\ everShipped \in BOOLEAN

Init == /\ status = "created"
        /\ paid = FALSE
        /\ everShipped = FALSE

pay == /\ status = "created"
       /\ status' = "paid"
       /\ paid' = TRUE
       /\ UNCHANGED everShipped

ship == /\ \/ status = "paid"
           \/ Bug = "shipunpaid" /\ status = "created"
        /\ status' = "shipped"
        /\ everShipped' = TRUE
        /\ UNCHANGED paid

cancel == /\ \/ status \in {"created", "paid"}
             \/ Bug = "shipcancelled" /\ status = "shipped"
          /\ status' = "cancelled"
          /\ UNCHANGED <<paid, everShipped>>

Next == pay \/ ship \/ cancel

Spec == Init /\ [][Next]_vars

\* An order that is shipped has been paid for.
ShippedWasPaid == status = "shipped" => paid

\* An order that was shipped is never cancelled afterwards.
CancelledNeverShipped == status = "cancelled" => ~everShipped

=============================================================================
