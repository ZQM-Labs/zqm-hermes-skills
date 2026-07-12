# Audit-Chain Contiguity Validation

When a system keeps its OWN claim ledger (e.g. `fleet_endpoint_audit.db` ->
`claim_hashes`), do NOT trust it blindly. Validate the chain before citing it.

## Check procedure
```python
import sqlite3, hashlib
rows = db("SELECT fid, claim_hash, prev_hash, chain_root
           FROM claim_hashes ORDER BY generated")
rec = b"GENESIS"
for fid, ch, ph, cr in rows:
    rec = hashlib.sha256(rec + b"|" + ch.encode()).hexdigest()
    if rec != cr:
        flag(fid)                       # stored root != recomputed -> broken link
if len({r[3] for r in rows}) == 1:
    flag("all rows share ONE chain_root")          # placeholder / snapshot, not a chain
if len({r[2] for r in rows} & {r[3] for r in rows}) == 0:
    flag("prev_hash links to nothing")             # anchors dangle
```

## Finding — 2026-07-12, fleet_endpoint_audit.db.claim_hashes (68 rows)
The ledger was NON-contiguous. Empirical proof:
- All 68 rows stored the SAME `chain_root` (`9fb4d3df...`).
- 68 distinct `prev_hash` values matched NO stored `chain_root` (0/68 link).
- `F1.root != F10.prev` -> rows do not chain to each other.

Conclusion: the table is a flat snapshot with a placeholder chain. Its
tamper-evidence is non-functional — it cannot prove claims were never altered.

## Why it matters
The monitor that is supposed to catch claim drift/regression cannot, because its
anchor is broken. Treat a non-contiguous audit chain as its own BLIND SPOT (B16-
class) and emit a sound chain (this skill's `scripts/claim_hash_chain.py`) as the
replacement until the table is re-chained.

## Repair (gate on owner OK — mutates the audit DB)

CRITICAL CORRECTION (2026-07-12, verified by building + dry-running the fix): the
stored `prev_hash` pointers were ALREADY CORRECT — 67/68 link forward to a prior
row's `claim_hash`, 1 head (F1) has an external 64-hex anchor. ONLY the accumulated
`chain_root` was a stale placeholder (all rows shared `9fb4d3df...`). Therefore:

  - DO NOT rewrite `prev_hash`. Recover true order by WALKING the existing pointers.
  - DO NOT trust `ORDER BY generated` (constant for all 68 rows) or numeric `fid`
    (non-sequential: F10 follows F1). Order is defined by prev_hash linkage only.
  - Fix ONLY `chain_root[i] = sha256(chain_root[i-1] || claim_hash[i])`.

Walker (recover order from pointers; the 2026-07-12 working version):
```python
by_prev  = {r[2]: r for r in rows}          # prev_hash -> row
claim_set = {r[1] for r in rows}
heads = [r for r in rows if r[2] not in claim_set]   # prev not a claim_hash => anchor head
assert len(heads) == 1, heads
order, seen, cur = [heads[0]], {heads[0][0]}, heads[0]
while True:
    nxt = by_prev.get(cur[1])               # next row: its prev_hash == cur.claim_hash
    if nxt is None: break
    if nxt[0] in seen: raise CycleError(nxt[0])
    order.append(nxt); seen.add(nxt[0]); cur = nxt
assert len(order) == len(rows), "orphans: %s" % (set(r[0] for r in rows) - seen)
```
Then: `prev = bytes.fromhex(heads[0][2])` (external anchor) and fold
`sha256(prev || claim_hash[i])` over `order`, UPDATE `chain_root` per row.

Reusable script (this session, dry-run-verified, NOT yet applied):
`C:\Users\zqmco\swarm\repair_claim_chain.py` — default DRY-RUN (read-only, prints
reconstructed fid order + new chain root `dbd8bc73...` + contiguous check); `--apply`
backs up to `claim_hashes_bak_<ts>` then rewrites `chain_root` only, re-verifies
contiguous. Carry that script into this skill's scripts/ as the canonical re-chainer.

Two walker bugs I actually hit and fixed (so the next session doesn't):
  1. Walking BACKWARD (look up `cur[2]` as a claim_hash) instead of forward
     (`by_prev.get(cur[1])`) -> reported 67 orphans. The edge is: next row's
     `prev_hash` EQUALS current row's `claim_hash`.
  2. A fixed `for _ in range(len(rows)+1)` loop that breaks on first None too early
     under the wrong direction -> use `while True` + explicit cycle/orphan checks.

Verification of the repair itself: re-walk the updated table with the EXACT formula
and assert `chain_root[-1]` equals `new_root` and every row's `chain_root ==
sha256(prior_chain_root || claim_hash)`. If it re-walks contiguous, the ledger is
tamper-evident again.
