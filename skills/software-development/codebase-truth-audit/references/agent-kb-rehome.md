# Re-home a dead-host-bound agent onto the REAL fleet

The agent's code/SOUL is usually bound to a host that no longer exists
(old IP, `D:\` paths, old username, fake hardware). You cannot run it as-is.
Build a thin API adapter that re-homes its IDENTITY + INTENTS onto the verified
fleet. Pattern proven live 2026-07-11 (ZBit agent -> ZQM Ollama fleet).

## Architecture
```
[client] -> [FastAPI :8400, localhost+TS only, X-Api-Key]
              |- /v1/models       -> fans out to Ollama /api/tags (N1/N2/N4/N3)
              |- /v1/generate     -> routes to LiteLLM (keep_alive TTL, NEVER -1)
              |- /v1/mesh/scan    -> wraps beacon.py discover (LAN port scan)
              |- /v1/ledger       -> READ-ONLY serve chain.json/merkle
              |- /v1/agent/status -> re-homed identity card (real Node-1 facts)
```

## Rules (non-negotiable)
- Bind `127.0.0.1` + Tailscale only. NO `0.0.0.0` public exposure.
- Require `X-Api-Key` header (env `ZBIT_API_KEY`). Reject missing/invalid.
- `/v1/ledger` + `/v1/mesh` are READ-ONLY. NO arbitrary exec, no file write
  outside an audited log dir.
- NO secrets from the old `hive_config.json` (dead `D:\` paths). Config comes
  from `config.yaml` env vars only.
- `/v1/generate` stays STUBBED (503) until LiteLLM is online.

## LiteLLM as the secure LB fabric
Install into a venv (isolated, reversible):
```
py -m venv venv && venv\Scripts\python.exe -m pip install "litellm[proxy]"
```
Config (keep_alive TTL, dummy key for local Ollama, localhost bind):
```yaml
model_list:
  - model_name: zbit-router
    litellm_params:
      model: openai/qwen3:8b
      api_base: http://192.168.1.218:11434/v1
      api_key: "sk-na"          # dummy; local Ollama needs SOME key field
      keep_alive: 5m            # TTL -- NEVER -1 (loaded-model memory leak)
  - model_name: zbit-heavy
    litellm_params: { model: openai/deepseek-r1:70b, api_base: http://192.168.1.215:11434/v1, api_key: "sk-na", keep_alive: 10m }
router_settings: { routing_strategy: least-busy, num_retries: 2 }
general_settings: { host: 127.0.0.1, port: 4000 }
```
Launch: `venv\Scripts\litellm.exe --config litellm_config.yaml --host 127.0.0.1 --port 4000`

## GOTCHA -- upstream Ollama 401
LiteLLM routes to Ollama, but if the fleet has `OLLAMA_API_KEY` set, EVERY
endpoint (even `/api/tags`) returns `401 unauthorized: missing/invalid Bearer
token`. The `openai/` provider needs `api_key: "sk-na"` (above) to stop its own
"Missing credentials" error, but the UPSTREAM 401 is a different wall: you need
the real Ollama API key in `litellm_params.api_key`. It is NOT in the shell env
and NOT in any readable local config (set at the Ollama service level). BLOCKER:
ask the user for it, or confirm where the service env lives. Do NOT brute-force.

## Verify before launch (no server started)
Import the FastAPI app with `fastapi.testclient.TestClient`; assert routes
registered, /health alive, /v1/agent/status shows re-homed identity, /v1/generate
returns 503 while LiteLLM unset, X-Api-Key enforces 401. Report as AD-HOC, not
suite green. (The `workspace-verification-status` + `fleet-council-audit`
"AD-HOC VERIFICATION" pattern covers the hermes-verify- temp-script form.)

## Verified fleet ground truth (this run)
N1 .218 -> 2 models; N2 .21 -> 8; N4 .215 -> 45 (heavy farm); N3 localhost -> 2.
Total 57 models. The agent's doc claimed "11 models ~60GB on HP host" = FICTION.
Bind the adapter to THIS, not the fiction.
