# Fleet Integration Workflow ("improve systems integrations")

Reusable recipe for taking a minimal/incomplete LiteLLM fleet config to a full,
validated, load-balanced fabric — drawn from the ZQM-NODE-1 session (2026-07-11).

## Trigger
User says "improve integrations" / "chain the fleet" / "use the councils" on an
already-profiled fleet. The integration gap is usually NOT missing code — it's a
DEPLOYED-minimal config while a fuller candidate config sits undeployed on disk.

## Step 1 — Inventory what's actually live (prove, don't assume)
```bash
PY="C:/Users/zqmco/AppData/Local/Programs/Python/Python312/python.exe"
for ip in 192.168.1.218 192.168.1.21 192.168.1.215; do
  echo "== $ip =="
  curl -s -m 6 http://$ip:11434/api/tags | "$PY" -c "import sys,json;d=json.load(sys.stdin);print(' ',len(d.get('models',[])),'models')"
done
curl -s -m 6 http://127.0.0.1:4001/v1/models | "$PY" -c "import sys,json;print(' proxy serves:',[m['id'] for m in json.load(sys.stdin).get('data',[])])"
```
Capture per-node model counts + capability tags (embed/vision/reasoning) so the
routing decision is data-driven.

## Step 2 — Diff running config vs candidate configs on disk
Search for ALL litellm configs: `glob('C:/Users/zqmco/**/litellm*.yaml')`. In this
session THREE existed: the minimal `ZBit_api/litellm_config.yaml` (3 aliases, what
the running proxy used), a complete 69-route `Desktop/ollama-fleet/litellm_config.yaml`
(N4/N2/N1 + heavy/fast/embed/vision aliases + master_key), and a skill template.
The integration win = deploy the fuller one, corrected.

## Step 3 — Close the two real blockers before deploy
1. **master_key env unset** -> proxy aborts at startup. Generate a strong key
   (`secrets.token_hex(24)`), inject it, persist to `.env` + machine env
   (`setx LITELLM_MASTER_KEY <key> /M`). This ALSO closes the "proxy has no auth"
   security finding.
2. **keep_alive: '-1' (53x)** -> infinite VRAM pin, violates fleet discipline.
   Rewrite all to tiered TTL (`5m` fast, `10m` heavy). Regex:
   `re.sub(r"keep_alive:\s*'-1'", "keep_alive: 5m", t)`.

## Step 4 — Validate, then stage (dry-run default)
- Generate the target, parse with `yaml.safe_load` (assert OK), assert 0 `'-1'`
  remain, assert master_key injected, count routes preserved.
- Keep `server.host: 127.0.0.1` (loopback-only). Do NOT expose to LAN pre-auth.
- `--apply` only on user go: backup old config, copy target over it, set env,
  restart proxy (via supervision task or manual).

## Step 5 — Post-deploy verification
- `curl /v1/models` shows the new aliases.
- `POST /v1/chat/completions` on a heavy alias returns <5s (warmup working).
- Re-hash the claim ledger (if using fleet_swarm.db) to record closure.

## Gotchas (burned this session)
- **Bare `socket.recv()` gives false "unreachable"** — server doesn't push, recv
  blocks. Use `curl -m N -w "%{http_code}"` for HTTP; raw TCP only if you send-then-recv.
- **A route timeout (HTTP 000) is usually COLD-LOAD, not a dead node.** Verify the
  target model exists on the node (`/api/tags`) before dropping it from the LB.
- **401 in litellm.log is often PROXY-LEVEL** (callers without the proxy master_key),
  not upstream Ollama auth. Prove upstream auth with a live `sk-na` probe per node.
- **Config drift**: the running proxy may be launched with a CLI port override
  (`--port 4001`) that contradicts the file's `server.port: 4000`. Trust the live
  `/v1/models` response for "what's actually served".
- Reusable generator: a Python script that reads the Desktop 69-route config,
  applies blockers 1+2, merges router retries/fallbacks, emits a validated target.
