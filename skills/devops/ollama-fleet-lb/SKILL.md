---
name: ollama-fleet-lb
description: Deploy and operate a SECURE load-balanced Ollama fleet for ZQM — one
  authenticated LiteLLM gateway in front of the LAN-exposed Ollama instances (Node-1
  .218 / Node-2 .21 / Node-4 .215), with Open WebUI as the UI layer. Covers the real
  LiteLLM config, the mandatory security ordering (auth BEFORE exposure), keep_alive
  TTL discipline, and a live smoke test. Use when the user wants to actually BUILD
  the fleet fabric, not just profile it.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - homelab
    - ollama
    - litellm
    - open-webui
    - load-balancer
    - llm-gateway
    related_skills:
    - fleet-council-audit
    - ollama-recovery
    - openclaw-mesh
    - zqm-fleet-management
    - zqm-lan-node-reachability
    - zqm-local-setup
    - zqm-ollama-fleet
    - zqm-systems-review
---
# Ollama Fleet Load Balancer — Build & Operate

## When to use
- User asks to "chain the fleet", "build the LB", "one secure endpoint for all Ollamas",
  "stand up LiteLLM", "deploy Open WebUI over the fleet".
- You have the inventory (zqm-ollama-fleet) and now need to OPERATIONALIZE it.
- Any change to fleet routing, virtual keys, model_list, or firewall bind rules.

## CRITICAL — security ordering (NEVER skip a step)
Ollama has NO native auth and processes ONE request at a time per instance. The fleet
today is 3 open, unauthenticated, LAN-exposed endpoints. Do NOT expose the proxy to the
LAN until auth + backend lock-down are in place.

1. Stand up LiteLLM WITH a master key, bound to `127.0.0.1` on the proxy host.
2. Point ALL clients at the proxy (`:4000`), NEVER directly at `:11434`.
3. Firewall `:11434` on .218 / .215 / .21 so ONLY the proxy IP can reach it.
4. Router: confirm NO `:11434` WAN port-forward exists (verify, don't assume).
5. Only THEN consider joining Node-3 (.46, localhost-only today).
Result: "3 open unauth endpoints" → "1 authed gateway, backends locked to gateway IP".

## Topology (verified 2026-07-10)
- Node-1 = 192.168.1.218 (control plane; 2 models, ~29 GB; RTX4060 8GB — weak, offload heavy)
- Node-2 = 192.168.1.21 (8 models, ~55 GB)
- Node-3 = 192.168.1.46 (localhost-only Ollama; NOT in pool unless exposed)
- Node-4 = 192.168.1.215 (45 models / ~452 GB; natural proxy host — biggest, central farm)
All Ollama on `:11434`. Agent sandbox CAN reach 192.168.1.0/24.

## keep_alive discipline (MANDATORY)
- Pass `keep_alive` as a TTL string with units: `keep_alive: "5m"` (or "10m", "1h").
- NEVER use `-1` (infinite pin) for fleet models — it pins VRAM on a node forever and
  starves the load balancer's ability to shift load. The only exception is a single
  pinned embedding model you call constantly.
- LiteLLM `model_list` entries can set `litellm_params.keep_alive` per backend.

## Deploy (LiteLLM on Node-4)
`litellm_config.yaml` — expand the template to ALL real models you enumerated
(see references/ollama-fleet-chaining.md for the full design + the verified plan at
`C:\Users\zqmco\Desktop\Ollama_Fleet_Chaining_Plan.md`):
```yaml
model_list:
  - model_name: deepseek-r1-70b
    litellm_params: { model: ollama/deepseek-r1:70b, api_base: http://192.168.1.215:11434, keep_alive: "10m" }
  - model_name: fast-chat
    litellm_params: { model: ollama/qwen3:8b, api_base: http://192.168.1.215:11434, keep_alive: "5m" }
  - model_name: fast-chat
    litellm_params: { model: ollama/qwen3:8b, api_base: http://192.168.1.21:11434, keep_alive: "5m" }
  - model_name: fast-chat
    litellm_params: { model: ollama/qwen3:8b, api_base: http://192.168.1.218:11434, keep_alive: "5m" }
  - model_name: gemma4
    litellm_params: { model: ollama/gemma4:latest, api_base: http://192.168.1.21:11434, keep_alive: "5m" }
  - model_name: embeddings
    litellm_params: { model: ollama/bge-m3:latest, api_base: http://192.168.1.215:11434, keep_alive: "1h" }
router_settings:
  routing_strategy: simple-shuffle   # LiteLLM prod default for duplicate model_name pools
  num_retries: 2
  timeout: 60
  fallbacks: [ { fast-chat: [deepseek-r1-70b] } ]
```
Run (proxy host, Docker):
```bash
docker run -p 4000:4000 -v ./litellm_config.yaml:/app/config.yaml \
  -e LITELLM_MASTER_KEY=sk-master-$(openssl rand -hex 16) \
  ghcr.io/berriai/litellm:main --config /app/config.yaml
```
Bind 127.0.0.1 only first (swap `-p 4000:4000` for `-p 127.0.0.1:4000:4000`), then
open via the gateway after firewalling backends.

### Windows / no-Docker deploy (Node-1, VERIFIED 2026-07-11)
Docker isn't required. Use a dedicated venv + the `litellm[proxy]` extra:
```bash
PY="C:/Users/zqmco/AppData/Local/Programs/Python/Python312/python.exe"
"$PY" -m venv C:/Users/zqmco/ZBit_api/venv
"C:/Users/zqmco/ZBit_api/venv/Scripts/python.exe" -m pip install "litellm[proxy]"
# launch (long-lived → background, silent):
"C:/Users/zqmco/ZBit_api/venv/Scripts/litellm.exe" --config litellm_config.yaml --host 127.0.0.1 --port 4000
```
- `litellm` exposes NO `__version__` at top level — test with `import litellm; print(hasattr(litellm,'main'))` and `from litellm import proxy`, NOT `litellm.__version__`.
- Proxy binary is `venv/Scripts/litellm.exe` (also `litellm-proxy.exe`).
- **`python`/`python3` are broken MS-Store stubs on this host — always invoke `Python312\python.exe` by EXPLICIT absolute path.** A bare `python` alias fails (Store redirect / "can't open file").
- Proxy health check: `/v1/models` answers WITHOUT a master key (returns the configured virtual model groups); `/health` may time out if the proxy gates it — use `/v1/models` to confirm the config loaded.
- Set `LITELLM_MASTER_KEY` for production; without it the proxy logs "treated as INTERNAL_USER" and still serves (fine for localhost dev).

## Smoke test (PROVE, don't claim)
```bash
# virtual key
curl -X POST http://127.0.0.1:4000/key/generate -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" -d '{"models":["fast-chat"]}'
# chat through the gateway
curl http://127.0.0.1:4000/v1/chat/completions -H "Authorization: Bearer $VK" \
  -H "Content-Type: application/json" \
  -d '{"model":"fast-chat","messages":[{"role":"user","content":"ping"}],"keep_alive":"5m"}'
# health: confirm LiteLLM drops a dead node before a user request fails
curl http://127.0.0.1:4000/health/liveliness -H "Authorization: Bearer $VK"
```
Verify the response came back <5s and that `/health/liveliness` shows the expected
backends. If a backend is hung (see ollama-recovery), LiteLLM should mark it unhealthy —
cross-check with that skill.

## Open WebUI layer (UI only)
Point Open WebUI's `OPENAI_BASE_URL` at LiteLLM (`http://<proxy>:4000`), NOT at raw
`:11434`. OLLAMA_BASE_URLS multi-connection is session-scoped and NOT true LB — use
Open WebUI strictly as a UI on top of LiteLLM.

## Dedup AFTER chaining (transparent to clients via LiteLLM)
- `qwen3:6b` x3 → keep 1 on Node-4 (~-48 GB)
- dedupe `deepseek-r1:1.5b`, `nomic-embed-text`, `qwen3:8b` to 1 host each
- optionally drop 1–2 redundant 70B-class models on Node-4 (-42 to -85 GB) with zero
  capability loss if only one 70B runs at a time

## Pitfalls (debugged in-session)
- Exposing `:11434` before LiteLLM auth = full unauthenticated LLM access on the LAN.
- `-1` keep_alive pins VRAM and breaks LB shifting (see discipline above).
- Native Hermes gateway vs OpenClaw gateway both want `:18789` (see openclaw-mesh) —
  pin the Hermes gateway PORT or disable the OpenClaw task; ASK the user, don't guess.
- A hung backend (Node-1/Node-4 `/api/generate` HANG) looks like a LiteLLM fault but is
  GPU/VMM stuck — recover the node, don't rebuild the proxy.
- **Chat models REJECT the legacy `/v1/completions` endpoint** — routing `model: openai/<chat-model>`
  (e.g. deepseek-r1:1.5b, qwen3, hermes3) through LiteLLM's `/v1/completions` returns
  `500 KeyError: 'prompt'`. FIX: call `/v1/chat/completions` with `messages:[{role:user,content:...}]`,
  never `prompt`. Any app code wrapping LiteLLM must use chat/completions (debugged 2026-07-11:
  the ZBit API scaffold's /v1/generate initially used /v1/completions and 500'd; switched to
  chat/completions → works).
- **Fleet auth is MIXED, not uniformly open.** Live probe 2026-07-11: N2 (.21) + N3 (localhost)
  answer with NO auth; N1 (.218) returns 401 (key-gated at service level). So a LB can route
  generation through the OPEN nodes immediately WITHOUT the Ollama key — only gate the keyed node
  behind `api_key`. Don't block the whole fabric waiting on the key. N4 (.215) is reachable (HTTP 200
  on /api/tags) and serves 45 models — its large models are NOT "cold/dead"; the 000/timeout seen on
  a heavy route was a COLD-LOAD latency (model not kept warm), not a dead node. Fix = keep_alive TTL +
  health-check warmup so the first request after idle doesn't exceed the proxy timeout.
- **CORRECTION (2026-07-11, log-forensics):** an earlier note claimed "N4 deepseek-r1:70b is COLD
  and TIMES OUT — keep 70B out of the hot path." REFUTED by litellm.log + live probe: the zbit-heavy
  route that was failing TIMED OUT because its TARGET (N2 hermes3:latest, which IS present+warm) was
  cold-loaded on first hit, not because N4's 70B was dead. The 53 `AuthenticationError 401` lines in
  litellm.log were LITELLM PROXY-LEVEL (callers without the proxy's own master_key), NOT upstream Ollama
  401 — all upstream nodes accept the `sk-na` backend key (verified: N1/N2/N4 all 200 with sk-na). Lesson:
  diagnose route failures from the proxy error log (categorize timeout/500/401/exception), then PROVE the
  cause with a targeted live probe before rewriting routing policy. Don't retire fleet capacity on a guess.
- **CONFIG DRIFT is the norm, not the exception.** The RUNNING proxy used a minimal 3-alias config
  (ZBit_api/litellm_config.yaml, port 4001, no master_key) while a complete 69-route fleet config sat
  UNDEPLOYED on the Desktop (ollama-fleet/litellm_config.yaml — N4/N2/N1 routes + heavy/fast/embed/vision
  aliases + master_key). Before "improving integrations", diff the running config against the candidate
  configs on disk; the integration win is usually DEPLOYING what already exists, corrected for two blockers:
  (1) `master_key: ${LITELLM_MASTER_KEY}` aborts startup if the env var is unset — generate+set it;
  (2) 53 `keep_alive: '-1'` entries violate VRAM discipline — rewrite to 5m/10m TTL. Reuse a generator that
  reads the fuller config, injects a generated key, rewrites keep_alive, and keeps loopback-only.
- **DEPLOY A 'FULLER' CONFIG ONLY AFTER CHECKING FOR THE `prisma`/DB PREREQUISITE (verified 2026-07-11).** A full fleet config (e.g. Desktop/ollama-fleet/litellm_config.yaml, 69 routes) silently FAILS at LiteLLM startup with `ModuleNotFoundError: No module named 'prisma'` — it enables LiteLLM's DB/spend-tracking backend, which needs `prisma` (+ a Postgres/SQLite DB) that is NOT installed on a minimal host. The minimal running config works precisely because it disables DB features. SYMPTOM: `litellm.exe --config <full>.yaml` exits code 3 after printing the model list, with a deep `merged_lifespan` traceback that HIDES the real cause (the prisma import is buried under the lifespan recursion). BEFORE attempting to deploy a fuller config: (1) grep the candidate for `prisma`/database/sql settings; (2) confirm `prisma` is importable in the proxy venv (`python -c "import prisma"`); (3) if absent, either `pip install prisma` + provision the DB, or STRIP the DB-dependent settings. Don't deploy-and-discover — it takes the proxy DOWN (you then recover from .bak). The Q23 integration in this session is BLOCKED on this; recorded as F68.
- **LiteLLM `model_list` NESTS `model` + `keep_alive` INSIDE `litellm_params` (verified 2026-07-11).** Entries look like `{ model_name: x, litellm_params: { model: ollama_chat/llama3.3:70b, api_base: ..., keep_alive: '-1' } }`. A transform that filters on a TOP-LEVEL `entry.get("model")` or `entry.get("keep_alive")` will SILENTLY NO-OP — every check returns None/False and the script reports success while nothing changed. ALWAYS read `entry["litellm_params"]["model"]` and `.get("keep_alive")`. Round-robin GROUPS nest further: their entries have a `model_list` whose members are themselves `{litellm_params:{model:...,keep_alive:...}}` dicts. A config-transform MUST recurse into groups. Verify the transform by RE-LOADING the output and asserting the target is actually gone (`"llama3.3:70b" not in str(cfg)`), not by trusting the script's "done" print.
- **NEVER REGEX-PATCH A YAML CONFIG — USE DICT-SURGERY (verified 2026-07-11).** A first Q23 attempt used `re.sub` to inject `router_settings` and `keep_alive`; it corrupted structure (a duplicate/nested `router_settings` collided with the source's own block) producing the `merged_lifespan` recursion crash above. Rewrite the generator to `yaml.safe_load` the source, mutate the dict (drop entries, set TTL, inject master_key, set router_settings ONCE), `yaml.safe_dump`, then re-`safe_load` to prove it parses. This is the only safe way to edit a LiteLLM config programmatically.
- **OLLAMA ON WINDOWS IS A USER PROCESS, NOT A SERVICE (verified 2026-07-11).** `net stop ollama` / `net start ollama` FAIL ("service name not valid"). To restart: find the PID (`Get-Process -Name ollama`), `os.kill(pid, SIGTERM)`, then relaunch `ollama serve` (or `ollama app`) as the SAME user with the desired env. NOTE: killing the tray `ollama.exe app` may leave the `ollama serve` child alive and respawn — after a "restart" re-check `netstat -ano | grep 11434` for STALE PIDs still bound to 0.0.0.0 and kill them too. Persist config via USER env (`setx OLLAMA_HOST 127.0.0.1:11434` WITHOUT `/M`) — see elevation note below.
- **`setx ... /M` AND `schtasks /Create` NEED ELEVATION (verified 2026-07-11).** Setting a MACHINE env var (`setx X /M`) and registering SYSTEM scheduled tasks both fail non-elevated with "Access is denied" from a background/non-UAC shell. For a user-process config value (e.g. OLLAMA_HOST), use plain `setx OLLAMA_HOST ...` (user scope, no /M) — it persists for that user and needs no elevation. For supervision tasks, generate the task-XML (which natively supports `<RestartOnFailure><Count>3</Count>`) and hand the `schtasks /Create /TN ... /XML ...` command to the user to run elevated; the XML is the reviewable artifact, registration is gated. Don't loop the failed elevated call.
- **'cold model' vs 'dead node' — use the log, don't assume.** A route returning HTTP 000/timeout from
  the proxy is usually a COLD-LOAD (first request after idle exceeds the proxy timeout), cured by
  keep_alive TTL + a health-check warmup, NOT by removing the model from the LB. Verify the target model
  actually exists on the node (`curl /api/tags` lists it) before concluding a node is dead.
- **Stale background `litellm.exe` is hard to reap from MSYS** (taskkill reports success but the
  orphan persists; can't be reaped by the shell). Workaround: launch corrected config on a NEW port
  (e.g. 4001) rather than fighting the zombie on 4000. Note the zombie is harmless (other port).
- **'Read them all' + omnimap pattern**: when the user says "read them all", actually read every
  file's FULL content and emit a consolidated map artifact (e.g. ZBit_KB_READ_ALL.md,
  ZBit_KB_CODE_SURFACE.md) separating SELF-NARRATIVE/from-fiction vs VERIFIED-REALITY. Don't just
  count/list files. False-positive leak scanners: SHA256 hashes containing "386" and `test@test.com`
  fixtures are NOT real PII — tighten regex to exclude example/test domains before declaring a leak.
- **Local Ollama via the `openai/` provider needs a dummy `api_key`.** If your
  `litellm_params` uses `model: openai/<name>` + `api_base: http://<node>:11434/v1`,
  LiteLLM throws `Missing credentials. Please pass an api_key` even for keyless local
  Ollama. Add `api_key: "sk-na"` (any placeholder) to each backend entry. (The
  `ollama/<name>` provider form does NOT need this — but `/v1/completions` routing in
  this session used the `openai/` form against `:11434/v1`, which needed the dummy key.)
- **Ollama itself may be AUTH-REQUIRED (blocks generation until key supplied).** Even
  when `OLLAMA_API_KEY` is NOT in your shell env, Ollama can return
  `401 unauthorized: missing/invalid Bearer token` on `/api/tags`, `/api/generate`,
  and `/v1/completions` — the key is set at the Ollama SERVICE level, not your terminal.
  SYMPTOM: LiteLLM proxy comes up and `/v1/models` lists the groups, but every generation
  returns 401. FIX: obtain the real Ollama API key (service env / node config) and put it
  in each backend's `litellm_params.api_key`. Until then generation is BLOCKED — do not
  claim the fabric "works"; label it PROVEN-config / UNVERIFIED-generation. (Hit 2026-07-11:
  fleet returned 401 on every endpoint; key lived at service level, not readable shell-side.)

## Lightweight single-node LAN auth (token-gated reverse proxy)
When you only need to gate ONE node's Ollama on the LAN (not a full LiteLLM fleet fabric), a
stdlib-only Python reverse proxy is enough and avoids the Docker/LiteLLM footprint. Used live
2026-07-11 on Node-1 (.218):

- Bind Ollama to loopback only: set user env `OLLAMA_HOST=127.0.0.1:11434`, kill+restart `ollama serve`.
  Local callers keep no-token access on 127.0.0.1:11434 (verified HTTP 200).
- Run a token-gated proxy on the LAN IP :11434. LAN callers WITHOUT `Authorization: Bearer <tok>`
  get 401; WITH the token get 200. Verified: no-token=401, with-token=200, loopback=200.
- Token in `OLLAMA_PROXY_TOKEN` (or `OLLAMA_PROXY_TOKEN_FILE`, mode 0600). Upstream
  `OLLAMA_PROXY_UPSTREAM` (default 127.0.0.1:11434), bind `OLLAMA_PROXY_BIND` (LAN IP), port
  `OLLAMA_PROXY_PORT` (11434).
- REVERSIBLE: kill the proxy + unset OLLAMA_HOST + restart `ollama serve` → back to original open listener.
- Reusable script: `scripts/ollama_token_proxy.py` (no deps; stdlib http.server + urllib).
This is the minimal "close the no-auth exposure" for a single host. For multi-node routing/failover,
use the full LiteLLM fabric above (auth BEFORE exposure still applies).

## App-layer: the ZBit FastAPI keyed wrapper (VERIFIED 2026-07-11)
When wrapping LiteLLM behind a user-facing API (not just Open WebUI), the pattern that
worked and passed a full endpoint review:
- Bind **127.0.0.1 only** (Tailscale = opt-in later). No LAN/internet exposure.
- **X-Api-Key gate**: `REQUIRED_KEY = os.environ.get("ZBIT_API_KEY", cfg.get("api_key",""))`.
  If empty → dev mode (no gate). To lock: write key to `ZBit_api/.env`
  (`ZBIT_API_KEY=<token>`, `chmod 600`), inject `load_dotenv()` before CONFIG load
  (add `python-dotenv` to the venv), restart. Verified: no-key→401, wrong-key→401,
  good-key→200 on every data/admin route.
- **`/health` is the ONLY open route** (liveness check, by design). Do NOT gate it.
  A "no-key /health returns 200" is CORRECT, not a fault — your test assertion
  must expect 200 there, 401 on the rest. (A prior review wrongly flagged it 401-expected.)
- **Routes**: GET /health, GET /v1/models (per-node fleet census via /api/tags; a
  key-gated node surfaces `count=0` + no error — that's the proxy's auth 401, surfaced
  correctly, NOT a code bug), POST /v1/generate (→ LiteLLM /v1/chat/completions),
  GET /v1/mesh/scan (read-only beacon.py `discover`), GET /v1/ledger (read-only chain.json),
  GET /v1/agent/status (re-homed identity).
- **No arbitrary exec**: /v1/mesh/scan only runs a fixed read-only subcommand; /v1/ledger
  is read-only. The runtime carries NO plaintext secrets (NAS pw never enters the API;
  Ollama key env-injected; API key in .env chmod 600).
- **Generate route shape**: `{"model","messages":[{"role":"user","content":prompt}],"max_tokens","temperature"}`
  → LiteLLM `/v1/chat/completions`. Do NOT use `/v1/completions` (KeyError 'prompt' on chat models).
- **Kill-then-relaunch gotcha**: if you kill a background uvicorn/litellm to reload config,
  MAKE SURE you kill the live one (the PID from `process(action='list')` / the background
  session_id), NOT a different process. A mis-kill killed the live API while leaving the
  :4000 litellm orphan — restart is instant, but verify the right PID.
Reusable skeleton: `references/zbit_api_runtime.md`.

- **TWO SEPARATE PORTS — agent control ≠ LiteLLM proxy (PROBE TRAP).** `start_zbit.bat`
  launches BOTH services at once: the **LiteLLM proxy on :4001** and the **ZBit FastAPI app
  on :8400**. They are DIFFERENT services with DIFFERENT endpoints AND DIFFERENT auth headers:
    • **LiteLLM :4001** → serves ONLY `/v1/models` (the 3 virtual groups
      `zbit-router`/`zbit-fast`/`zbit-heavy`) and `/v1/chat/completions`. Auth:
      `Authorization: Bearer <key>` — and `/v1/models` answers even with NO key.
    • **ZBit app :8400** → serves `/health` (open, by design), `/v1/agent/status`,
      `/v1/mesh/scan`, `/v1/models` (per-node fleet census via /api/tags),
      `/v1/ledger`, `/v1/skills`, `/v1/generate` (→ LiteLLM /v1/chat/completions).
      Auth: `X-Api-Key: <key>` header — NOT Bearer.
  ⚠ **If you probe :4001 for `/v1/agent/status` or `/v1/mesh/scan` you get HTTP 404** — those
  endpoints LIVE ON :8400. An audit that conflates the two ports will wrongly report the agent
  endpoints as "missing/not found". Always hit **:8400 for agent control**, **:4001 for
  routing/chat**. (Verified live 2026-07-11: `:4001/v1/agent/status`→404;
  `:8400/v1/agent/status`→200 with `real_node: "Node-1 / 192.168.1.218 / ASUS Vivobook K6602VV"`
  and the FICTION disclaimer about the old HP/`.241` doc claims.)
- **Independent-audit recipe (prove, don't trust prior claims):** run these 4 live probes:
  1. Ollama fleet census — `curl -m10 http://<Nx>:11434/api/tags` per node (expect N1=401
     auth-gated, N2/N3/N4=200 with model counts). 2. LiteLLM :4001 `/v1/models` (3 virtual
     groups, no key) + `POST /v1/chat/completions {model:zbit-fast,...,max_tokens:8}`→200 text.
  3. ZBit :8400 `/v1/agent/status` (X-Api-Key) → confirms bound real node + FICTION note.
  4. ZBit :8400 `/v1/mesh/scan` (X-Api-Key) → `returncode:0` + host list. Label each number
     PROVEN from live output; flag any model that 000s on first call as COLD (N4 deepseek-r1:70b
     was COLD: HTTP 000 @25s; LB correctly avoids it — zbit-heavy routes to N2 hermes3).
  Live 2026-07-11 evidence + N3/localhost reconciliation note: `references/zbit-audit-evidence.md`.

## References
- `references/fleet-integration-workflow.md` (the "improve integrations" recipe: inventory-live → diff running vs candidate configs → close master_key/keep_alive blockers → validate+dry-run → deploy → verify)
- `references/ollama-fleet-chaining.md` (full design + verified plan path)
- `references/zbit_api_runtime.md` (app-layer FastAPI keyed wrapper + known-good litellm_config routing around the key-gated node; verify-the-gate recipe)
- `references/zbit-audit-evidence.md` (2026-07-11 independent live audit: fleet counts, :4001 vs :8400 split, agent FICTION disclaimer, COLD-model note)
- zqm-ollama-fleet (the inventory these routes are built from)
- ollama-recovery (when a backend hangs)
