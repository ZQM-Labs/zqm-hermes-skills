# Revive a Discovered First-Party Agent via API (re-home to verified reality)

Worked pattern from the ZBit/ZQM SOUL.md session (2026-07-11). The user had an
agent's full knowledge base in `CVG-CONTAMINATED-Zbit-Knowledge-Base/` + a Google
Drive "declassified" import. Intent was NOT to scrub it but to REVIVE the agent —
bound to the REAL fleet, not the fictional host in its docs.

## 0. Inspect first (parent skill discipline)
Read ALL narrative docs (SOUL/USER/LESSONS/SSH_OPERATIONS/DFORGE-HISTORY/etc).
Map: provenance (user-built → first-party), redaction level, fiction-vs-reality.
The agent's SELF-DESCRIBED host/IP/hardware/models are almost always FICTION.

## 1. Separate fiction from VERIFIED reality (cross-check, never trust)
ZBit doc CLAIMED: HP Pavilion i7-13700T @192.168.1.241, "11 Ollama models ~60GB",
2.8M blocks/hr, CHSH 2.63, 63 devices.
VERIFIED reality: Node-1 = ASUS Vivobook K6602VV / i9-13900H / .218; real Ollama
fleet = 57 models (N1:2 N2:8 N4:45 N3:2). The agent's metrics are self-narrative.

## 2. Re-scrub PII even in "cleaned" output (the leak trap)
A prior sanitize pipeline had already produced `C:\Users\zqmco\.sanitize_work\03_zqm_ready\`
(22 cleaned+zip repos). But the STRICT leak sweep found REAL PII survived:
- ZQM-Zbit-Knowledge-Base.zip → USER.md + DFORGE-11-HISTORY.md: phone +1 (386) 265-9994
- ZQM-Neuron-Core.zip → knowledge.py + Modelfile: phone +1 (386) 957-2314 + email
The NAS password `azelenski/e5Bi6#g7*7qB3Zr$` + old IP 192.168.1.241 survived ONLY
in raw quarantine + GDrive import (the CRITICAL leak surface).
RE-SCRUB recipe (tighten the regex — naive `password`/`Bearer` matches are false
positives like "Password Management Solutions" headings and `Bearer ${process.env.X}`):
  strict = re.compile(r"(e5Bi6|azelenski|265-9994|957-2314)")
  for each zip: rewrite entries, replacing hits with `[REDACTED:label]`, then RE-VERIFY
  with a second pass that flags any line containing the token but NOT `[REDACTED`.
  (The re-scrub's own `[REDACTED:azelenski]` placeholder will false-match the strict
  regex — check for the unredacted bare token, not the label.)

## 3. Wrap identity in an API layer bound to REAL infra (the revive)
Don't run the agent's old host-bound modules (they reference dead D:\ paths + the
old IP). Build a thin adapter:
- FastAPI scaffold (C:\Users\zqmco\ZBit_api\app.py): routes /health, /v1/models
  (fans out to real Ollama /api/tags), /v1/generate (→ LiteLLM), /v1/mesh/scan
  (wraps beacon.py discover), /v1/ledger (READ-ONLY chain.json), /v1/agent/status
  (re-homed identity card). Bind 127.0.0.1; X-Api-Key gate; NO arbitrary exec;
  NO old-host creds loaded.
- LiteLLM gateway in front of the real fleet (see ollama-fleet-lb). keep_alive TTL,
  never -1.
Verify the scaffold with `fastapi.testclient.TestClient` (import + route + /health +
/auth-gate) WITHOUT starting the server.
BLOCKER encountered: Ollama was AUTH-REQUIRED (401 on every endpoint) — the API key
lived at the Ollama SERVICE level, not the shell, and was not readable. Generation
stayed 503 until the real key is supplied. Do NOT claim the fabric "works" without it.

## 4. Council sweep + SQLite (provenance-adjacent)
Full investigation = parallel leaf agents; two hit API 429 and returned NO data, so
the LEAD re-ran Leak + Live-Fleet with live terminal/tool calls (no subagent, no
rate limit). Findings → SQLite (zips/leaks/contradictions/json_failures/fleet_checks/
old_host_refs). Never take a leaf's PASS without re-verifying its headline live.

## Output shape for a revive task
- On-disk: KB read-all map, OMNIMAP, API design + scaffold, SQLite findings DB.
- Explicit: fiction-vs-reality table; leak surface (what's clean vs CRITICAL);
  BLOCKED-at-Ollama-key status (honest, not "works").
