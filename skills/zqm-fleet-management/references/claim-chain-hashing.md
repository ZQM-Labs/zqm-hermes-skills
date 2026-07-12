# Tamper-evident SHA-256 claim chain (RECREATION-tier anchoring)

The user's standing "hash claims" / "investigate fully" mandate requires that
every finding in the audit ledger be cryptographically anchored so a later edit
to ANY finding's text is detectable. This is the canonical pattern (proven live
this session over a 60-finding SQLite ledger).

## When to use
- After any audit pass where findings were written to SQLite.
- As the FINAL step of "investigate fully" / "hash claims" — re-verify every
  headline claim LIVE, then re-walk the chain.
- Before handing the ledger to the user as a closed deliverable.

## The chain algorithm
Store findings in a table `(fid, title, severity, status, evidence)`. Chain them
head->tail so each hash depends on the previous:

```python
import sqlite3, hashlib, json, datetime
DB = "fleet_swarm.db"
con = sqlite3.connect(DB); cur = con.cursor()
rows = cur.execute(
    "SELECT fid,title,severity,status,evidence FROM findings ORDER BY fid").fetchall()
db_hash = hashlib.sha256(open(DB,'rb').read()).hexdigest()   # file integrity
gen = datetime.datetime.now().isoformat()
# seed the chain with the DB hash + generation + all fids
chain_root = hashlib.sha256((db_hash+gen+",".join(r[0] for r in rows)).encode()).hexdigest()
prev = chain_root
for fid,title,sev,status,ev in rows:
    h = hashlib.sha256((prev+fid+title+sev+status+ev).encode()).hexdigest()
    prev = h   # each link depends on the previous -> any edit breaks the tail
chain_root = prev   # final root = tamper fingerprint of the WHOLE ledger
```

Persist per-claim hashes + the root back into the DB (`claim_hashes` table) AND
write an EXTERNAL `claim_manifest.json` that lives OUTSIDE the DB.

## Why the external manifest matters
If an attacker (or a careless edit) changes a finding's `evidence` text inside the
DB, the DB's own `claim_hashes` table could be rewritten too — but the standalone
`claim_manifest.json` (saved elsewhere, e.g. the audit working dir, or a git repo
outside the DB) still holds the OLD `chain_root`. Diff the live-recomputed root
against the manifest root → mismatch = tamper. The manifest is the witness; the
DB is the defendant.

## Manifest contents
```json
{
  "generated": "2026-07-11T...",
  "db_path": ".../fleet_swarm.db",
  "db_sha256": "<sha256 of the DB file>",
  "chain_root": "<final chained hash>",
  "claim_count": 60,
  "rehash_reason": "investigate-fully RECREATION tier: all claims re-verified LIVE",
  "live_recreation_verdict": { "C1_N2_Redis_unauth": "PASS (+PONG x3)", ... },
  "open_questions_remaining": ["Q17","Q18",...],
  "note": "chain_root changes if ANY finding's text changes. Manifest is external witness."
}
```

## Live re-verification BEFORE hashing (do not skip)
Hash the CURRENT state, but first RE-PROVE each headline claim against live output
(RECREATION tier). This session re-checked 9 claims: N2 Redis +PONG, N1 sshd
`passwordauthentication yes` (sshd -G), all fleet nodes HTTP 200, proxy no-auth 200,
ZBit :8400 gated, N1 Ollama block>allow, proxy loopback-only, master_key unset,
Ollama bind drift. All PASS. If a re-check FAILS, investigate the TEST first
(false-negative trap) before recording a contradiction — this session's first
automated pass threw 2 false FAILs (wrong test path -> 405 not 401; wrong regex
`:::11434` missed `0.0.0.0:11434`). Fix the probe, re-verify, then record honestly.

## Re-runnability
Make the hasher idempotent: `DROP TABLE IF EXISTS claim_hashes` then recreate, so
re-running after a legitimate finding edit produces a fresh, consistent root. The
audit is never "done" until the manifest root matches a live re-walk with zero
contradictions.

## Pitfalls
- **Don't hash the DB then claim the DB is tamper-proof.** Hash a chain OVER THE
  ROW CONTENTS, not just the file — file hashing catches binary corruption but not
  a silent `UPDATE findings SET evidence=...` that preserves row count.
- **External manifest path must differ from the DB path** or it inherits the same
  tamper surface. Put it in the audit working dir / a separate git repo.
- **Re-verify before re-hash.** A chain over STALE-but-wrong findings just anchors
  the error. The live recreation step is the quality gate, not a formality.
