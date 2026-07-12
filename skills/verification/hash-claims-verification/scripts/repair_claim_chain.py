#!/usr/bin/env python3
"""
repair_claim_chain.py -- repair a broken claim_hashes chain in a fleet audit DB so it
is tamper-evident again.

WHAT IS BROKEN (observed 2026-07-12 on fleet_endpoint_audit.db):
  - All rows stored the SAME chain_root (placeholder).
  - 68 distinct prev_hash values, 0 of which equal any stored chain_root.
  - Rows didn't chain to each other.
  BUT: the prev_hash POINTERS were already correct (67/68 link forward to a prior
  row's claim_hash; 1 head has an external 64-hex anchor). So the fix is to WALK the
  pointers to recover true order, then recompute chain_root only. DO NOT rewrite prev_hash.

REPAIR:
  Recompute chain_root[i] = sha256(chain_root[i-1] || claim_hash[i]), walking the real
  order via prev_hash pointers. prev_hash is LEFT AS-IS.

SAFETY:
  Default = DRY-RUN (read-only, prints plan, writes nothing).
  Pass --apply to actually UPDATE chain_root. Backs up to claim_hashes_bak_<ts> first.
  Run only with explicit operator consent (mutates the audit DB).
"""
import sqlite3, hashlib, sys, os, datetime

DB = r"C:\Users\zqmco\swarm\fleet_endpoint_review\fleet_endpoint_audit.db"

def load():
    c = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    rows = c.execute("SELECT fid, claim_hash, prev_hash, chain_root FROM claim_hashes").fetchall()
    c.close()
    return rows

def reconstruct_order(rows):
    """Walk forward: next row is the one whose prev_hash == current row's claim_hash."""
    by_prev = {r[2]: r for r in rows}                 # prev_hash -> row
    claim_set = {r[1] for r in rows}
    heads = [r for r in rows if r[2] not in claim_set]  # prev not a claim_hash => anchor head
    if len(heads) != 1:
        return None, "heads=%d (expected 1): %s" % (len(heads), [h[0] for h in heads])
    order = [heads[0]]
    seen = {heads[0][0]}
    cur = heads[0]
    while True:
        nxt = by_prev.get(cur[1])                     # row whose prev == cur.claim_hash
        if nxt is None:
            break
        if nxt[0] in seen:
            return None, "CYCLE at %s" % nxt[0]
        order.append(nxt); seen.add(nxt[0]); cur = nxt
    if len(order) != len(rows):
        missing = set(r[0] for r in rows) - seen
        return None, "ORPHANS (%d) not reachable: %s" % (len(missing), list(missing)[:8])
    return order, "OK len=%d" % len(order)

def recompute(order):
    anchor = order[0][2]                              # external 64-hex anchor
    prev = bytes.fromhex(anchor) if len(anchor) == 64 else anchor.encode()
    out = []
    for r in order:
        h = hashlib.sha256(prev + b"|" + r[1].encode()).hexdigest()
        out.append((r[0], h))
        prev = bytes.fromhex(h)
    return out, prev.hex()

def main():
    apply = "--apply" in sys.argv
    rows = load()
    order, status = reconstruct_order(rows)
    print("ROWS=%d  ORDER_STATUS=%s" % (len(rows), status))
    if order is None:
        print("CANNOT REPAIR: %s" % status); return 1
    new_roots, new_root = recompute(order)
    print("RECONSTRUCTED CHAIN ORDER (fids):", [r[0] for r in order])
    print("NEW CHAIN ROOT: %s" % new_root)
    print("CURRENT (broken) root (all rows): %s" % rows[0][3][:24])
    print("\nBEFORE/AFTER (first 4 rows):")
    old = {r[0]: r[3] for r in rows}
    for fid, nr in new_roots[:4]:
        print("  %s  before=%s  after=%s" % (fid, old[fid][:12], nr[:12]))
    ok = all(new_roots[i][1] == recompute(order[:i+1])[0][-1][1] for i in range(len(new_roots)))
    print("NEW CHAIN CONTIGUOUS: %s" % ok)

    if not apply:
        print("\n[DRY-RUN] no changes written. Re-run with --apply to persist.")
        return 0

    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = "claim_hashes_bak_%s" % ts
    c = sqlite3.connect(DB)
    c.execute("CREATE TABLE IF NOT EXISTS %s AS SELECT * FROM claim_hashes" % bak)
    print("BACKUP -> %s" % bak)
    for fid, nr in new_roots:
        c.execute("UPDATE claim_hashes SET chain_root=? WHERE fid=?", (nr, fid))
    c.commit()
    chk = c.execute("SELECT chain_root FROM claim_hashes WHERE fid=?", (order[-1][0],)).fetchone()[0]
    c.close()
    print("APPLIED. Last row %s chain_root=%s  matches new root? %s" % (order[-1][0], chk[:16], chk == new_root))
    return 0

if __name__ == "__main__":
    sys.exit(main())
