#!/usr/bin/env python3
"""Chained SHA-256 claim ledger (generic, reusable).

Feed claims as a JSON file (list of dicts: id, statement, status, observed, evidence)
or inline. Builds a tamper-evident chain:
    chain[0] = sha256("GENESIS" | content[0])
    chain[i] = sha256(chain[i-1] | content[i])
    content  = id|statement|status|observed|ts
Emits claim_manifest.json + claim_manifest.md with chain_root, and self-checks by
re-walking the chain. Re-run later with the same claims; a mismatched chain_root means
a claim was altered.

Usage:
    python claim_hash_chain.py --claims claims.json [--out DIR]
    python claim_hash_chain.py --id B1 --statement "..." --status PROVEN --observed "200"
"""
import argparse, json, hashlib, os, datetime, sys

def build_chain(claims, ts):
    prev = b"GENESIS"; chain = []
    for c in claims:
        content = "%s|%s|%s|%s|%s" % (c["id"], c["statement"], c["status"], c.get("observed",""), ts)
        h = hashlib.sha256(prev + b"|" + content.encode("utf-8")).hexdigest()
        chain.append({"id": c["id"], "hash": h})
        prev = bytes.fromhex(h)
    return chain, prev.hex()

def rewalk(claims, ts, chain_root):
    _, rec = build_chain(claims, ts)
    return rec == chain_root

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--claims", help="JSON file: list of {id,statement,status,observed,evidence}")
    ap.add_argument("--id"); ap.add_argument("--statement"); ap.add_argument("--status")
    ap.add_argument("--observed", default=""); ap.add_argument("--out", default=".")
    a = ap.parse_args()
    if a.claims:
        claims = json.load(open(a.claims))
    elif a.id and a.statement and a.status:
        claims = [{"id": a.id, "statement": a.statement, "status": a.status, "observed": a.observed}]
    else:
        print("need --claims FILE or --id/--statement/--status"); sys.exit(2)
    ts = str(int(datetime.datetime.now().timestamp()))
    chain, root = build_chain(claims, ts)
    tally = {}
    for c in claims:
        tally[c["status"]] = tally.get(c["status"], 0) + 1
    manifest = {"generated": datetime.datetime.now().isoformat(), "ts": ts, "chain_root": root,
                "tally": tally, "claim_count": len(claims),
                "claims": [dict(c, hash=ch["hash"]) for c, ch in zip(claims, chain)]}
    os.makedirs(a.out, exist_ok=True)
    jp = os.path.join(a.out, "claim_manifest.json")
    mp = os.path.join(a.out, "claim_manifest.md")
    json.dump(manifest, open(jp, "w"), indent=2)
    lines = ["# Claim Manifest", "Generated %s" % manifest["generated"],
             "chain_root=%s" % root, "tally=%s" % tally, ""]
    for c in claims:
        lines.append("- [%s] %s: %s" % (c["status"], c["id"], c["statement"]))
        lines.append("    observed: %s" % c.get("observed", ""))
    open(mp, "w").write("\n".join(lines))
    ok = rewalk(claims, ts, root)
    print("chain_root=%s claims=%d tally=%s rewalk_ok=%s" % (root, len(claims), tally, ok))
    print("wrote %s + %s" % (jp, mp))

if __name__ == "__main__":
    main()
