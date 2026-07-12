# ZBit + LiteLLM Stack Runbook (Node-1 control plane)
Class: launching, relaunching, and hardening the ZBit Agent API (:8400) +
LiteLLM proxy (:4001) on Node-1 (192.168.1.218). Condensed from the
2026-07-11 "improve the garden" session. The broader *why* (first-party
agent, mesh topology) is in `agent-revival-via-litellm.md`; this is the
OPERATIONAL runbook + the launch bugs that bit us.

## Launch (verified-working shape)
Both services are LOOPBACK-ONLY (127.0.0.1) — not a C2, not LAN-exposed.
The ZBit API is `uvicorn app:app`; LiteLLM is the `litellm[proxy]` exe.
Both run from their own `venv` (`C:\Users\zqmco\ZBit_api\venv`).

```bash
cd /c/Users/zqmco/ZBit_api
# LiteLLM — run the .exe DIRECTLY (see pitfall #1). Do NOT wrap in python.exe.
start "litellm" /min "C:/Users/zqmco/ZBit_api/venv/Scripts/litellm.exe" \
  --config litellm_config.yaml --host 127.0.0.1 --port 4001
# ZBit API
start "zbit" /min "C:/Users/zqmco/ZBit_api/venv/Scripts/python.exe" -m uvicorn app:app \
  --host 127.0.0.1 --port 8400
```
The `start_zqm_stack.bat` launcher in `ZBit_api/` does both; it is the canonical
one-shot. To self-heal after reboot, schedule it (see Reliability below).

## PITFALL #1 — `python.exe litellm.exe` -> `No module named litellm`
`venv\Scripts\litellm.exe` is a self-bootstrapping Windows PE (console launcher).
Invoking it AS AN ARGUMENT to another python (`python312\python.exe litellm.exe`)
fails: the outer python tries to import the `.exe` and the venv site-packages
isn't on its path -> `ModuleNotFoundError: No module named 'litellm'`.
FIX: run `litellm.exe` directly (it locates its own venv). `-m litellm` ALSO fails
(`litellm` is a package, no `__main__`). The `.exe` is the only correct entry.
Symptom this session: killed the old PID to apply a config edit, relaunch via
`python.exe litellm.exe` failed 3x; `litellm.exe` direct came up instantly.

## PITFALL #2 — `start /min` from git-bash detaches and DIES
`start "litellm" /min cmd /c "..."` launched from the agent's MSYS/bash terminal
spawns a console that dies with the shell -> :4001 goes NOT-LISTENING, no PID.
RELIABLE method = the agent `terminal(background=true)` call (tracks PID, keeps
alive). Use it for any long-running Windows process. `timeout 7 ...` will also
kill it after 7s — only for a quick liveness check, never for the real launch.

## PITFALL #3 — zbit-heavy 120s HARD-FAIL on cold N2 hermes3 load
`zbit-heavy` -> N2 (192.168.1.21) `openai/hermes3:latest`. LiteLLM's
`request_timeout`/`timeout` is UNSET by default -> it applies the 120s default.
N2 only keeps ~1 model warm (deepseek-r1:1.5b); hermes3 gets EVICTED.
A `zbit-heavy` call forces a cold hermes3 reload from disk > 120s -> stall/hard-500.
FIX (applied + verified live): in the `zbit-heavy` litellm_params block add
`timeout: 45` (bounds the stall) + `model_group_fallback: [zbit-fast]`
(reroutes to the fast node instead of failing). Before/after: POST zbit-heavy went
120s-hang -> 200 in ~2s. Combine with `keep_alive: 10m` TTL (N4 OOM risk
if `-1`, per `agent-revival-via-litellm.md` pitfall #4).

## Reliability / self-heal (gaps found)
- **No boot autostart for ZBit+LiteLLM.** Only `Ollama.lnk` + OpenClaw task
  auto-start; after a reboot the agent stack stays DOWN until manual launch.
  Fix = scheduled task `AtStartup` calling `start_zqm_stack.bat`. Script
  `apply_stability.ps1` does `Register-ScheduledTask` + sets sshd FailureActions
  (auto-restart x3). The task REGISTRATION needs ELEVATED UAC (background
  can't surface the prompt) — user must run it once as Admin. sshd recovery
  itself applies non-elevated and was verified set.
- **sshd auto-restart** — verified working (FailureActions present). Boot-race
  crash (post-reboot startup) is the known pattern; auto-restart covers it.
- **N2 Redis :6379 UNAUTH** — NOT covered by this stack, but it is the fleet's
  one true CRITICAL (pre-auth RCE + any-LAN-host can FLUSHALL). Separate fix
  path (`n2_redis_fix.ps1` + N2 break-glass cred). Also a reliability hazard.

## Genesis / intent (the "exposed on purpose?" question)
- **Ollama LAN-exposure (N1/N2/N4 :11434, no auth) = BY DESIGN.** The
  `litellm_config.yaml` comments state it: `Hot LB = N2 (open) + N3 localhost`,
  `N1 (.218) is key-gated (401) — kept behind api_key env until key supplied`.
  This is the ZBit distributed-inference mesh — first-party nodes talking to
  themselves on a private /24. NOT a C2, NOT drift.
- **N3 Ollama = intentional localhost-only** (127.0.0.1, not in the LB config).
  N1's Ollama route is COMMENTED OUT pending `OLLAMA_API_KEY`.
- **N2 Redis UNAUTH = ACCIDENTAL** (default config, no `requirepass`). The only
  true mistake in the fleet. Distinguish BY-DESIGN exposure from accidental every
  time the user asks "why is X open?" — read the service's OWN config comments
  before concluding drift.

## Verify (ad-hoc, not a suite) — MANDATORY after every edit
The Hermes environment flags every code edit as "unverified" until a fresh
behavioral check runs. Treat this as a HARD gate, not noise:
- After any launch/config change, re-probe the LIVE service before claiming done.
- Write a temp verify script to `$env:TEMP` (or /tmp) named `hermes-verify-<topic>-<date>.py`,
  run it, read the result, then `rm` it. Summarize as "ad-hoc verification",
  explicitly NOT "suite green". If verification is impossible, say the blocker — do NOT
  claim "fully verified".
- Pitfall this session: a verify script that CONCLUDES "applied: YES" from a
  substring match (`"FOUND" in "TASK_NOT_FOUND"` is True) is a LYING summary.
  Use `.startswith("TASK_FOUND")` for Yes/No verdicts. Always print the RAW line too.

## PITFALL — bash double-quote mangles inline Python in write_file
When `write_file` content contains `\"` (escaped double-quotes inside a Python
string literal), git-bash/MSYS may rewrite `\"` -> `"` on the way to the tool,
breaking the Python (`SyntaxError: f-string` / `\"...\"` collapse). Seen this
session on `redis_trace.py` + others. FIX: write Python with SINGLE-quote string
literals and `chr(10)`/`chr(13)` for newlines instead of `\n` escapes, or
use triple-quoted raw-ish strings. If a just-written `.py` throws on line 1, suspect
a quote-mangle and rewrite with single quotes before re-running. (Distinct from the
`powershell -Command` `$_` expansion trap — that's PS, this is Python-in-bash.)

## Re-probe checklist (do NOT trust a prior summary)
- `netstat -ano | grep ":4001|:8400"` -> both LISTENING 127.0.0.1.
- `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8400/v1/agent/status`
  -> 401 no-key (X-Api-Key enforced); `/health` -> 200 (intentionally open).
- `curl -s http://127.0.0.1:4001/v1/models` -> lists zbit-router/fast/heavy.
- POST `/v1/chat/completions` model=zbit-heavy -> 200 in <50s (not 120s hang).
- Redis (if touched): from N1 `socket` PING -> `NOAUTH` (was `+PONG` unauth pre-fix);
  authed `AUTH <pass>` PING -> `+PONG`. Confirms requirepass live.
