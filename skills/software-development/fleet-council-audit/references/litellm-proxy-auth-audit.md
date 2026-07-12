# LiteLLM Proxy Auth / Exposure Audit (reusable recipe)

Live-verified 2026-07-11 against the ZBit fleet proxy on `127.0.0.1:4001`. Use this when a
council/deep pass surfaces a LiteLLM proxy (litellm-proxy process, `litellm --config ...`) and
you need to grade its auth posture + routing + exposure.

## What "no master key" means (decisive, not assumed)
LiteLLM's proxy has TWO auth gates:
- `general_settings.master_key` — set this → the proxy enforces per-request virtual keys.
- absent master key → LiteLLM starts in `INTERNAL_USER` mode. ALL requests are accepted with
  NO token. The startup log literally prints:
  `LITELLM_MASTER_KEY is not set! All requests will be treated as INTERNAL_USER with no admin access.`

So an empty/absent master_key is NOT a misconfiguration error — it is a wide-open inference
endpoint. Treat it as a finding, not noise.

## Probe sequence (each is a live verdict — run them, don't infer)
1. **Service up + liveness**
   `curl -s -m5 http://127.0.0.1:4001/`  → Swagger HTML (200)
   `curl -s -m5 http://127.0.0.1:4001/health/liveliness` → `"I'm alive!"`
2. **Model list with NO auth** (the discriminator)
   `curl -s -m5 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4001/v1/models` → 200 ⇒ open
   `curl -s -m5 -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer sk-1234" http://127.0.0.1:4001/v1/models` → still 200 ⇒ token ignored
3. **DECISIVE: real completion with no token**
   `curl -s -m60 -X POST http://127.0.0.1:4001/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"<model>","messages":[{"role":"user","content":"hi"}],"max_tokens":20}'`
   → HTTP 200 + valid `choices[].message.content` proves free inference works.
4. **Admin key-create (is it exploitable?)**
   `curl -s -m8 -X POST http://127.0.0.1:4001/key/generate -H "Content-Type: application/json" -d '{"models":["x"],"duration":"24h"}'`
   → If `500 ... DB not connected. This endpoint needs a database; set DATABASE_URL to a PostgreSQL`
   then virtual-key minting is NOT exploitable (needs Postgres). Record as "admin locked (no DB)",
   not "admin open".
5. **Confirm no master_key in config**
   `Select-String -Path <config>.yaml -Pattern 'master_key|general_settings'` → 0 matches = open.
6. **Routing map (what does it actually reach?)**
   `curl -s -m6 http://127.0.0.1:4001/model/info` → for each `model_name`, read
   `litellm_params.api_base` + `litellm_params.model`. This IS the backend map.
7. **Bind / exposure**
   `Get-NetTCPConnection -State Listen | ? LocalPort -eq 4001` → LocalAddress 127.0.0.1 = loopback-only
   (local exposure, NOT LAN). If `0.0.0.0`/`::` → LAN-exposed (escalate to CRITICAL).

## THE BENIGN WARNING PITFALL (do not "fix" these)
Startup logs emit lines like:
```
register_model: model=d78d0cf7ef59a90f09e9732d3804a420e9760bdf10e429c9abb0df958a13cabe
not in built-in cost map ... cache cost fields will default to 0.
```
These SHA256-looking model IDs are **LiteLLM's internal stable model IDs** = sha of the model
string (`hashlib.sha256("openai/deepseek-r1:1.5b".encode()).hexdigest()`). They appear in
`/model/info` as `model_info.id`. They are NOT config errors, NOT unknown backends, NOT a leak.
The warning is only about missing cache cost fields (cosmetic; add `cache_creation_input_token_cost`
/ `cache_read_input_token_cost` to `model_info` to silence). NEVER flag these as a finding.

## Cross-ref: proxy → backend → co-located service = lateral path
If `model/info` routes through an Ollama node that ALSO runs an unauth service (e.g. N2
192.168.1.21 has unauth Redis :6379 — requirepass empty, protected-mode off, bind empty),
the proxy is a lateral path: a local caller using the free proxy, or any foothold on the
backend node, can drive the Redis RCE. Grade the chain, not the proxy in isolation.

## Single-LEAD vs fan-out (when this was used)
For a SINGLE local service on the control-plane box, run this directly as the LEAD (not a
3-leaf council fan-out). A fan-out adds the leaf-429/silent-failure risk with zero extra
coverage for one localhost endpoint. Reserve fan-out for multi-node fleet inventory.

## Verdict lexicon
- `INTERNAL_USER` mode + loopback bind + no master key = MEDIUM (free local inference, no LAN reach).
- same + `0.0.0.0`/LAN bind = CRITICAL (any LAN host uses every model free).
- proxy routes to a node with an unauth critical service = escalate the chain to CRITICAL.
- companion gated API (:8400 ZBit, 401 on no/bad key) = the REAL auth boundary; note it as PASS.
