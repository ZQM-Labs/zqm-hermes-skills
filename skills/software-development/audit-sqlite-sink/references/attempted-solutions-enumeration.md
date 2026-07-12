# Attempted-Solutions Enumeration (fleet review ask)

Use when the user says "full enumeration of attempted solutions" / "what did we try" /
"review what was attempted". Source of truth = the APPLIED-STATE tables in
`C:\Users\zqmco\swarm\fleet_endpoint_review\fleet_endpoint_audit.db`
(NOT the minimal swarm schema in `zbit-litellm-*/fleet_swarm.db`).

## Query bank (Python sqlite3, stdlib only)
```python
import sqlite3
F = r"C:/Users/zqmco/swarm/fleet_endpoint_review/fleet_endpoint_audit.db"
c = sqlite3.connect(F)
# what was actually executed (authoritative 'done' list)
for r in c.execute("SELECT fix,status,evidence,ts FROM reliability_applied"):
    print(r)
# every remediation VECTOR + its viability (enumerate ALL, not just the winner)
for r in c.execute("SELECT target,issue,vector,status,blocker,decided FROM remediations"):
    print(r)
# design-state gaps + their gating
for r in c.execute("SELECT area,state,risk,fix,gated,ts FROM reliability"):
    print(r)
# resolved vs open change-log
for r in c.execute("SELECT qid,status,substr(question,1,85),substr(resolution,1,45) FROM open_questions"):
    print(r)
# security fixes applied live (e.g. N2 requirepass)
for r in c.execute("SELECT ts,action,result,state,pending FROM redis_auth"):
    print(r)
```

## Status taxonomy -> classification
- `reliability_applied.status`:
  - APPLIED+VERIFIED / APPLIED (prior)  -> Applied+Verified
  - GATED (UAC) / PARTIAL              -> Gated/Blocked
- `remediations.status`:
  - VIABLE-BLOCKED (needs cred)        -> Gated/Blocked
  - VIABLE / REPORT-ONLY (user scope)  -> Drafted-Open (or user-scope)
  - REJECTED (insecure/non-durable) / DEAD (no listener/cred) -> Rejected/Dead
- `open_questions.status`: RESOLVED -> settled; OPEN -> parked/drafted.

## Output shape (verified 2026-07-12)
Group as:
  A. APPLIED + VERIFIED   (actually executed, confirmed live)
  B. GATED / BLOCKED      (attempted, could NOT complete — cred or UAC)
  C. DRAFTED BUT NOT EXECUTED (script on disk, still OPEN)
  D. REJECTED / DEAD VECTORS (explicitly ruled out — do NOT retry)
  E. META / reconciliation
Close with COUNTS per class + TOTAL. This matches the user's standing
option-enumeration preference (memory: "VALUES option-enumeration").

## Cron-safety (non-negotiable)
The recurring cron 'ZQM fleet diagnostics + drift watch' (every 15 min) hard-codes
`DB = .../fleet_endpoint_audit.db` and reads its `claim_hash` + `hash_drift_log`
tables. Never delete/rename/move that file — it breaks the monitor. When reconciling
(Option A/B), merge stray data IN without disturbing those tables
(see references/reconcile-merge-canonical.md).
