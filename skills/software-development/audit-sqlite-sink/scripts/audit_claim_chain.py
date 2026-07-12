"""Tamper-evident claim chain over an audit SQLite ledger.

Usage:  python scripts/audit_claim_chain.py <ledger.db> [out_manifest.json]
Re-hashes every finding into a SHA-256 chain (each hash binds the previous
hash) and writes an independent witness manifest OUTSIDE the db. After any
findings mutation, re-run to refresh chain_root.

Verify-later: re-hash db file + re-walk claim_hashes; both must match the manifest.
"""
import sqlite3, hashlib, json, sys, os, datetime

DB = sys.argv[1] if len(sys.argv) > 1 else "fleet_swarm.db"
OUT = sys.argv[2] if len(sys.argv) > 2 else "claim_manifest.json"

con = sqlite3.connect(DB); cur = con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS claim_hashes (
    fid TEXT, content_hash TEXT, prev_hash TEXT, chain_hash TEXT)""")
rows = cur.execute("SELECT fid,title,severity,status,evidence FROM findings ORDER BY fid").fetchall()

prev = '0' * 64
chain = []
for fid, title, sev, status, ev in rows:
    canon = f"{fid}|{title}|{sev}|{status}|{ev}"
    h = hashlib.sha256(canon.encode("utf-8")).hexdigest()
    this = hashlib.sha256((prev + h).encode("utf-8")).hexdigest()
    chain.append((fid, h, prev, this))
    prev = this
root = prev

cur.execute("DELETE FROM claim_hashes")
cur.executemany("INSERT INTO claim_hashes VALUES(?,?,?,?)", chain)
db_sha = hashlib.sha256(open(DB, "rb").read()).hexdigest()
manifest = {
    "generated": datetime.datetime.now().isoformat(),
    "db_path": os.path.abspath(DB),
    "db_sha256": db_sha,
    "claim_count": len(chain),
    "chain_root": root,
    "claims": [{"fid": c[0], "content_hash": c[1], "prev_hash": c[2], "chain_hash": c[3]} for c in chain],
}
json.dump(manifest, open(OUT, "w"), indent=2)
con.commit(); con.close()
print(f"claims={len(chain)} chain_root={root[:16]}... manifest={OUT} db_sha={db_sha[:16]}...")
