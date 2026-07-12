# Claim-chain verification (the "hash claims" verb)

Tamper-evident SHA-256 chain over the audit findings ledger. Re-walked on every
change so any future edit to any finding breaks the root. Pairs with the lead
RE-VERIFY discipline: re-prove each headline claim LIVE before re-walking.

## SQLite shape
- `findings` table: (fid, title, severity, status, evidence).
- `claim_hashes` table: (fid, claim_hash, prev_hash, chain_root, generated).
- `claim_manifest.json` written OUTSIDE the db (independent witness) with
  db_sha256, chain_root, generated, claim_count, rehash_reason, live_verdicts.

## Recipe (Python, against fleet_swarm.db)
```python
import sqlite3, hashlib, json, datetime
DB = r"...\fleet_swarm.db"
con = sqlite3.connect(DB); cur = con.cursor()
rows = cur.execute("SELECT fid,title,severity,status,evidence FROM findings ORDER BY fid").fetchall()
db_hash = hashlib.sha256(open(DB,'rb').read()).hexdigest()
gen = datetime.datetime.now().isoformat()
chain_root = hashlib.sha256((db_hash+gen+",".join(r[0] for r in rows)).encode()).hexdigest()
prev = chain_root
for fid,title,sev,status,ev in rows:
    h = hashlib.sha256((prev+fid+title+sev+status+ev).encode()).hexdigest()
    cur.execute("INSERT OR REPLACE INTO claim_hashes VALUES (?,?,?,?,?)",(fid,h,prev,prev,gen))
    prev = h
json.dump({"db_sha256":db_hash,"chain_root":prev,"generated":gen}, open("claim_manifest.json","w"))
```
On the NEXT run, recompute db_sha256 and walk again; if any finding text changed,
the per-row claim_hash and the final chain_root both shift -- that IS the tamper signal.

## Live re-verify BEFORE re-walk (the point of "hash claims")
For each headline claim with a live check available, re-run it THIS turn and record
a verdict (PROVEN / NOT PROVEN / FALSE). Only then re-walk the chain.

## GOTCHA that produced a FALSE "CONTRADICTED" this session
A claim-chain re-verify reported 5 findings contradicted. Root cause was TOOLING,
not drift:
1. subprocess-wrapped `powershell ... -Command "cmd /c netstat ... | Select-String LISTENING"`
   SILENTLY returned 0 rows (MSYS/PS pipe eats cmd.exe stdout). The bare-terminal
   form writing to a file works: redirect to `C:/.../net.txt` then parse the file.
2. Regex `\S+` failed on netstat's spaced 2nd column `0.0.0.0:0`; use `[\d.]+:\d+`.
Both made the live check return 0 matches -> false contradiction. Fix the capture,
re-run, and the chain re-verifies clean.

## Reference impl
`swarm/zbit-litellm-20260711/audit_hash_claims.py` (pattern; adapt paths).
