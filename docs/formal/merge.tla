------------------------------ MODULE merge ------------------------------
(***************************************************************************)
(* softwary V4: the parallel merge protocol (see merge.md).                *)
(*                                                                         *)
(* Jobs are admitted (Start), worked on (Begin, work), enqueued by         *)
(* `merge <job>` and merged one at a time by the holder of the merge lock  *)
(* (the drainer). Processes may crash; a dead owner's lock is broken by    *)
(* the next process that wants it. Somebody else may push to the           *)
(* integration branch. After a merge the integration branch is checked; a  *)
(* red branch halts the run (a revert PR is opened, not modelled).         *)
(*                                                                         *)
(* Every action is one critical section of the code (one state-lock        *)
(* section), or one step outside the lock. `Bug` selects a broken variant: *)
(* "none" is the protocol as built.                                        *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Jobs,         \* the slices
          Procs,        \* processes that can drain the queue
          Overlap,      \* set of {j, k}: slices whose touches cross
          Concurrency,  \* loop.conf concurrency
          MaxCrashes,   \* crashes of a draining process
          MaxPushes,    \* pushes by somebody else to the integration branch
          Bug           \* "none" | "nogate" | "nooverlap" | "nolock" | "racyrelease"
                        \* | "nostale" | "haltignored" | "splitdequeue" | "norecover"

VARIABLES st,        \* job -> state
          queue,     \* the merge queue (sequence of jobs)
          lock,      \* owner of the merge lock, or "free"
          pst,       \* process -> "off" | "drain" | "dead"
          cur,       \* process -> job it works on, or "none"
          phase,     \* process -> step of the drainer
          fresh,     \* job -> its branch has the tip of the integration branch
          verified,  \* job -> guard and verify passed on the branch's commit
          prMerged,  \* job -> gh pr merge has been done for it
          checked,   \* job -> the integration branch was checked after its merge
          tipSame,   \* job -> at the merge the branch had the tip (same tree)
          mv,        \* job -> history: it was verified when gh pr merge ran
          ghcalls,   \* job -> history: number of gh pr merge calls
          inflight,  \* processes inside gh pr merge
          mwh,       \* history: a merge started while the run was halted
          halted,    \* the run is halted (integration red)
          released,  \* a drainer gave the lock up because the run was halted
          extBad,    \* the integration branch has a bad commit of somebody else
          crashes, pushes

vars == <<st, queue, lock, pst, cur, phase, fresh, verified, prMerged, checked,
          tipSame, mv, ghcalls, inflight, mwh, halted, released, extBad, crashes, pushes>>

Active == {"ready", "work", "queued"}
Open == Active \cup {"escalated"}

InQueue(j) == \E i \in 1..Len(queue) : queue[i] = j
Without(q, j) == SelectSeq(q, LAMBDA x : x # j)

\* The merge lock can be taken: nobody has it, or its owner is dead (broken
\* first). "nolock": the drainer never uses the lock.
LockTakeable == \/ Bug = "nolock"
                \/ lock = "free"
                \/ (Bug # "nostale" /\ lock # "free" /\ pst[lock] = "dead")
Unlock(p) == IF lock = p THEN "free" ELSE lock
TakeLock(p) == IF Bug = "nolock" THEN lock ELSE p

TypeOK ==
  /\ st \in [Jobs -> {"none", "ready", "work", "queued", "merged", "escalated"}]
  /\ queue \in Seq(Jobs)
  /\ lock \in Procs \cup {"free"}
  /\ pst \in [Procs -> {"off", "drain", "dead"}]
  /\ cur \in [Procs -> Jobs \cup {"none"}]
  /\ phase \in [Procs -> {"idle", "emptyseen", "have", "sync", "verify", "merge",
                          "fin", "check", "record", "refused"}]
  /\ inflight \subseteq Procs
  /\ released \in BOOLEAN

Init ==
  /\ st = [j \in Jobs |-> "none"]
  /\ queue = <<>>
  /\ lock = "free"
  /\ pst = [p \in Procs |-> "off"]
  /\ cur = [p \in Procs |-> "none"]
  /\ phase = [p \in Procs |-> "idle"]
  /\ fresh = [j \in Jobs |-> FALSE]
  /\ verified = [j \in Jobs |-> FALSE]
  /\ prMerged = [j \in Jobs |-> FALSE]
  /\ checked = [j \in Jobs |-> FALSE]
  /\ tipSame = [j \in Jobs |-> FALSE]
  /\ mv = [j \in Jobs |-> TRUE]
  /\ ghcalls = [j \in Jobs |-> 0]
  /\ inflight = {}
  /\ mwh = FALSE
  /\ halted = FALSE
  /\ released = FALSE
  /\ extBad = FALSE
  /\ crashes = 0
  /\ pushes = 0

(* --- admission and the work of a job ---------------------------------- *)

\* sw_admit_locked (admit.sh): limit, touches, record and worktree, one section.
Start(j) ==
  /\ st[j] = "none" /\ ~halted
  /\ Cardinality({k \in Jobs : st[k] \in Active}) < Concurrency
  /\ (Bug = "nooverlap" \/ \A k \in Jobs : st[k] \in Open => {j, k} \notin Overlap)
  /\ st' = [st EXCEPT ![j] = "ready"]
  /\ UNCHANGED <<queue, lock, pst, cur, phase, fresh, verified, prMerged, checked,
                 tipSame, mv, ghcalls, inflight, mwh, halted, extBad, crashes, pushes, released>>

\* sw_job_start (job.sh): bootstrap and the `start` event.
Begin(j) ==
  /\ st[j] = "ready"
  /\ st' = [st EXCEPT ![j] = "work"]
  /\ UNCHANGED <<queue, lock, pst, cur, phase, fresh, verified, prMerged, checked,
                 tipSame, mv, ghcalls, inflight, mwh, halted, extBad, crashes, pushes, released>>

\* sw_job_apply escalate: the job goes to the human while it is worked on.
Escalate(j) ==
  /\ st[j] = "work"
  /\ st' = [st EXCEPT ![j] = "escalated"]
  /\ UNCHANGED <<queue, lock, pst, cur, phase, fresh, verified, prMerged, checked,
                 tipSame, mv, ghcalls, inflight, mwh, halted, extBad, crashes, pushes, released>>

(* --- merge <job>: queue and try the lock, one section ------------------ *)

\* sw_merge_enqueue_locked, lock free (or stale): this process is the drainer.
EnqueueDrain(j, p) ==
  /\ st[j] = "work" /\ ~halted /\ pst[p] = "off" /\ LockTakeable
  /\ st' = [st EXCEPT ![j] = "queued"]
  /\ queue' = Append(queue, j)
  /\ lock' = TakeLock(p)
  /\ pst' = [pst EXCEPT ![p] = "drain"]
  /\ cur' = [cur EXCEPT ![p] = "none"]
  /\ phase' = [phase EXCEPT ![p] = "idle"]
  /\ released' = FALSE
  /\ UNCHANGED <<fresh, verified, prMerged, checked, tipSame, mv, ghcalls, inflight,
                 mwh, halted, extBad, crashes, pushes>>

\* sw_merge_enqueue_locked, lock held by a live drainer: `queued: <job> (position n)`.
EnqueueBusy(j) ==
  /\ st[j] = "work" /\ ~halted /\ ~LockTakeable
  /\ st' = [st EXCEPT ![j] = "queued"]
  /\ queue' = Append(queue, j)
  /\ UNCHANGED <<lock, pst, cur, phase, fresh, verified, prMerged, checked, tipSame,
                 mv, ghcalls, inflight, mwh, halted, extBad, crashes, pushes, released>>

\* sw_queue_start (queue.sh): `queue drain` (run next printed `drain`).
DrainStart(p) ==
  /\ pst[p] = "off" /\ ~halted /\ queue # <<>> /\ LockTakeable
  /\ lock' = TakeLock(p)
  /\ pst' = [pst EXCEPT ![p] = "drain"]
  /\ cur' = [cur EXCEPT ![p] = "none"]
  /\ phase' = [phase EXCEPT ![p] = "idle"]
  /\ released' = FALSE
  /\ UNCHANGED <<st, queue, fresh, verified, prMerged, checked, tipSame, mv, ghcalls,
                 inflight, mwh, halted, extBad, crashes, pushes>>

(* --- the drainer ------------------------------------------------------- *)

\* sw_queue_next (queue.sh): one section: a halted run or an empty queue gives
\* the lock up in the same section that saw it; otherwise the head is taken.
\* "haltignored": a halted run is not looked at. "racyrelease": the empty queue
\* is seen in one section and the lock given up in a later one.
Pick(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "idle"
  /\ \/ /\ halted /\ Bug # "haltignored"
        /\ lock' = Unlock(p)
        /\ pst' = [pst EXCEPT ![p] = "off"]
        /\ released' = TRUE
        /\ UNCHANGED <<cur, phase>>
     \/ /\ (~halted \/ Bug = "haltignored") /\ queue = <<>>
        /\ IF Bug = "racyrelease"
              THEN /\ phase' = [phase EXCEPT ![p] = "emptyseen"]
                   /\ UNCHANGED <<lock, pst, cur, released>>
              ELSE /\ lock' = Unlock(p)
                   /\ pst' = [pst EXCEPT ![p] = "off"]
                   /\ UNCHANGED <<cur, phase, released>>
     \/ /\ (~halted \/ Bug = "haltignored") /\ queue # <<>>
        /\ cur' = [cur EXCEPT ![p] = Head(queue)]
        /\ phase' = [phase EXCEPT ![p] = "have"]
        /\ UNCHANGED <<lock, pst, released>>
  /\ UNCHANGED <<st, queue, fresh, verified, prMerged, checked, tipSame, mv, ghcalls,
                 inflight, mwh, halted, extBad, crashes, pushes>>

\* "racyrelease" only: the lock is given up after the queue was seen empty.
RacyRelease(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "emptyseen"
  /\ lock' = Unlock(p)
  /\ pst' = [pst EXCEPT ![p] = "off"]
  /\ phase' = [phase EXCEPT ![p] = "idle"]
  /\ UNCHANGED <<st, queue, cur, fresh, verified, prMerged, checked, tipSame, mv,
                 ghcalls, inflight, mwh, halted, extBad, crashes, pushes, released>>

\* sw_merge_one: the PR is asked for its state (gh pr view --json state); a
\* merged one is only recorded. "norecover": the state is not asked.
Have(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "have"
  /\ LET j == cur[p] IN
       phase' = [phase EXCEPT ![p] =
                   IF prMerged[j] /\ Bug # "norecover"
                      THEN (IF checked[j] THEN "record" ELSE "check")
                      ELSE "sync"]
  /\ UNCHANGED <<st, queue, lock, pst, cur, fresh, verified, prMerged, checked, tipSame,
                 mv, ghcalls, inflight, mwh, halted, extBad, crashes, pushes, released>>

\* sw_merge_conditions step 2: fetch and merge the integration branch, push.
Sync(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "sync"
  /\ LET j == cur[p] IN
       /\ fresh' = [fresh EXCEPT ![j] = TRUE]
       /\ verified' = [verified EXCEPT ![j] = FALSE]
  /\ phase' = [phase EXCEPT ![p] = IF Bug = "nogate" THEN "merge" ELSE "verify"]
  /\ UNCHANGED <<st, queue, lock, pst, cur, prMerged, checked, tipSame, mv, ghcalls,
                 inflight, mwh, halted, extBad, crashes, pushes, released>>

\* sw_merge_conditions steps 3-9 (guard, approvals, risk, verify, PR, evaluation)
\* on the synced commit: pass, or refuse (sw_merge_refuse_locked: the job is
\* escalated and leaves the queue in one section).
Verify(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "verify"
  /\ LET j == cur[p] IN
       IF extBad /\ fresh[j]
          THEN \* the synced tree has the bad commit: the checks fail
               /\ st' = [st EXCEPT ![j] = "escalated"]
               /\ IF Bug = "splitdequeue"
                     THEN /\ UNCHANGED queue
                          /\ phase' = [phase EXCEPT ![p] = "refused"]
                          /\ UNCHANGED cur
                     ELSE /\ queue' = Without(queue, j)
                          /\ phase' = [phase EXCEPT ![p] = "idle"]
                          /\ cur' = [cur EXCEPT ![p] = "none"]
               /\ UNCHANGED verified
          ELSE /\ verified' = [verified EXCEPT ![j] = TRUE]
               /\ phase' = [phase EXCEPT ![p] = "merge"]
               /\ UNCHANGED <<st, queue, cur, released>>
  /\ UNCHANGED <<lock, pst, fresh, prMerged, checked, tipSame, mv, ghcalls, inflight,
                 mwh, halted, extBad, crashes, pushes, released>>

\* "splitdequeue" only: the refused job is taken out of the queue in a later section.
Dequeue(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "refused"
  /\ queue' = Without(queue, cur[p])
  /\ cur' = [cur EXCEPT ![p] = "none"]
  /\ phase' = [phase EXCEPT ![p] = "idle"]
  /\ UNCHANGED <<st, lock, pst, fresh, verified, prMerged, checked, tipSame, mv, ghcalls,
                 inflight, mwh, halted, extBad, crashes, pushes, released>>

\* sw_merge_one step 10, the call: `gh pr merge --match-head-commit <sha>`.
StartMerge(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "merge"
  /\ (Bug = "haltignored" \/ ~halted)
  /\ (Bug = "nogate" \/ verified[cur[p]])
  /\ LET j == cur[p] IN
       /\ mv' = [mv EXCEPT ![j] = verified[j]]
       /\ tipSame' = [tipSame EXCEPT ![j] = fresh[j]]
       /\ ghcalls' = [ghcalls EXCEPT ![j] = @ + 1]
  /\ inflight' = inflight \cup {p}
  /\ mwh' = (mwh \/ halted)
  /\ phase' = [phase EXCEPT ![p] = "fin"]
  /\ UNCHANGED <<st, queue, lock, pst, cur, fresh, verified, prMerged, checked, halted,
                 extBad, crashes, pushes, released>>

\* The call returns: the PR is merged and the integration branch has moved.
FinishMerge(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "fin"
  /\ prMerged' = [prMerged EXCEPT ![cur[p]] = TRUE]
  /\ fresh' = [j \in Jobs |-> FALSE]
  /\ inflight' = inflight \ {p}
  /\ phase' = [phase EXCEPT ![p] = "check"]
  /\ UNCHANGED <<st, queue, lock, pst, cur, verified, checked, tipSame, mv, ghcalls,
                 mwh, halted, extBad, crashes, pushes, released>>

\* sw_queue_integration (queue.sh): the tip has the tree of the merged commit,
\* or it is verified; red halts the run (the revert PR is opened).
PostCheck(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "check"
  /\ LET j == cur[p] IN
       /\ halted' = (halted \/ (~tipSame[j] /\ extBad))
       /\ checked' = [checked EXCEPT ![j] = TRUE]
  /\ phase' = [phase EXCEPT ![p] = "record"]
  /\ UNCHANGED <<st, queue, lock, pst, cur, fresh, verified, prMerged, tipSame, mv,
                 ghcalls, inflight, mwh, extBad, crashes, pushes, released>>

\* sw_merge_record_locked (merge.sh): `merged`, the queue, the main checkout and
\* the worktree, one section.
Record(p) ==
  /\ pst[p] = "drain" /\ phase[p] = "record"
  /\ st' = [st EXCEPT ![cur[p]] = "merged"]
  /\ queue' = Without(queue, cur[p])
  /\ cur' = [cur EXCEPT ![p] = "none"]
  /\ phase' = [phase EXCEPT ![p] = "idle"]
  /\ UNCHANGED <<lock, pst, fresh, verified, prMerged, checked, tipSame, mv, ghcalls,
                 inflight, mwh, halted, extBad, crashes, pushes, released>>

(* --- the environment --------------------------------------------------- *)

\* A drainer dies (kill -9) between two steps; its lock stays where it is.
Crash(p) ==
  /\ pst[p] = "drain" /\ p \notin inflight /\ crashes < MaxCrashes
  /\ pst' = [pst EXCEPT ![p] = "dead"]
  /\ cur' = [cur EXCEPT ![p] = "none"]
  /\ phase' = [phase EXCEPT ![p] = "idle"]
  /\ crashes' = crashes + 1
  /\ UNCHANGED <<st, queue, lock, fresh, verified, prMerged, checked, tipSame, mv,
                 ghcalls, inflight, mwh, halted, extBad, pushes, released>>

\* Somebody else pushes to the integration branch (good or bad).
ExtPush ==
  /\ pushes < MaxPushes
  /\ pushes' = pushes + 1
  /\ fresh' = [j \in Jobs |-> FALSE]
  /\ \E bad \in BOOLEAN : extBad' = (extBad \/ bad)
  /\ UNCHANGED <<st, queue, lock, pst, cur, phase, verified, prMerged, checked, tipSame,
                 mv, ghcalls, inflight, mwh, halted, crashes, released>>

\* The human merges the revert PR: the integration branch is good again.
ExtFix ==
  /\ halted /\ extBad
  /\ extBad' = FALSE
  /\ fresh' = [j \in Jobs |-> FALSE]
  /\ UNCHANGED <<st, queue, lock, pst, cur, phase, verified, prMerged, checked, tipSame,
                 mv, ghcalls, inflight, mwh, halted, released, crashes, pushes>>

\* sw_run_unhalt (run.sh): `run start` verifies the tip again and lifts the halt.
Resume ==
  /\ halted /\ ~extBad
  /\ halted' = FALSE
  /\ UNCHANGED <<st, queue, lock, pst, cur, phase, fresh, verified, prMerged, checked,
                 tipSame, mv, ghcalls, inflight, mwh, released, extBad, crashes, pushes>>

DrainStep(p) ==
  \/ Pick(p) \/ RacyRelease(p) \/ Have(p) \/ Sync(p) \/ Verify(p) \/ Dequeue(p)
  \/ StartMerge(p) \/ FinishMerge(p) \/ PostCheck(p) \/ Record(p)

Next ==
  \/ \E j \in Jobs : Start(j) \/ Begin(j) \/ Escalate(j) \/ EnqueueBusy(j)
  \/ \E j \in Jobs, p \in Procs : EnqueueDrain(j, p)
  \/ \E p \in Procs : DrainStart(p) \/ DrainStep(p) \/ Crash(p)
  \/ ExtPush \/ ExtFix \/ Resume

Fairness ==
  /\ \A j \in Jobs : WF_vars(Begin(j))
  /\ \A j \in Jobs : WF_vars(EnqueueBusy(j) \/ \E p \in Procs : EnqueueDrain(j, p))
  /\ \A p \in Procs : WF_vars(DrainStart(p))
  /\ \A p \in Procs : WF_vars(DrainStep(p))

Spec == Init /\ [][Next]_vars /\ Fairness

(* --- what must hold ---------------------------------------------------- *)

\* A SHA that did not pass guard and verify is never merged by the loop.
GateBeforeMerge == \A j \in Jobs : prMerged[j] => mv[j]

\* No merge starts while the run is halted.
NoMergeWhileHalted == ~mwh

\* Two jobs whose touches cross are never both on their way (escalated ones count).
NoOverlap == \A j, k \in Jobs : {j, k} \in Overlap => ~(st[j] \in Open /\ st[k] \in Open)

\* At most one gh pr merge runs at a time.
SingleMerger == Cardinality(inflight) <= 1

\* A queued job is in the queue, and every job in the queue is queued, once.
QueueKept ==
  /\ \A j \in Jobs : (st[j] = "queued") <=> InQueue(j)
  /\ Len(queue) = Cardinality({queue[i] : i \in 1..Len(queue)})

\* A queue that waits always has a lock holder (a dead one is broken by the
\* next), unless a drainer gave the lock up on purpose because the run was halted.
QueueOwned == (queue # <<>> /\ ~released) => lock # "free"

\* gh pr merge is called at most once for a job (a merged PR is only recorded).
MergedOnce == \A j \in Jobs : ghcalls[j] <= 1

\* Every job that started is merged, handed to the human, or the run is halted
\* (the human's turn), as long as crashes are finite.
Progress == \A j \in Jobs :
  (st[j] \in {"ready", "work", "queued"}) ~> (st[j] \in {"merged", "escalated"} \/ halted)
=============================================================================
