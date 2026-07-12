# Ollama Health Ops & Live-Fault Diagnosis (ZQM fleet, 2026-07-10)

Operational lessons from a live fleet investigation. NOT in the inventory/security
references — these are about KEEPING THE RUNNING SERVICE HEALTHY, not discovering it.

## 1. THE INFERENCE-WEDGE FAULT (most important — seen live 2026-07-10)
Symptom: `/api/tags` answers INSTANTLY (HTTP 200, ~0.2s) but `/api/generate` HANGS —
returns HTTP 000 (connection accepted, no data) even at 30–120s timeouts, on a model
that is ALREADY resident in `/api/ps`. This is NOT a network/auth problem and NOT
normal queue contention.
Root cause: the Ollama process / GPU VMM context is wedged (VRAM exhaustion, stuck
generation, or a bad state after a model load). A resident model that won't answer a
1-token request within a second is a hard fault.
Diagnosis rule:
  - tags OK + generate 000  => GPU/VMM stuck, NOT network. Restart the Ollama service
    on that node (`Restart-Service Ollama` / `ollama serve` restart) and re-test a tiny
    generate. Capture `nvidia-smi` + `ollama serve` logs if it recurs under load.
  - tags 000 entirely       => Ollama not listening (service down / port not bound).
  - 404 on generate         => model not present (normal), not a wedge.
  - 000 on generate AFTER a fresh model load on an empty node => the load itself is
    stalling; check VRAM headroom (a 70b-class model needs ~48 GB+ free VRAM).
Seen: Node-4 (192.168.1.215) AND Node-1 (192.168.1.218) both hung in the same window
while Node-2 (light, 8 models) stayed healthy. A `keep_alive: '-1'` config that keeps
every model resident is a LIKELY trigger (see chaining pitfall #1) — VRAM gridlock.

## 2. OLLAMA IS SINGLE-STREAM PER INSTANCE (design fact, confirmed)
One `/api/generate` runs at a time per Ollama process; concurrent requests QUEUE.
=> usable concurrency = number of SEPARATE Ollama instances, NOT GPUs.
=> A load-balancer across instances (LiteLLM) is what buys parallelism; adding GPUs to
   one instance does NOT make that instance serve N requests at once (it still serializes).
When you hammer one instance with competing requests while a big model is resident,
your tiny probes time out behind the queue — distinguish this from the wedge (rule #1):
if `/api/ps` shows a model resident and a SINGLE 1-token request to THAT model still
hangs, it's a wedge; if only competing requests time out, it's just queue ordering.

## 3. NO /health OR /metrics ENDPOINT
These Ollama builds return nothing useful on `:11434/health` and `:11434/metrics`
(HTTP 000/404). So:
  - LiteLLM's health checks rely on request success/failure, not a health endpoint — fine.
  - For watching, poll `/api/ps` per host (size_vram tells you VRAM pressure) on a timer;
    ALERT when a host answers `/api/tags` but NOT `/api/generate` (catches the #1 wedge
    automatically). This is the cheap external watcher recommended in INVESTIGATION_FINDINGS.md.

## 4. DEDUP-SAFETY PROOF BEFORE PRUNING (prune with confidence)
Before `ollama rm`-ing a "redundant" copy, PROVE the copies are byte-identical so you
lose zero capability. The digest field is the proof — but it is NOT in `/api/show`
in these builds (show returns `details.digest = None`). Get it from `/api/tags` instead:
  for each host: curl -s http://<ip>:11434/api/tags -> models[].digest
Then compare the digest strings per model name across hosts.
Verified 2026-07-10 (all identical across hosts):
  qwen3.6:latest      .215/.21/.218 = 07d35212591fc27746f
  deepseek-r1:1.5b    .215/.21       = e0979632db5a88d1a53
  nomic-embed-text    .215/.21       = 0a109f422b47e3a30ba
  qwen3:8b            .215/.218      = 500a1f067a9f782620b
=> safe to prune: keep one copy (recommend Node-4, the farm), rm the rest. ~54.5 GB freed.
LiteLLM keeps routing to the survivor. ZERO capability loss when digests match.

## 5. /api/ps IS DYNAMIC — always re-probe in the same turn
Models auto-load/unload on use, so a "loaded models" fact is point-in-time. If it
matters, run `/api/ps` in the SAME turn you report it and label it TIME-STAMPED. A
stale "/api/ps empty" from a subagent is almost always a snapshot, not ground truth.

## Reusable probe (one-shot health check per host)
curl -s -o /dev/null -w "tags=%{http_code} " http://<ip>:11434/api/tags
curl -s -o /dev/null -w "gen=%{http_code}\n" --max-time 15 -X POST http://<ip>:11434/api/generate \
  -H "Content-Type: application/json" -d '{"model":"<small-resident-model>","prompt":"x","max_tokens":1,"stream":false}'
# tags=200 gen=000  => WEDGE (rule #1). tags=200 gen=200 => healthy.
