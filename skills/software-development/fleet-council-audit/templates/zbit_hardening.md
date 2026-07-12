# ZBit Stack Hardening (defense-in-depth)

The ZBit stack (see references/zqm-zbit-agent-topology.md) is FIRST-PARTY and
loopback-only, so both gaps below are LOW risk as deployed. They become real if the
bind ever widens off 127.0.0.1. Applied on the user's "proceed" (offered 2026-07-11,
not yet executed).

## Gap 1 — ZBit Agent API (:8400) open schema docs
FastAPI serves `/openapi.json`, `/docs`, `/redoc` UNKEYED even when /v1/* is key-gated.
They disclose the full route map incl. the authenticated POST write routes
(/v1/generate, /v1/ledger, /v1/skill/{name}).

Fix: decorate the three doc routes with the same `_check_key` (X-Api-Key header) used
on /v1/*. In app.py the schema routes are auto-mounted by FastAPI; gate them by
setting `app.openapi_url = None` + `app.docs_url = None` + `app.redoc_url = None`
UNLESS a valid key is present, OR wrap them. Simplest robust pattern:
```python
# after app = FastAPI(...)
@app.middleware("http")
async def _gate_docs(request, call_next):
    if request.url.path in ("/openapi.json", "/docs", "/redoc"):
        key = request.headers.get("x-api-key")
        if key != API_KEY:                       # API_KEY loaded from .env
            return JSONResponse(status_code=401,
                                content={"detail": "invalid or missing X-Api-Key"})
    return await call_next(request)
```
(401 matches the existing gate so clients get a consistent contract.)

## Gap 2 — LiteLLM proxy (:4001) open inference
No `master_key` in litellm_config.yaml ⇒ proxy runs in INTERNAL_USER wide-open mode;
`POST /v1/chat/completions` returns 200 with NO key and even with a bogus key
(verified live 2026-07-11). Loopback-only ⇒ local processes only, but unkeyed.

Fix A (proxy side): add to litellm_config.yaml
```yaml
general_settings:
  master_key: "sk-litellm-<long-random>"   # generate: python -c "import secrets;print('sk-litellm-'+secrets.token_hex(24))"
litellm_settings:
  ...existing...
```
Fix B (client side): have app.py forward `Authorization: Bearer <LITELLM_KEY>` when
posting to `{LITELLM_URL}/v1/chat/completions` (currently sends NO auth header —
see app.py line ~114). Add `LITELLM_KEY` to .env and a header in the requests call.

## Verify after applying
- `curl /openapi.json` (no key) → 401; (valid key) → 200.
- `curl -X POST /v1/chat/completions` (no key) on :4001 → 401; (Bearer valid) → 200.
- Both services stay loopback (netstat confirms 127.0.0.1 only).
- Re-read ZBit_runtime/ledger/chain.json to confirm authorized /v1/ledger writes still land.
