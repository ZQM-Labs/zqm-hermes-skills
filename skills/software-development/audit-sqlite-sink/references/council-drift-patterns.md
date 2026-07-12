# Council Drift-Check + Pattern Study (re-derive / "investigate fully" re-run)

Proven 2026-07-11 ZQM fleet audit. Two deliverables the user expects
when they say "investigate fully" (re-derive) or "study patterns":

## 1. HASH-DRIFT-CHECK (ledger integrity + state-stability proof)

The claim ledger (`claim_hash(id,claim,status,evidence,sha256,reverify)`)
is only trustworthy if you can RE-PROVE it from live state. Never trust the
stored hash — recompute it from a fresh probe and compare.

```python
import sqlite3, hashlib, socket, time, datetime
DB="fleet_endpoint_audit.db"
con=sqlite3.connect(DB); c=con.cursor()
def h(s): return hashlib.sha256(s.encode()).hexdigest()[:16]

def redis_ping(ip):
    s=socket.socket(); s.settimeout(2)
    try:
        s.connect((ip,6379)); s.sendall(b"PING\r\n"); time.sleep(0.3)
        return s.recv(1024)            # NOTE: 1024, not 200 — 200 truncated the body
    except Exception as e: return b"ERR:"+str(e).encode()
    finally: s.close()
def http_get(ip,p,path):
    s=socket.socket(); s.settimeout(3)
    try:
        s.connect((ip,p)); s.sendall(("GET %s HTTP/1.0\r\n\r\n"%path).encode()); time.sleep(0.4)
        return s.recv(1024)
    except Exception as e: return b"ERR:"+str(e).encode()
    finally: s.close()

live = { "N2redis": redis_ping("192.168.1.21"),
         "N1ollama": http_get("192.168.1.218",11434,"/api/tags"),
         # ... one entry per claim ... }
# recompute + compare
stored = {r[1]:(r[2],r[3]) for r in c.execute("SELECT id,claim,status,sha256 FROM claim_hash")}
drift=stable=0
for claim, cur_status in claim_state():        # (claim, live_status)
    old_status, old_hash = stored[claim]
    new_hash = h(claim+cur_status)
    if new_hash != old_hash or cur_status != old_status:
        drift+=1; print("[DRIFT]", claim, old_status, "->", cur_status)
    else:
        stable+=1; print("[OK]", claim, new_hash)
print("STABLE=%d DRIFT=%d"%(stable,drift))
```

PITFALLS burned this session:
- **recv(200) truncated the HTTP body** -> `"model"` substring not found in
  the truncated bytes -> FALSE DRIFT on a healthy LiteLLM (emits `"id":`,
  not `"model":`). Fix: `recv(1024)` + match `"id":`.
- **Substring `in` matcher false-positive:** summary did
  `"YES" if "FOUND" in r.stdout` but stdout was `"TASK_NOT_FOUND"` ->
  `"FOUND"` is a substring of `"NOT_FOUND"`. Fix: `.startswith("TASK_FOUND")`.
- **Hash recompute must use the SAME (claim+status) string** as the original
  insert, or a stale-state mismatch reads as drift. If DRIFT appears, FIRST
  re-run the probe bare to confirm the live state actually changed; only then
  flip the verdict. A checker bug is a FALSE drift, not a real one.

## 2. PATTERN STUDY (recurring vs one-off)

When the user says "study patterns", mine the gathered data for RECURRENCE,
not just count errors. Four classes observed + how to read them:

- **RECURRING (boot-correlated):** sshd crashed 3x — one was 30s after a
  power-off reboot (post-boot startup race, known Win OpenSSH quirk). Signal:
  correlates with system start, not random. Mitigate with auto-restart.
- **SINGLE / non-recurring:** only 1 Kernel-Power 41 (unexpected shutdown)
  in the window. Rules OUT a crash-reboot loop. Report as one-off.
- **RECENT-CLUSTERED (triggered regression):** all litellm zbit-heavy
  timeouts sat in the log TAIL (lines 250-370 of 374), not spread over
  lifetime. Signal: a NEW onset after a config edit / resource eviction —
  fixable at the config layer, not a chronic disease.
- **RECURRING-STABLE (post-fix):** hash-drift re-verify was drift=1 for the
  first 2 runs (checker bug), then stable=7/drift=0 for 7 consecutive
  runs after the fix. Signal: once the checker was corrected, the ledger is
  provably stable across every re-verify — strong evidence state is genuinely
  unchanging, not a flaky reading.

SCHEMA for patterns table (add to the sink DB):
`patterns(id,pattern,signal,evidence,recurring,ts)`
values: recurring in {RECURRING(boot), SINGLE, RECENT-CLUSTERED, RECURRING-STABLE}

ROOT-CAUSE table (pairs with patterns):
`root_cause(id,finding,root_cause,evidence,classification,ts)`
classification in {deliberate-poweroff, config-gap, mitigated-crash, ...}

DEEP-LEARN table (who/why):
`deep_learn(id,topic,finding,evidence,ts)`

## 3. The re-derive contract (extends audit-sqlite-sink §CONTRACT)

"investigate fully" re-run = do NOT trust the prior ledger. Re-probe EVERY
headline claim live (process/service/security layers + external fleet + hash
integrity), re-verify, THEN update. The 2026-07-11 full re-derive
confirmed all 7 prior claims STABLE=7/DRIFT=0 and re-affirmed the
N2-Redis CRITICAL + Ollama-LAN-by-design genesis from scratch.
