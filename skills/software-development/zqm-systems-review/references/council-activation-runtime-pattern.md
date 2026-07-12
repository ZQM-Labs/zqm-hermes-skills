# Council Activation Runtime Pattern

Confirmed behavior from activating `/tmp/ZQM-AI-Council` on ZQM-Node-1.

## Architecture manifest

When inspecting an unfamiliar council repo, read these files before launching:

- `README.md` — purpose and known-backend assumptions
- `service.py` — FastAPI app, routes, lifespan/startup hooks
- `council_engine.py` — councils, agents, backends, round logic
- `llm_client.py` — model registry, circuit breakers, supported backends
- `config.py` — model names, temperatures, timeouts, enable flags
- `board_*.json` — persisted board state; may contain stale topics
- `requirements.txt` — Python deps

## Routes confirmed on this host

| Route | Method | Purpose |
|-------|--------|---------|
| `/health` | GET | Service + backend health |
| `/council/topic` | POST | Set topic JSON `{"topic":"..."}` |
| `/council/round` | POST | Run one deliberation round |
| `/council/board` | GET | Return `topic`, `round`, `message_count`, `councils` |
| `/council/summarize` | POST | Summarize board |
| `/council/last` | GET | Return `messages[]` with `agentId`, `role`, `council`, `round`, `text`, `timestamp` |
| `/agent/chat` | POST | Stub on this repo |
| `/agent/tool` | POST | Stub on this repo |

Auth: `/tool` routes may require bearer/env gating when `ZQM_COUNCIL_TOKEN` is set; on this repo, `/health`, `/council/*`, `/agent/*` are unauthenticated.

## Degraded runtime pattern

Symptom: `/council/round` returns success with `total_turns=32` and `message_count=32`, but `/council/last` shows every message with `"text": ""`.

Root cause: backend generation timed out; the council engine recorded turns but stored empty responses instead of raising 500.

Verification order:

1. `GET /health` — expect `degraded` when backend is unavailable.
2. `GET /council/board` / `GET /council/last` — inspect `text` fields, not just `message_count`.
3. `POST http://127.0.0.1:11434/api/generate` with current model — if this times out, backend is the blocker.
4. `GET http://127.0.0.1:11434/api/tags` — inventory models.

## Ollama model-fit guard on 16 GB hosts

When the only installed model is a large file on a small-RAM host:

- Generation may time out even for `max_tokens=8`, `temperature=0.1`.
- The council service will swallow the timeout and produce empty deliberations.
- Check `parameter_size`, `quantization_level`, `context_length` from `/api/tags`.
- Prefer `qwen3:8b` or `gemma3:12b` Q4_K_M on 16 GB RAM.
- After model swap, re-run `/council/round`, then inspect `/council/last` `text` before declaring utilization successful.

## Startup sequence

1. `python -m py_compile service.py council_engine.py llm_client.py` from repo root.
2. Install only missing deps (`pip install fastapi uvicorn requests pydantic python-dotenv`).
3. Start: `python service.py` bound to `127.0.0.1:8000`.
4. Call `/health`; degraded without backend is expected.
5. Set topic, run round, inspect actual message text.

## State hygiene

`board_*.json` files persist across runs. After a stale topic causes confusion:

1. Inspect `board_*.json` before reuse.
2. Reset with `POST /council/topic` to overwrite board state.
3. Run `POST /council/round` to populate.
