# ZQM Node-1 — ZBit Agent runtime topology (verified 2026-07-11, live)

The user's OWN re-homed ZBit agent. FIRST-PARTY — treat as known-good, not a threat.
Discovered via "investigate fully" on a pasted uvicorn startup log (PID 1908).

## Paths
- `C:\Users\zqmco\ZBit_api\app.py`  — FastAPI "ZBit Agent API" v0.1.0
- `C:\Users\zqmco\ZBit_api\litellm_config.yaml`
- `C:\Users\zqmco\ZBit_api\start_zbit.bat`  — launcher
- `C:\Users\zqmco\ZBit_api\ZBit_runtime\`  — re-homed skill layer (`__init__.py` REGISTRY + `modules/`)

## Launch
- MANUAL only: `start_zbit.bat` → `litellm.exe` (:4001) then `uvicorn app:app` (:8400).
- NO scheduled task registered; NOT in any Startup folder. `app.py` header: "Service is NOT auto-started."

## Bind / processes
- ZBit Agent API: `127.0.0.1:8400` (PID 1908, system Python312). Loopback-only.
- LiteLLM proxy:   `127.0.0.1:4001` (PID 19120, litellm.exe v1.91.2). Loopback-only.

## Auth (verified live)
- ZBit Agent API: `X-Api-Key` REQUIRED on every `/v1/*` route (401 with no key AND bogus key).
  `/health` OPEN. `/openapi.json` + `/docs` + `/redoc` OPEN (200, no key) — full schema
  disclosure incl. the 3 authenticated POST write routes. Loopback-only → low risk.
- LiteLLM proxy: OPEN / UNKEYED (no `master_key`; `chat/completions` 200 with no key & bogus
  key). Mgmt routes (`/key/generate` etc.) mounted but 500 (no `DATABASE_URL`).

## Capability surface (ZBit `/v1/*`, all key-gated)
- GET `/health` (open). GET `/v1/models`. POST `/v1/generate` (→ litellm :4001).
- GET `/v1/mesh/scan` (beacon.py LAN discover). GET+POST `/v1/ledger` (append block to
  `ZBit_runtime/ledger/chain.json`). GET `/v1/skills`. POST `/v1/skill/{name}`.
- GET `/v1/agent/status` (identity/disclosure: host=Node-1, fleet IPs — loopback only).

## REGISTRY (`ZBit_runtime/__init__.py`) — 9 vetted fns, NO eval/exec
`ledger_append, ledger_status, mesh_scan, base_convert, qubit_measure,
qseal_keygen, qseal_sign, qseal_verify, qseal_enroll`.
All writes stay LOCAL (ledger json + `qseal_keypair.pem`). Unknown name → 404.

## LiteLLM fleet routing (`litellm_config.yaml`)
- `zbit-router` → LB N2 (192.168.1.21, open) + N3 (127.0.0.1): deepseek-r1:1.5b / qwen3:8b,
  `least-busy`, keep_alive 5m (NEVER -1).
- `zbit-fast` → N2 deepseek-r1:1.5b. `zbit-heavy` → N2 hermes3:latest.
- N1 (.218) is key-gated (401) — commented out until `OLLAMA_API_KEY` supplied.
- Hash-named models in startup warnings are LiteLLM's computed `model_info.id` (visible in
  `/model/info`), NOT a config mismatch. `server.port: 4000` in yaml is overridden by
  `start_zbit.bat --port 4001` (cosmetic drift).

## Verdict
FIRST-PARTY, benign. Access = loopback isolation + ZBit `X-Api-Key`.
Gaps (low-risk while loopback): open LiteLLM inference locally; open `/openapi.json`+/docs/+/redoc`.
Optional hardening: add LiteLLM `master_key` + forward Bearer from app.py; gate the 3 doc routes
behind `X-Api-Key`.

## AUTH VERIFIED BOTH DIRECTIONS (capstone pass, 5 passes total)
- No-key → 401 on every `/v1/*` (read + POST write routes). Valid key → 200.
- WRITE PROOF: `POST /v1/ledger` → 200 AND `ZBit_runtime/ledger/chain.json` block count
  incremented (grew to 5 blocks; tail idx4 = `audit_probe` from this investigation). Confirms the
  route is a REAL append, not an echo. Re-run the check with:
  `python -c "import json;c=json.load(open(r'C:\Users\zqmco\ZBit_api\ZBit_runtime\ledger\chain.json'));print(len(c),c[-1])"`
- Docs/openapi disclosure confirmed live: `/docs`,`/redoc`,`/openapi.json` all 200 unkeyed and
  render the full schema (incl. the 3 POST write routes). Loopback-only ⇒ low risk.
- LiteLLM chat proof: a `POST /v1/chat/completions` 200 is only real if `choices[0].message.content`
  is non-empty — verify the body, not just the status code.

## LEDGER STATE (final, persisted per "investigate fully")
- Primary: `C:\Users\zqmco\swarm\uvicorn8400\zbit8400_audit.db` — run_meta/services/probes=20/open_questions=5.
  Q1 (why did it start?) RESOLVED: manual bring-up via start_zbit.bat; the capstone log shows the
  intended authenticated workflow (read + ledger/generate writes with valid key). Q5 (open doc routes)
  carries the hardening recommendation.
- Sibling: `C:\Users\zqmco\swarm\uvicorn8400\litellm4001_audit.db` — probes=10/open_questions=4
  (separate service; do NOT merge into the primary db — see SKILL.md "investigate further" ledger rule).
- Scripts: `swarm\uvicorn8400\persist.py`, `persist_litellm.py`, `probe_process.ps1`.
