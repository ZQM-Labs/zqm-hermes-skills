# LiteLLM ↔ Ollama fleet route-table validation

Reusable method for the recurring task: *"validate a LiteLLM proxy config against the
real N1/N2/N4 Ollama fleet — emit a WORKS/TIMEOUT/AUTH-FAIL table + flag config drift."*
Empirically observed 2026-07-11; verified against the Desktop 69-route config.

## 1. Reachability + inventory (prereqs)
Already covered in SKILL.md (4-part census). Snapshot the live `api/tags` of every node
you will probe BEFORE parsing the config — the drift diff is only meaningful against a
fresh inventory.

Node IPs (verified 2026-07-10/11): N4=192.168.1.215 (47 models), N2=192.168.1.21 (8),
N1=192.168.1.218 (2). All answered 200 on /api/tags this turn.

## 2. Parse the config — compare the REAL ollama tag, not the alias
LiteLLM `model_list` entries have TWO name fields:
- `model_name:` -> the **alias** clients call (e.g. `fast-chat`, `heavy-reasoning`,
  `embeddings`, `vision`, or a bare model tag).
- `litellm_params.model:` -> `ollama/<tag>` or `ollama_chat/<tag>` — the **real Ollama
  model** that must exist on `api_base`.

DRIFT-FALSE-POSITIVE TRAP: diff the `ollama/<tag>` value against the target node's
`/api/tags`. If you match on `model_name`, every alias (`fast-chat`, `embeddings`, ...)
falsely flags as drift. Parse with a regex:
```python
import re
blocks = re.split(r'(?=^- model_name:)', cfg_text, flags=re.M)
for b in blocks:
    name = re.search(r'model_name:\s*(\S+)', b)
    ip   = re.search(r'api_base:\s*http://(\d+\.\d+\.\d+\.\d+)', b)
    tag  = re.search(r'model:\s*ollama(?:_chat)?/([^\s]+)', b)
    # drift iff tag not in live_tags[ip]
```
Also run the REVERSE check: every model a node serves SHOULD have a route — report
uncovered models as coverage gaps. This session: 69 entries, 0 real drift, 0 coverage
gaps (full fleet mapped, no stale `:latest`).

## 3. Empirically probe sample routes
Type -> endpoint, with `Authorization: Bearer sk-na`:
- chat models (`ollama_chat/` prefix) -> `POST /api/chat`
- embeddings (`ollama/` prefix, embed models) -> `POST /api/embeddings`
- vision (`ollama/llava*`, `minicpm-v`, `moondream`, `qwen2.5vl`) -> `POST /api/generate`
  **with a base64 image**.

Minimal probe (stdlib, URL-based — never use raw `socket.recv()`, it hangs):
```python
import urllib.request, json
def probe(kind, ip, model, key='sk-na', tmo=120):
    url = f"http://{ip}:11434/{kind}"
    body = {"model": model, "stream": False}
    if kind == 'api/chat':        body["messages"] = [{"role":"user","content":"hi"}]
    elif kind == 'api/embeddings': body["prompt"] = "test"
    else: body["prompt"] = "describe"; body["images"] = [IMG_B64]
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
            headers={"Content-Type":"application/json","Authorization":f"Bearer {key}"}, method="POST")
    t = time.time()
    try:  r = urllib.request.urlopen(req, timeout=tmo); return (r.status, round(time.time()-t,1))
    except urllib.error.HTTPError as e: return (e.code, round(time.time()-t,1))
    except Exception: return (0, round(time.time()-t,1))   # 0 = timeout/conn error
```
Parallelize with `concurrent.futures.ThreadPoolExecutor(max_workers=14..20)` so one slow
cold-load doesn't serialize the sweep.

## 4. AUTH-LAYER DISAMBIGUATION (the #1 misread on this fleet)
Ollama itself on N1/N2/N4 requires **NO key** and **accepts any key**: no-key -> 200,
`sk-na` -> 200 (verified 3/3 retries on N1). So a `401 missing/invalid Bearer` does NOT
come from Ollama — it comes from the **LiteLLM proxy** `general_settings.master_key`
gate (client->proxy hop). Do NOT conflate:
- proxy->Ollama auth = none (sk-na fine)
- client->proxy auth = enforced by `master_key: ${LITELLM_MASTER_KEY}` in `.env`
This session PROVED a prior lead claim wrong ("N1 requires a key" / "401 on N1") — it was
a proxy-layer gate, not Ollama. Always surface machine truth vs prior claim as
PROVEN / NOT PROVEN / **UNRESOLVED**.

## 5. CONCURRENCY-SATURATION FALSE TIMEOUT (critical pitfall)
Firing many cold-load requests at N4 **simultaneously** (70b + 32b + vision together) may
return TIMEOUT/0 for models that are actually HEALTHY — limited VRAM serializes loads.
This session: every "timed-out" route re-passed 200 when probed ALONE. Rules:
- Probe big models (>=32b) **sequentially**, with generous timeouts: 32b~120s, 70b~300s.
- A 70b cold-load can take **256s** — far above the proxy's `router_settings.timeout:120`.
  Either raise the proxy timeout or set `keep_alive: '-1'` (warm pool) on heavy routes.
- Distinguish a true **500** from a timeout: `llama3.3:70b` returned 500 *in isolation*
  (genuine load failure on N4) — that's a real route defect, not a slow-cold-load timeout.

## 6. MALFORMED-IMAGE 400 TRAP (vision probes)
`/api/generate` vision probes with a 1x1 dummy PNG returned **400** (malformed image) —
NOT a route failure. Build a real small PNG in-memory (e.g. 32x32 solid color via
zlib) and base64-encode it; with a valid image every vision model returned 200. Use the
PNG-builder in `scripts/validate_litellm_routes.py`.

## 7. Verdict vocabulary
- WORKS: HTTP 200 (chat/embed/generate) with valid body.
- TIMEOUT: HTTP 0 / socket timeout — re-verify alone before labeling (see 5).
- AUTH-FAIL: HTTP 401/403 — on this fleet, means the *proxy* gate, not Ollama.
- DRIFT: ollama tag not served by target node (real config drift).
- COVERAGE GAP: served model with no route.

Full re-runnable sweep: `python scripts/validate_litellm_routes.py <config.yaml>`.
