---
name: agent-service-log-audit
description: Deep-dive audit of a single service from its startup log (LiteLLM proxy, FastAPI agent API, etc.) — identify process+config, read source as auth contract, auth-bypass matrix, backend/routing map, fleet-exposure cross-ref, SQLite persist. LEAD-only shape (not a council fan-out).
---

# Agent / Service Log Audit (single-service deep-dive)

Use when the user pastes a server startup log and says "investigate further" / "investigate fully" on ONE service. This is the LEAD-only deep-dive shape — one local process, one box. Do NOT fan out: a 3-leaf batch would hit the leaf-429/silent-failure trap for zero extra coverage.

## SHAPE
1. **Identify the process** from its command line in the log + `Get-NetTCPConnection -State Listen` joined to `Get-CimInstance Win32_Process`. The cmdline yields the config path (e.g. `--config litellm_config.yaml --host 127.0.0.1 --port 4001`).
2. **Read the source/config as the AUTHORITATIVE auth + routing contract.**
   - FastAPI: find `_check_key()` / the header dependency. Note exact-match vs prefix; whether no-key-configured hard-refuses (503) or silently opens.
   - LiteLLM: check for `general_settings.master_key` / `LITELLM_MASTER_KEY` env. Absent ⇒ `INTERNAL_USER` (no auth). Log proves it: `LITELLM_MASTER_KEY is not set! All requests will be treated as INTERNAL_USER`.
3. **Live auth-bypass matrix** (bash `curl`, no key first):
   - `GET /v1/models` (no header) → 401 if gated, 200 if open.
   - lowercase `x-api-key: bogus`, `?api_key=bogus`, `Authorization: Bearer bogus`, empty `X-Api-Key:`, trailing-slash `/v1/models/`, `OPTIONS` preflight.
   - Capture any `Access-Control*` / `WWW-Authenticate` / header leakage on 401.
   - FastAPI default: `/docs` + `/redoc` + `/openapi.json` are OPEN (no key) → schema disclosure (LOW). Close with `app = FastAPI(docs_url=None, redoc_url=None)`.
4. **DECISIVE inference probe** (only if no-auth suspected): POST a real completion with NO token. HTTP 200 + valid body = free inference confirmed.
5. **Map backends/routing**: `GET /model/info` (LiteLLM) or `/v1/models`. Hash-named model WARNINGs = LiteLLM's internal stable model IDs (sha of the model string) — BENIGN, not a config error.
6. **Cross-ref fleet exposure**: each backend the service routes to is a lateral path. Re-probe them (N2 unauth Redis `+PONG` → RCE primitive; N1 Ollama open → LAN exposure). A prior "key-gated" baseline may be STALE — always re-verify live.
7. **Persist / EXTEND SQLite**: add rows to `nodes`/`probes`/`findings`/`open_questions`/`swarm_log`. DISCLOSE any MUTATION you perform during a write-surface test (e.g. a `/v1/ledger` POST that appends a real block — reversible).
8. **LEAD re-verify gate**: every PROVEN tag traces to a live command the lead ran.

## PROBE RECIPES (bash)
- Proxy no-auth inference:
  `curl -s -m60 -X POST http://127.0.0.1:4001/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"zbit-fast","messages":[{"role":"user","content":"hi"}],"max_tokens":20}'`
- Redis unauth (file-driven python to dodge MSYS `C:\c\` path doubling):
  socket `PING` → `+PONG`; `CONFIG GET requirepass|protected-mode|bind` (empty/0 = CRITICAL RCE primitive).
- Authenticated surface probe without printing the key: load `.env` via python-dotenv, set `X-Api-Key` from `os.environ["ZBIT_API_KEY"]`, never `print()` the value.

## GOTCHAS
- FastAPI `/docs` `/redoc` open by default — schema leak, trivially closed.
- LiteLLM without `master_key` = wide-open inference; loopback bind limits exposure to localhost but any local process/user gets free use.
- "investigate further" = DEEPEN the named service, not a fresh fleet council.
- Prior-session state (key-gated nodes, disabled ports) is BASELINE, but RE-VERIFY — this session found N1 open despite a "key-gated" claim, and corrected a prior "OpenClaw :18789 down" claim (it was UP).
- Use the proxy's own `/model/info` to reconcile "hash-named" warning models — they map 1:1 to `model_info.id`.
