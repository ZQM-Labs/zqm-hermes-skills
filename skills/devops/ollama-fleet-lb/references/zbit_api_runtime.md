# App-layer runtime on top of the LiteLLM fleet fabric

Proven recipe from the 2026-07-11 ZBit agent revival. The LiteLLM proxy is the
gateway; this is the FastAPI layer that wraps it for an agent/API consumer, with
a real auth gate (not dev-mode).

## Known-good litellm_config.yaml (open nodes only; keyed node pre-wired)
Mixed-auth reality: N2(.21) + N3(localhost) answer with NO Ollama key; N1(.218)
is 401 key-gated at the service level; N4(.215) is reachable but deepseek-r1:70b
is COLD and times out. Route the hot LB over open nodes; keep 70B out until loaded.
```yaml
model_list:
  - model_name: zbit-router            # LB across OPEN fleet
    litellm_params: { model: openai/deepseek-r1:1.5b, api_base: http://192.168.1.21:11434/v1, api_key: "sk-na", keep_alive: "5m" }
  - model_name: zbit-router
    litellm_params: { model: openai/qwen3:8b, api_base: http://127.0.0.1:11434/v1, api_key: "sk-na", keep_alive: "5m" }
  - model_name: zbit-fast
    litellm_params: { model: openai/deepseek-r1:1.5b, api_base: http://192.168.1.21:11434/v1, api_key: "sk-na", keep_alive: "5m" }
  - model_name: zbit-heavy             # N2 hermes3 (open), NOT N4 cold 70B
    litellm_params: { model: openai/hermes3:latest, api_base: http://192.168.1.21:11434/v1, api_key: "sk-na", keep_alive: "10m" }
  # N1 key-gated — uncomment + set real Ollama key once supplied:
  # - model_name: zbit-router
  #   litellm_params: { model: openai/qwen3:8b, api_base: http://192.168.1.218:11434/v1, api_key: "<OLLAMA_KEY>", keep_alive: "5m" }
litellm_settings:
  request_timeout: 120
  num_retries: 2
  routing_strategy: "least-busy"
server: { host: 127.0.0.1, port: 4001 }   # fresh port if a stale :4000 zombie persists
```
Launch: `venv/Scripts/litellm.exe --config litellm_config.yaml --host 127.0.0.1 --port 4001`
Confirm via `GET /v1/models` (lists virtual groups; `/health` may gate/timeout).

## FastAPI keyed wrapper (X-Api-Key gate, dotenv-loaded, 401 on miss/wrong)
```python
import os, yaml
from pathlib import Path
from fastapi import FastAPI, Header, HTTPException
import httpx

CONFIG = yaml.safe_load((Path(__file__).parent/"config.yaml").read_text())
try:                                        # load .env so ZBIT_API_KEY is set
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent/".env")
except Exception: pass
REQUIRED_KEY = os.environ.get("ZBIT_API_KEY", CONFIG.get("api_key", ""))
LITELLM_URL  = CONFIG.get("litellm_url", "")

app = FastAPI()

def _check_key(x_api_key: str | None = Header(None)):
    if not REQUIRED_KEY: return                 # dev mode only; close before exposure
    if x_api_key != REQUIRED_KEY:
        raise HTTPException(401, "invalid or missing X-Api-Key")

@app.post("/v1/generate")
def generate(p: dict, x_api_key: str | None = Header(None)):
    _check_key(x_api_key)
    if not LITELLM_URL: raise HTTPException(503, "LiteLLM not configured")
    body = {"model": p.get("model","zbit-router"),
            "messages":[{"role":"user","content":p.get("prompt","")}],
            "max_tokens": p.get("max_tokens",400), "temperature": p.get("temperature",0.7),
            "stream": False}
    try:
        r = httpx.post(f"{LITELLM_URL}/v1/chat/completions", json=body, timeout=120)
        return r.json()
    except Exception as e:
        raise HTTPException(502, f"LiteLLM error: {e}")
```
Key mgmt: `secrets.token_hex(24)` -> write `ZBit_api/.env` with `0600` perms.
Boot keyed: `uvicorn app:app --host 127.0.0.1 --port 8400`.

## Verify the gate (PROVE, don't claim) — working probe recipe
Run these from the real `Python312\python.exe` (bare `python` is a Store stub):
```python
import urllib.request, json
B="http://127.0.0.1:8400"
KEY=open(r"C:\Users\zqmco\ZBit_api\.env").read().strip().split("=",1)[1]
def hit(method,path,body=None,key=None):
    h={"Content-Type":"application/json"}
    if key: h["X-Api-Key"]=key
    req=urllib.request.Request(B+path,data=(json.dumps(body).encode() if body is not None else None),headers=h,method=method)
    try: return urllib.request.urlopen(req,timeout=90).status
    except urllib.error.HTTPError as e: return e.code
print("no-key   GET /v1/models      ", hit("GET","/v1/models"), "(want 401)")
print("wrong-key GET /v1/models      ", hit("GET","/v1/models",key="deadbeef"), "(want 401)")
print("good-key  GET /v1/models      ", hit("GET","/v1/models",key=KEY), "(want 200)")
g=hit("POST","/v1/generate",{"model":"zbit-router","prompt":"ping"},key=KEY)
print("good-key  POST /v1/generate   ", g, "(want 200; text warms on retry if empty 1st hit)")
```
- no-key -> 401, wrong-key -> 401, good-key -> 200 = gate CLOSED (proven).
- First generate call after a cold proxy may return empty `content` — retry; that is
  a cold-load artifact, NOT a code fault (proven this session: warmed call returned full text).

## Ad-hoc verification gate (coding-system requirement)
When you edit app.py / config / litellm_config, the workspace flags "unverified"
and demands a focused temp-script check. Pattern that satisfies it WITHOUT claiming a
suite green:
- Write a throwaway verifier to `%TEMP%` with a `hermes-verify-` filename prefix
  (e.g. `hermes-verify-zbitapi-*.py`), run it against the CHANGED behavior
  (hit the live routes / parse the config), and clean it up (`os.unlink`) after.
- If YOUR assertion expressions are buggy, the check may show false "FAIL" rows —
  prove the files are correct with a DIRECT read (e.g. `grep -n`/file read) rather
  than trusting a malformed boolean. Report it explicitly as AD-HOC, not "tests pass".
- This is NOT a CI run; there is no canonical test command for the scaffold.

## Re-scrub leak regex (tighten to kill false-positives)
When scanning cleaned zips for surviving PII, a naive `(?i)\d{3}-\d{3}-\d{4}` or
`@...` pattern FALSE-POSITIVES on (a) SHA256 hex containing "386" and
(b) `test@test.com` fixtures. Use a tightened pattern and exclude example/test
domains before declaring a leak:
```python
REALPAT = re.compile(r'(?i)(?:\+?1[\s.\-]?)?\(?386\)?[\s.\-]?\d{3}[\s.\-]?\d{4}'
    r'|azelenski|e5bi6|9\d{2}[-\._]\d{3}[-\._]\d{4}'
    r'|[a-z0-9._%+\-]+@(?!redacted|test@|example\.|localhost)[a-z0-9.\-]+\.[a-z]{2,}')
# and skip lines already containing 'REDACTED'
```
This session: two "LEAK" flags on cleaned zips were these false-positives; the
zips were in fact CLEAN (0 real-PII lines). Always dump the matched lines as
evidence before reporting a leak.

## Persist findings to SQLite (investigate-fully closure)
The council sweep landed its verdict in `ZBit_council_findings.sqlite` with tables:
meta, zips, leaks, contradictions, json_failures, fleet_checks, old_host_refs,
deployment_status, leak_locations. Reusable pattern: one row per finding, plus a
`deployment_status(k, v, ts)` kv table for live state, and `leak_locations` for
precise PII coordinates.

## Pitfalls specific to the app layer
- dotenv must be installed in the venv: `python -m pip install python-dotenv`.
- `/v1/generate` MUST hit LiteLLM's `/v1/chat/completions` (chat models reject
  legacy `/v1/completions` -> 500 `KeyError: 'prompt'`).
- Dev-mode (empty REQUIRED_KEY) is a real security gap — close it (set key) before
  any LAN/Tailscale exposure. The 401 gate is coded; just supply the key.
- MSYS `python -m venv` can fail silently / `&&` chaining drops the next command;
  invoke the REAL interpreter by explicit absolute path and check exit per step.
