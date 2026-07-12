#!/usr/bin/env python3
"""
claims_core.py -- GENERIC compute core for an API/attestation claim system.

Distilled from the ZQM fleet attestation (2026-07-12). Ships with a tiny
DEMO claim set + dummy probes so it runs standalone with ZERO external deps.
To use for real: replace gather_probes() and build_claims() with your live
probes/claims; keep build_chain(), audit_chain_status(), build_attestation() as-is.

DESIGN RULE (the lesson): build_attestation() is the ONLY public entry point.
Both the offline manifest writer AND the HTTP server import it, so the two
delivery paths can never diverge. Never call probes twice per request.

api_server.py imports build_attestation() from THIS module.
"""
import sqlite3, subprocess, hashlib, time, os, datetime

DB_AUDIT = None  # path to an existing claim_hashes ledger, or None to skip audit re-walk

def sh(cmd, timeout=8):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return "ERR:%s" % str(e)[:80]

# ---- 1) LIVE PROBES (replace with real ones) ---------------------------------
def gather_probes():
    """Return a dict of raw observed values. Demo = harmless."""
    return {
        "demo_port": sh('curl -s -o /dev/null -w "%%{http_code}" --max-time 4 http://127.0.0.1:8088/ 2>nul')[:3] or "000",
        "demo_time": datetime.datetime.now().strftime("%H:%M:%S"),
    }

# ---- 2) CLAIM SET (replace with real ones) ----------------------------------
def build_claims(p):
    def C(cid, claim, status, evidence):
        return {"id": cid, "claim": claim, "status": status, "evidence": evidence}
    return [
        C("D1", "Demo: attestation API responds on :8088",
           "PROVEN", "curl / -> %s" % p["demo_port"]),
        C("D2", "Demo: clock present",
           "PROVEN", "local time %s" % p["demo_time"]),
    ]

# ---- 3) HASH CHAIN (do not change) ----------------------------------------
def build_chain(claims, ts):
    chain = []
    prev = b"GENESIS"
    for cl in claims:
        content = "%s|%s|%s|%s|%s" % (cl["id"], cl["claim"], cl["status"], cl["evidence"], ts)
        h = hashlib.sha256(prev + b"|" + content.encode("utf-8")).hexdigest()
        chain.append({"hash": h, "id": cl["id"]})
        prev = bytes.fromhex(h)
    return chain, prev.hex()

# ---- 4) AUDIT-DB EXISTING CHAIN RE-WALK (read-only) ----------------------
def audit_chain_status(db_path=None):
    db_path = db_path or DB_AUDIT
    if not db_path or not os.path.exists(db_path):
        return {"valid": None, "rows": 0, "reason": "no audit DB configured"}
    try:
        c = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
        rows = c.execute("SELECT fid, claim_hash, prev_hash, chain_root FROM claim_hashes").fetchall()
        by_prev = {r[2]: r for r in rows}
        claim_set = {r[1] for r in rows}
        heads = [r for r in rows if r[2] not in claim_set]
        if len(heads) != 1:
            return {"valid": False, "rows": len(rows), "reason": "heads=%d" % len(heads)}
        prev = bytes.fromhex(heads[0][2]) if len(heads[0][2]) == 64 else heads[0][2].encode()
        cur = heads[0]
        for _ in range(len(rows)):
            exp = hashlib.sha256(prev + b"|" + cur[1].encode()).hexdigest()
            if exp != cur[3]:
                return {"valid": False, "rows": len(rows), "reason": "break at %s" % cur[0]}
            prev = bytes.fromhex(cur[3])
            nxt = by_prev.get(cur[1])
            if nxt is None:
                break
            cur = nxt
        return {"valid": True, "rows": len(rows), "chain_root": prev.hex(),
                "generated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
    except Exception as e:
        return {"valid": False, "rows": -1, "reason": str(e)[:80]}

# ---- 5) PUBLIC ENTRY POINT (imported by offline writer + HTTP server) --------
def build_attestation():
    ts = str(int(time.time()))
    probes = gather_probes()
    claims = build_claims(probes)
    tally = {}
    for cl in claims:
        tally[cl["status"]] = tally.get(cl["status"], 0) + 1
    chain, root = build_chain(claims, ts)
    audit = audit_chain_status()
    return {
        "generated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "ts": ts,
        "claim_count": len(claims),
        "tally": tally,
        "chain_root": root,
        "chain": chain,
        "claims": claims,
        "probes": probes,
        "audit_db_chain": audit,
    }

if __name__ == "__main__":
    import json
    print(json.dumps(build_attestation(), indent=2))
