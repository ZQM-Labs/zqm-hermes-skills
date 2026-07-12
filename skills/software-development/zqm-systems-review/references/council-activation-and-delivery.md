# Council Activation & Delivery Patterns

## Runtime activation sequence
1. Ensure Python deps are importable: `fastapi`, `uvicorn`, `requests`, `pydantic`, `python-dotenv`.
2. Start the FastAPI service from the repo root: `uvicorn.run(app, host='127.0.0.1', port=8000, log_level='info')`.
3. Probe `/health` first; degraded status without model backend is expected.
4. Set topic via `POST /council/topic`.
5. Run `POST /council/round`; capture round summary.
6. Inspect `GET /council/last` for actual message bodies, not just `message_count`.

## Empty-deliberation failure mode
- Symptom: `/council/round` returns `{"total_turns":32,"message_count":32}` but `/council/last` shows `"text":""` for every agent turn.
- Root cause: Ollama generation timed out mid-run; the council service stored empty turns instead of raising a 500.
- Diagnostic: directly probe `POST http://127.0.0.1:11434/api/generate` with the configured model; timeout here confirms the backend is the issue, not council routing.
- Fix path: pull a smaller Ollama model for this hardware before re-running `/council/round`.

## Model-fit check for local Ollama
Query `GET http://127.0.0.1:11434/api/tags` first:
- If `parameter_size` is large and Q4_K_M pushes the model file above ~15 GB on limited RAM/VRAM, expect generation timeouts on complex council topics.
- Prefer smaller models or lighter quantization on small-form-factor Windows hosts.
- Generation timeout on complex topics is not a council bug; it is a backend/model-fit issue.

## Detected issue on this host
- Ollama 0.31.2 installed and listening on `127.0.0.1:11434`.
- Only model available: `qwen3.6:latest`, Q4_K_M, ~23.9 GB, context_length=262144.
- Direct `api/generate` timed out during verification.
- Council service started successfully on port 8000, but deliberation produced empty message bodies.
