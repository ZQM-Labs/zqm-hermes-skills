---
name: ollama-recovery
description: 'Recover a hung ZQM Ollama node. THE /api/generate HANG fault: POST /api/generate
  HANGS (curl HTTP 000) while /api/tags returns instantly — GPU/VMM stuck, not network.
  BUT a SLOW model (qwen3:32b chain-of-thought) can take 25-50s and yield a FALSE 000@45s;
  always use ESCALATING timeouts (20s then 45s) before calling it a hard hang. Verified
  2026-07-11 LEAF B: N1=.218=401 auth-gated, N2=.21=HEALTHY (200@1.7s), N3=.46=unreachable
  from sandbox, N4=.215=HEALTHY-SLOW (200@35.8s, NOT hung). Covers the escalating-timeout
  cold-load-vs-hang diagnostic, the recovery recipe, and the MSYS CRLF pitfall that
  silently corrupts the generate payload into a bogus 400. Use whenever a node "won''t
  generate", a chat hangs, or a backend drops from LiteLLM.'
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - homelab
    - ollama
    - gpu
    - recovery
    - hang-fault
    - nvidia-smi
    related_skills:
    - fleet-council-audit
    - ollama-fleet-lb
    - openclaw-mesh
    - zqm-fleet-management
    - zqm-lan-node-reachability
    - zqm-local-setup
    - zqm-ollama-fleet
    - zqm-systems-review
---
# Ollama Node Recovery — the generate-hang fault

## When to use
- User says a node "won't generate", "chat hangs", "Ollama is stuck", or a model call
  times out while the host clearly answers `/api/tags`.
- LiteLLM marks a backend unhealthy / drops it from the pool.
- You see `HTTP 000` on `/api/generate` but instant `200` on `/api/tags`.

## THE FAULT (verified 2026-07-10/11)
- Affected: ANY LAN-exposed node can wedge — the hung node MIGRATES run-to-run.
  ALWAYS re-verify the specific node with the ESCALATING probe (STEP 1) before acting;
  never trust a prior node attribution. The 2026-07-11 LEAD headline "N4 hard hang /
  fault migrated N2→N4" was a FALSE POSITIVE (see FALSE-HANG below).
- Symptom: `/api/tags` instant; `/api/generate` HANGS → curl HTTP 000 (timeout).
- Root cause: GPU / VMM stuck (model loaded but the compute path wedged), NOT network,
  NOT auth, NOT WinRM. The Ollama service process is alive and answering tags.
- Node-3 (.46) is localhost-only and usually unaffected; Node-2 (.21) less prone.

## STEP 1 — ESCALATING TIMEOUT probe (cold-load vs PERMANENT hang) — READ THIS
A single `/api/generate` probe with one timeout is DANGEROUS: a slow large model can
exceed it and look like a hard hang. Use ESCALATING timeouts to tell a slow cold-load
from a permanent wedge. The re-runnable script is `scripts/escalating_generate_probe.sh`.
```bash
IP=192.168.1.215
M=$(curl -s -m 5 "http://$IP:11434/api/tags" | python -c "import json,sys;d=json.load(sys.stdin);print(d['models'][0]['name'])" | tr -d '\r')
# 1) first shot at 20s
curl -s -m 20 -o /dev/null -w "gen20=%{http_code} %{time_total}s\n" -X POST "http://$IP:11434/api/generate" \
  -H 'Content-Type: application/json' -d "{\"model\":\"$M\",\"prompt\":\"ping\",\"stream\":false}"
# 2) IF gen20=000, escalate to 45s
curl -s -m 45 -o /dev/null -w "gen45=%{http_code} %{time_total}s\n" -X POST "http://$IP:11434/api/generate" \
  -H 'Content-Type: application/json' -d "{\"model\":\"$M\",\"prompt\":\"ping\",\"stream\":false}"
```
Interpretation:
- `gen20=200` ⇒ HEALTHY (cold-load fine). Done.
- `gen20=000` then `gen45=200` ⇒ **SLOW COLD-LOAD, NOT a hang** (model just loaded slowly).
- `gen20=000` then `gen45=000` ⇒ **PERMANENT HANG / inference wedge** → proceed to recovery (STEP 2).
- `gen=400` with `<0.1s` ⇒ your JSON payload is MALFORMED (see CRLF PITFALL below), NOT a hang. Fix and re-probe before concluding anything.
- `gen=404` ⇒ model name wrong. `tags=401` ⇒ auth-gated (OLLAMA_API_KEY). `tags=000` ⇒ service/port down.

## FALSE-HANG — qwen3:32b chain-of-thought latency (critical)
- qwen3:32b (and qwq:32b "thinking" models) emit FULL chain-of-thought: a "ping" prompt
  still produces 100+ tokens, taking **25-50s**. A single 45s probe can catch a slow tail
  and return 000 → you'd wrongly declare a HARD HANG and bounce the GPU for no reason.
- Proof (2026-07-11 LEAF B, N4 .215, qwen3:32b, full gen): `gen20=000` → `gen45=200 @35.81s`
  (load 205ms; eval 25-35s). Same model with `num_predict:1` loaded+answered in **0.57s**
  — so the model/VRAM is FINE; only full-reasoning generation is slow.
- Rule: before calling ANY 32B+ "thinking" model hung, run the ESCALATING probe AND, if
  still ambiguous, a `num_predict:1` control shot. Fast control + slow full-gen = slow model,
  not a wedge.

## CRLF PITFALL (MSYS/git-bash — silent 400 misdiagnosis)
- On this Windows host, piping JSON through bash `read` (or process substitution) into a
  variable can append a trailing `\r` (CRLF). A model name like `qwen3:32b\r` makes the
  curl JSON body invalid → Ollama returns **400 in ~0.01s** (instant, not a hang).
- First symptom seen in-session: `gen=400 time=0.012s` while the model clearly exists.
- FIX: strip CR before building the payload — `M=$(... | tr -d '\r')` — and always pass
  `-H 'Content-Type: application/json'`. Re-probe; a real hang returns 000 (timeout), not 400.
- Never diagnose "hang" from a sub-0.1s 400. That's a payload bug, not the node.

## STEP 2 — recover the node (only after STEP 1 confirms a PERMANENT hang)
On the node itself (WinRM / OpenClaw / local PS). NEVER from the proxy host alone —
you must restart the Ollama service on the affected box:
```powershell
# restart the Ollama Windows service
Restart-Service -Name ollama -Force
# if GPU wedged, bounce the driver stack (nvidia-smi) — proven fix for the VMM stall
nvidia-smi --gpu-reset   # if supported; else:
# fallback: kill any zombie ollama_gpu processes, then let the service respawn
```
If `nvidia-smi --gpu-reset` is refused (display driver in use), a full Ollama service
restart is usually enough; the VMM releases on process exit. Wait ~10s for the service
to re-bind, then re-probe with STEP 1.

## STEP 3 — re-verify BEFORE declaring fixed
Re-run the ESCALATING probe. `gen20=` or `gen45=` must now return `200`. Only then tell
the user it's recovered. If it still hangs at 45s, the GPU may need a host reboot (escalate,
don't loop the restart).

## STEP 4 — single-stream guard (prevent recurrence)
Ollama processes ONE request at a time per instance. The hang is more likely under
concurrent load. Enforce:
- LiteLLM `num_retries: 2` + `timeout: 60` (already in ollama-fleet-lb config).
- Never fire parallel `/api/generate` at the same node from multiple clients.
- Keep `keep_alive` TTL (NOT `-1`) so VRAM churns and doesn't wedge (see ollama-fleet-lb).

## What this is NOT
- Not a LiteLLM bug — LiteLLM just surfaces it. Fix the node, not the proxy.
- Not a network/WAN issue — tags prove the pipe is fine.
- Not fixed by editing model_list — the backend itself is wedged.
- NOT a "hang" just because gen took 40s on a thinking model (see FALSE-HANG).

## References
- `scripts/generate_health.py` — reusable tags-vs-generate probe (single-shot; for the
  cold-load-vs-hang distinction use `scripts/escalating_generate_probe.sh` instead).
- `scripts/escalating_generate_probe.sh` — ESCALATING 20s→45s generate probe across
  N1/N2/N3/N4 with CRLF-safe model-name extraction. Re-runnable; prints HEALTHY /
  SLOW-COLD-LOAD / PERMANENT-HANG per node.
- `references/escalating-timeout-coldload.md` — the method, the qwen3:32b CoT gotcha,
  the CRLF pitfall, and the 2026-07-11 LEAF B result table proving N2/N4 are healthy.
- zqm-ollama-fleet (which hosts/models are affected; its STEP 3 hang-test should be
  read alongside this escalating method to avoid mislabeling slow models as wedged).
- ollama-fleet-lb (keep_alive discipline that reduces recurrence)
