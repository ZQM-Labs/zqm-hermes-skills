# ZQM-Quantum-Automation — Investigation Findings & Reusable Technique

Investigated 2026-07-09. Repo: `C:\Users\zqmco\ZQM-Quantum-Automation`.
Run with system Python; H1 hash reproduced; billing/API source mismatch confirmed.

## What the repo actually is

Two layers merged into one folder:

- **(A) Real Python project** — FastAPI service "QP-VaaS" / "CVG Quantum Test
  Runner" that runs 35 hypothesis checks (H1–H35) + a billing microservice.
- **(B) Pseudoscientific narrative markdown** — `dark_realm.md`, `omnimap.md`,
  `progress_map.md` about an ancient "Resonant Network," Schumann-energy
  harvesting, "planet is our hardware," a "multiverse mesh," and a claimed
  "first light activation" on 2026-06-30. Fiction; not backed by any code or
  measured data in the repo.

## Key findings (verified, not asserted)

1. **Engine mostly a stub that always passes.** H1 (SHA3-256) is genuine —
   computed == `6f7ddbb8bc8d068d198409bf382b0ac57efa2377c33b49e40e2b6816f1d8764a`
   → real PASS. H2–H7 return hardcoded `pass=True`. H8–H30 check a hardcoded
   constant vs threshold (e.g. H11 rectenna just checks a string contains
   "Micro"). H31–H35 are real math (horn-torus volume, Webster horn
   `f0=c/4(r+Δℓ)`, amplituhedron Plücker minors, singularity regularization).
   `api_service.py:669` /latest-results HARDCODES all 31 as "PASS"/"PROMOTABLE".
2. **Status persistence bug → wrong verdict logged.** Envelope has `"promotion"`
   (PROMOTABLE/REJECTED) and per-result `"pass"`, no top-level `"pass"`. H21–H30
   do `result.get("pass")` → always `None` → always record "FAIL". H8–H12 do
   `result.get("status","UNKNOWN")` → envelope has no `"status"` → always
   "UNKNOWN". Confirmed in `quantum_results.db`: both rows `status="UNKNOWN"`.
3. **Billing disconnected from API (verified).** API persists usage to SQLite
   `usage_events` table; `billing_service.py:51` reads
   `quantum_automation/usage_events.jsonl` — a file the API never writes. No such
   JSONL exists → billing generates empty invoices. Paths also assume CWD is
   parent of a `quantum_automation/` subdir (real dir is `ZQM-Quantum-Automation`).
4. **Cross-user hardcoded paths.** `runner.py:26` and `stale_rotation_service.py:19`
   hardcode `C:\Users\AlexZelenski\Desktop\...` (a different user). On host zqmco
   those dirs don't exist; spine writer hits PermissionError after mkdir fails.
   `stale_rotation_service.py` clears `AlexZelenski\Desktop\quantum_automation\__pycache__`
   — wrong cache (not this project's). `__pycache__` has three 0-byte files
   (`stale_cache*.pyc`) — anomalous, delete.
5. **Security posture of api_service.py.** CORS `allow_origins=["*"]` +
   `allow_credentials=True` (invalid/insecure). `TrustedHostMiddleware
   allowed_hosts=["*"]` is a no-op. Single hardcoded key
   `example-client`/`example-key-12345`. In-memory `rate_limit_store` never
   evicts → minor leak.
6. **H31–H35 orphaned.** Defined + runnable via `runner.py`, but API only exposes
   H1–H30 and `/test/{id}` accepts only H1–H30 (`api_service.py:648`).
7. **Runtime evidence.** `api_server.log` shows uvicorn `0.0.0.0:8000` (pid 12458)
   served /metrics + two POST 200s from 192.168.1.21. Plus "Invalid HTTP request"
   warnings + HEAD / 404 — routine noise, not an attack.
8. **requirements.txt incomplete.** Omits fastapi/uvicorn (required by
   api_service.py); lists liboqs-python/pqcrypto never imported (H2 PQC is a sha3
   stub). `pip install -r requirements.txt` won't give a working API.

## Reusable technique (apply to any ZQM mixed repo)

- Grep written path vs read path to catch data-source disconnects.
- Inspect a DB row after a request to catch wrong-key persistence bugs.
- Reproduce hardcoded expected values (hashes, constants) in a throwaway script.
- Separate `*.py`/`*.db`/`*.json` (evidence) from `*_realm.md`/`omnimap.md`
  (fiction); state the split; don't let narrative claims pass as fact.
- Severity-rank: HIGH = misleads users; MEDIUM = security defaults + ops drift;
  LOW = anomalies + orphaned modules.
- Write full findings to an on-disk `.md` report; summarize in plain terminal text.

## Suggested fixes (offered, not applied)

Fix status-key bug; rewire billing to SQLite source; correct AlexZelenski paths;
tighten CORS/auth; add fastapi/uvicorn to requirements.
