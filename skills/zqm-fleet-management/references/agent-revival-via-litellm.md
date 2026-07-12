# Agent Revival via API + LiteLLM over the Real Fleet

Class: re-homing a dead-host / archived agent (e.g. the ZBit/ZQM "Hermes" brain,
`C:\Users\zqmco\quarantine\CVG-CONTAMINATED-zbit-knowledge-base`) onto the LIVE
verified Ollama fleet through a localhost/Tailscale-only API layer. Built + run
live 2026-07-11. Reuse this shape; do NOT re-run the discovery from scratch.

## Why (the user's standing intent)
The user BUILDS agents (ZBit/ZQM). Their agents' memory/code is FIRST-PARTY —
treat as trusted, not "contaminated." A dead-host agent (its docs bind to a
fictional/old machine: HP Pavilion / 192.168.1.241 / "11 Ollama models") cannot
be RUN as-is. The correct revival is an API adapter that re-homes identity to
Node-1 + routes inference to the REAL fleet (N1 .218 / N2 .21 / N4 .215 / N3
localhost), NOT running its old host-bound modules.

## Architecture that worked (verified live)
- **LiteLLM proxy** (`litellm[proxy]`) in a dedicated venv at `ZBit_api/venv`.
  Serves OpenAI-compatible `/v1/chat/completions` with virtual model groups:
  - `zbit-router` = LB pool over OPEN nodes (N2 + N3 localhost)
  - `zbit-fast`   = N2 (deepseek-r1:1.5b etc.)
  - `zbit-heavy`  = N2 hermes3 (NOT N4's 70B — see pitfall #1)
  - N1 (.218) route is PRE-WIRED but COMMENTED (key-gated, see below).
- **ZBit API** = FastAPI (`ZBit_api/app.py`) bound 127.0.0.1:8400:
  `/health`, `/v1/models`, `/v1/generate` (→ LiteLLM chat/completions),
  `/v1/agent/status`, `/v1/ledger` (read-only chain.json), `/v1/mesh/scan`
  (beacon.py discover, read-only). X-Api-Key required (dotenv `.env`, chmod 600).
  No public exposure; Tailscale is opt-in.

## Exact working recipe
```bash
# 1. venv + litellm (real python, not the Store stub alias)
PY="C:/Users/zqmco/AppData/Local/Programs/Python/Python312/python.exe"
VENV="C:/Users/zqmco/ZBit_api/venv"
"$PY" -m venv "$VENV"
"$VENV/Scripts/python.exe" -m pip install -q "litellm[proxy]"
# 2. litellm_config.yaml — open nodes only + keep_alive TTL (NEVER -1)
# 3. launch proxy (background, silent)
"$VENV/Scripts/litellm.exe" --config litellm_config.yaml --host 127.0.0.1 --port 4001 > litellm.log 2>&1 &
# 4. pip python-dotenv into venv; write .env (ZBIT_API_KEY=$(python -c 'import secrets;print(secrets.token_hex(24))'), chmod 600)
# 5. launch API
"$VENV/Scripts/python.exe" -m uvicorn app:app --host 127.0.0.1 --port 8400 > zbit_api.log 2>&1 &
```

## CRITICAL PITFALLS (hit + solved live)
1. **N4 deepseek-r1:70b is COLD/UNLOADED → 120s timeout.** It's 45-model farm but
   the 70B isn't resident; first generate hangs forever. Route `zbit-heavy` to a
   smaller OPEN model (N2 hermes3 / deepseek-r1:1.5b) instead. Verify a node's
   actual `/api/tags` before pointing a route at a model it doesn't have.
2. **LiteLLM `/v1/completions` (legacy) 500s on chat models** (`KeyError:
   'prompt'`). The fleet models are chat-type. Use `/v1/chat/completions` with
   `messages=[{role:user,content:...}]` in the API's generate route, NOT
   `/v1/completions` with `prompt=`. (app.py was patched to match.)
3. **Ollama fleet AUTH is MIXED, not uniform.** Live probe 2026-07-11:
   N2/N3/N4 answer NO-AUTH; N1 (.218) returns **401** (key required). So route
   only to OPEN nodes and leave the key-gated node commented until the key is
   supplied. To unlock N1: set its `api_key` in litellm_config.yaml + the
   `OLLAMA_API_KEY` it expects (the user holds this; agent does NOT guess/brute).
4. **`keep_alive` TTL only — NEVER `-1`** (OOM risk on the 45-model farm). Use
   `5m`/`10m`. The old fleet-council skill's "keep_alive:-1 OOM" pitfall applies.
5. **Orphan proxy processes won't die from MSYS `taskkill` — and DON'T kill the
   wrong one.** Two traps hit live:
   - A background-launched `litellm.exe` becomes a console orphan; `tasklist | grep`
     + `cmd //c "taskkill /F /PID"` reports success but the PID persists (detached
     console child). Launch on a FRESH port (4001 vs a stale 4000) and leave the
     zombie; or use the `process` tool's `kill` on the KNOWN `session_id` of a
     process *you* launched (not a name-grep, which is ambiguous when many
     `python.exe`/`litellm.exe` PIDs coexist).
   - **Easy to kill the LIVE service instead of the orphan.** This session I meant to
     remove the :4000 litellm orphan but passed the wrong session_id and killed the
     running keyed ZBit API — then had to restart it. DISCIPLINE: before any
     `process kill`, confirm the target's port/role from `netstat -ano` output, not
     memory. Restarted API re-verified LIVE within the same turn. Harmless once
     caught, but avoid the wrong-PID kill.
6. **API dev-mode gap = real risk.** Initially `api_key:""` meant no auth. CLOSE
   it: generate a key, store in `.env` (chmod 600), inject `load_dotenv` into
   app.py, install `python-dotenv`. Verified: no-key→401, wrong-key→401,
   good-key→200+text.
7. **Regex PII false-positives in re-scrub verification.** A "leak" matcher can
   flag SHA256 hex containing `386` and `test@test.com` fixtures. Always DUMP the
   matched lines before declaring a leak; confirm real secrets (phone/email/NAS
   pw) vs coincidental strings.

## Verification (ad-hoc, not a suite)
After launch, hit the live endpoints: `/health` (litellm=True), `/v1/models`
(with key → 200; without → 401), `/v1/generate` (returns real fleet text),
`/v1/mesh/scan` (beacon discover → N hosts). Persist findings to SQLite
(`deployment_status` + `leak_locations` tables) per the user's standing
"findings land in SQLite" rule.
**GOTCHA — `/health` is INTENTIONALLY UNGAUTED (liveness check).**
A verification script that asserts `no-key /health → 401` is WRONG; expect 200.
Scope the auth-gate assertions to the DATA/ADMIN routes (`/v1/models`,
`/agent/status`, `/ledger`, `/generate`, `/mesh/scan`) — those MUST 401
without a key. This session a check script flase-flagged the whole API
"DEGRADED" because it expected `/health`→401; the API was fine, the
ASSERTION was the bug. Rule: when a green/red verdict looks wrong, re-read
your OWN test's expected-value, not just the code under test.
**Regex PII-trap:** an unescaped `(` inside a group (`(?:\+?1...)` is fine,
but a bare `\(?386\)?` is fine too — the failure mode is a `(` with NO
`?`/`(?:` prefix, which raises `re.error: missing ), unmatched`. Dump the
matched lines before declaring a leak; SHA256 hex containing `386` and
`test@test.com` fixtures are the two real false-positives seen.

## What stays untouched (user exclusion)
The raw `CVG-CONTAMINATED` quarantine + GDrive import are the LAST cred-bearing
copies (NAS pw `e5Bi6#g7*7qB3Zr$` + phones). User declined purge. Do NOT delete
them. Record their exact leak locations in SQLite (`leak_locations`) and only act
on explicit authorization. The runtime (`ZBit_api/`) carries NO plaintext secrets.
