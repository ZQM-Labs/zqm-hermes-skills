# Reconciling dual / competing audit ledgers

Procedure for when an audit leaves two SQLite DBs both claiming to be "the fleet audit"
with conflicting counts. Standing rule: no two audit DBs may drift into ambiguity.

## 1. Diff schemas (read-only, no writes)
```python
import sqlite3
for path in ["fleet_endpoint_audit.db", r"..\zbit-litellm-20260711\fleet_swarm.db"]:
    c=sqlite3.connect(path)
    tabs=[r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    for t in tabs:
        cols=[d[1] for d in c.execute(f"PRAGMA table_info({t})")]
        n=c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"{path.split(chr(92))[-1]}: {t}({len(cols)}) = {n}  cols={cols}")
    c.close()
```
If table NAMES differ (`claim_hash` vs `claim_hashes`) or row counts diverge sharply
(16 vs 68 claims, 4 vs 11 nodes) → they are COMPLEMENTARY timepoints, not corrupt
copies. Do NOT force-merge.

## 2. Declare canonical
Pick by recency + completeness:
- canonical = most recent + has the latest applied fixes (redis_auth live, reliability
  rows, full_investigation, 18 hash_drift_log runs).
- stray = earlier/parallel audit (blockchain-style claim_hashes, broader scope).

## 3. Archive (move, never delete)
```bash
mkdir -p fleet_endpoint_review/archive
mv swarm/zbit-litellm-20260711 fleet_endpoint_review/archive/
```
Reversible via `mv` back. Preserves claim_manifest.json + fleet_swarm.db + scripts.

## 4. Record discrepancy in canonical `meta`
```python
c.execute("INSERT INTO meta VALUES(?,?,?)",
  ("ledger_reconcile","canonical=fleet_endpoint_audit.db; stray archived to fleet_endpoint_review/archive/zbit-litellm-20260711 (fleet_swarm.db, 68 claims/11 nodes, different schema = earlier broader scope, superseded)",
   datetime.datetime.now().isoformat()))
```

## 5. NEVER `git add .` in the stray
The stray dir often has its own `.git/` with no remote and may contain secrets
(auth.json, ca, cache/, SOUL.md). Move files only; do not commit anything from it.

## 6. Salvage unique rows (optional)
Before archiving, diff fid lists; if the stray has findings absent from canonical,
`INSERT` the unique rows into canonical + re-run the hash chain (see audit_claim_chain.py).

## End state
ONE canonical ledger + ONE archived historical dir. Anyone citing "the fleet audit"
reads the canonical; the stray is preserved for provenance.
