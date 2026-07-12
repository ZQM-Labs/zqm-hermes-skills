# Hashed Claim Manifest — tamper-evident fleet claim tree

Used when the user says "hash claims" / "hash claims and investigate fully". Do the
standard `investigate fully` pass (live re-probe of every host), THEN mint a
SHA-256 over each claim's canonical form and persist a `claims` table + a manifest
JSON. The point: every fleet claim becomes referenceable AND tamper-evident, so a
later re-audit detects drift by re-hashing rather than re-reading prose.

## Canonical form (whitespace-robust)
```
canonical = f"{status}\u241f{claim}\u241f{evidence}"   # U+241F unit separator
hash = hashlib.sha256(canonical.encode()).hexdigest()[:16]
```
- Use U+241F (UNIT SEPARATOR), NOT `|` or space — a naive `status|claim|evidence`
  hash breaks on any whitespace/newline drift inside claim/evidence. The separator
  must be a control char that never appears in normal text.
- `status` ∈ {PROVEN, NOT PROVEN, PRIOR-LEDGER, RETRACTED}. PRIOR-LEDGER = claim
  inherited from a prior session's ledger that you did NOT live-re-verify this pass
  (be explicit about which are live vs inherited).

## Persist
```
CREATE TABLE IF NOT EXISTS claims(
  claim_id INTEGER PRIMARY KEY AUTOINCREMENT,
  hash TEXT UNIQUE, status TEXT,
  claim TEXT, evidence TEXT, probed_at TEXT);
-- INSERT (hash,status,claim,evidence,probed_at)
```
Also emit a manifest JSON for human consumption + later diff:
```
manifest = {
  "generated_at": NOW,
  "host_scan": {host: [open_ports]},
  "redis": {...}, "ollama": {...}, "node1_ollama_auth": <code>,
  "claims": [ {hash,status,claim,evidence,probed_at} ... ],
  "counts": {"PROVEN":N, "NOT PROVEN":M, "PRIOR-LEDGER":K}
}
```
Write to `<hermes>/fleet-claims-manifest.json`.

## Why it's useful
Re-running the builder on a later fleet state and diffing the hash list shows
EXACTLY which claims changed — a flipped PROVEN->NOT PROVEN, a new hash, or a
retracted hash that disappeared are all visible at a glance. It is the audit trail
made diffable.

## Builder skeleton (concise, Python, runs in execute_code)
```python
import socket, json, datetime, hashlib, sqlite3, urllib.request, urllib.error

NOW = datetime.datetime.now().isoformat(timespec='seconds')
HOSTS = {"Node-1":"192.168.1.218","Node-2":"192.168.1.21","Node-3":"192.168.1.46",
 "Node-4":"192.168.1.215","G1":"192.168.1.173","G2":"192.168.1.40","NAS":"192.168.1.53"}
# CURATED ports only — full 1-1024 x7 times out execute_code's 300s cap.
PORTS=[21,22,23,53,80,111,135,139,443,445,5000,5001,548,662,873,892,161,2049,
       5985,5986,7000,9000,9119,11434,11435,18789]
def tcp(ip,p,to=0.25):
    try:
        with socket.create_connection((ip,p),timeout=to): return True
    except: return False
scans={h:[p for p in PORTS if tcp(ip,p)] for h,ip in HOSTS.items()}

def add(claims, status, claim, evidence):
    canonical=f"{status}\u241f{claim}\u241f{evidence}"
    h=hashlib.sha256(canonical.encode()).hexdigest()[:16]
    claims.append({"hash":h,"status":status,"claim":claim,"evidence":evidence,"probed_at":NOW})

claims=[]
for h,ip in HOSTS.items():
    add(claims,"PROVEN",f"{h} ({ip}) reachable",f"{len(scans[h])} curated-open: {scans[h]}")
# ... add Redis / Synology / Ollama / WinRM claims via live probes ...

DB="<hermes>/fleet-audit.db"
con=sqlite3.connect(DB); cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS claims(claim_id INTEGER PRIMARY KEY AUTOINCREMENT, hash TEXT UNIQUE, status TEXT, claim TEXT, evidence TEXT, probed_at TEXT)")
cur.execute("DELETE FROM claims")
cur.executemany("INSERT INTO claims(hash,status,claim,evidence,probed_at) VALUES(?,?,?,?,?)",
    [(c["hash"],c["status"],c["claim"],c["evidence"],c["probed_at"]) for c in claims])
con.commit()
from collections import Counter
cnt=Counter(c["status"] for c in claims)
manifest={"generated_at":NOW,"host_scan":scans,"claims":claims,"counts":dict(cnt)}
with open("<hermes>/fleet-claims-manifest.json","w") as f: json.dump(manifest,f,indent=2)
con.close()
print(f"Total {len(claims)} | {dict(cnt)}")
for c in claims: print(f"  [{c['hash']}] {c['status']:12} | {c['claim']}")
```

## VERIFICATION-INTEGRITY RULES (decisive for the manifest's honesty)
A hashed claim is only as true as the probe behind it. Two bugs this session
CORRUPTED the `status` field (and thus the manifest) -- fix before recording:

### R1. Wrong-protocol probe = false "SECURE" (mirror of the loopback blind-spot)
Probing a raw-socket port with the wrong client produces a MISLEADING "secure/
closed" verdict, NOT a hang. Live 2026-07-11: `httpx.get("http://N2:6379")`
against Redis (a RESP socket, not HTTP) TIMED OUT and was logged `PASS-closed` --
but a raw `socket` `PING` -> `+PONG` proved the port OPEN+UNAUTHENTICATED. The
HTTP client's timeout LOOKED like "secured" when it was protocol mismatch.
  RULE: probe each port with a CLIENT THAT SPEAKS ITS PROTOCOL.
    Redis/Memcached/Telnet/FTP -> raw `socket` + protocol handshake (see
    references/endpoint-review.md byte recipes). ONLY HTTP/S services get curl/httpx.
  A timeout from the wrong client is NOT evidence of closure -- confirm with the
  correct client BEFORE flipping a severity or hashing a "PROVEN-secure" claim.
  (This is the inverse of the WINDOWS-FIREWALL-LOOPBACK-BLIND-SPOT pitfall:
  that one hides a live EXPOSURE as "exposed=still open"; this one hides a live
  EXPOSURE as "secure=closed". Both are verification false-negatives that, if
  hashed, entrench a false claim into the tamper-evident tree.)

### R2. netstat regex `\S+` FAILS on the spaced 2nd column
`TCP\s+(\S+):(\d+)\s+\S+\s+(\d+)` silently matches ZERO rows because the
2nd `\S+` cannot span netstat's spaced `0.0.0.0:0` LocalAddress column.
Result: a parser yields "0 listeners" and every listener-based claim flips to
CONTRADICTED -- which, if hashed, writes 5 false "CONTRADICTED" rows.
  FIX: `re.search(r'TCP\s+([\d.]+):(\d+)\s+[\d.]+:\d+\s+LISTENING\s+(\d+)', line)`
    -> groups (localaddr, port, pid). And capture netstat reliably (see
    references/windows-firewall-audit.md A2): bare terminal redirect to a file,
    then parse -- the subprocess-powershell form swallows cmd.exe stdout.
  If your parse yields 0 listeners, HEXDUMP the file bytes first; the data is
  usually there and your regex/pipe is the bug, not the box. Never hash a
  "CONTRADICTED" verdict that a re-capture with the corrected regex reverses.

### R3. Ad-hoc verifier assertion bugs (the malformed-check false-FAIL)
A buggy boolean in your OWN check function yields false FAIL rows even when the
endpoint is correct (e.g. grepping rigid `Action:                               Block`
with 34 spaces; or `ok = sc==200 and d.get("N1").get("count")==0` where the
gated node legitimately returns 0). SYMPTOM: 8/10 pass but 2 "fail" that
are clearly the right status. FIX: never report "tests pass" on a check whose
assertion logic might be the bug. After the script runs, PROVE the artifact is
correct with a DIRECT read (read_file / netsh dump / hexdump) -- that is the real
evidence; the script's green/red is secondary. If the direct read confirms the
code is right, the malformed-check FAIL is a non-finding -- say so, don't loop
patching the assertions. Label every such run "AD-HOC VERIFICATION, not a suite
green." (All three rules hit + caught live 2026-07-11; the manifest's
8/8-PROVEN final state was only reached AFTER correcting R1/R2/R3.)

## Live result (2026-07-11)
33 claims: 26 PROVEN / 3 NOT PROVEN / 4 PRIOR-LEDGER. The 3 NOT PROVEN were explicit
gaps (Node-2 Redis owner/purpose, Node-4 :11435 stability, Node-1 Ollama health
under the token proxy) -- surfaced honestly, never forced to PROVEN. Full 1-1024 scan
was NOT re-run here (it had been captured in an earlier pass and lives in the ledger);
the curated 30-port set completed in ~53s.
(SEPARATE pass, same session, on the LiteLLM/ZBit stack: 8/8 headline claims
RECREATION-verified PROVEN across 3 audit tiers, 0 contradicted, after
correcting R1/R2/R3 above. Chain root + claim_manifest.json emitted as an
independent witness outside the DB.)
