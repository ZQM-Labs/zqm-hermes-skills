---
name: zqm-ollama-fleet
description: Profile and audit the ZQM homelab Ollama fleet — extract REAL model metadata
  (params/quant/context/architecture) via POST /api/show, measure per-host responsiveness,
  build best-model-per-task matrices, and reason about VRAM/footprint. Use when asked
  for a model capability/performance profile, a 'which model for X' matrix, Ollama
  model census, or VRAM/footprint implications across the homelab (Node-1..4, Gardens).
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - homelab
    - ollama
    - llm
    - model-profiling
    - capability-matrix
    - vram
    - lan
    related_skills:
    - ollama-fleet-lb
    - ollama-recovery
    - zqm-fleet-management
    - zqm-local-setup
    - zqm-systems-review
---
# ZQM Ollama Fleet — Model Profiling & Capability Audit

## When to use
- Build a "model capability & performance profile" or "best model per task" matrix for the ZQM Ollama fleet.
- Pull REAL metadata for models on a node (params, quantization, context length, architecture, format).
- Measure which Ollama host is most responsive (`curl` timing across Node-1/2/4).
- Reason about VRAM/footprint: which models need ~48GB+ VRAM, which are duplicated across nodes.
- Any Ollama `/api/tags`, `/api/show`, `/api/generate` work on the homelab LAN (192.168.1.0/24).

## CRITICAL: /api/show `details` block lies about params/context/arch
`POST http://<ip>:11434/api/show` returns a `details` block AND a `model_info` block.
For the GGUF imports on this fleet, the `details` block's `parameter_count`,
`context_length`, and `architecture` fields are **NULL**. The real values are in
`model_info` (the raw GGUF header map). Do NOT report the null `details` fields.

Authoritative key map (read from `model_info`):
- `general.architecture` → architecture string ("llama", "qwen2", "qwen3", "qwen25vl", "bert")
- `general.parameter_count` → float (e.g. 70600000000); divide by 1e9 for "B"
- `<arch>.context_length` → context window (e.g. `llama.context_length` = 131072)
- `details.quantization_level` → human quant string ("Q4_K_M", "F16") — RELIABLE, use this
- `details.format` → "gguf" — RELIABLE, use this
- `details.family` → usually equals `general.architecture`; use as arch fallback
- `details.parameter_size` → string like "8.3B" — fallback if `general.parameter_count` missing

Extraction snippet (full re-runnable version: `scripts/pull_ollama_meta.py`):
```python
import json, urllib.request
def show(host, name):
    req = urllib.request.Request(host+"/api/show",
        data=json.dumps({"model":name}).encode(),
        headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req, timeout=15))
d = show("http://192.168.1.215:11434", "deepseek-r1:70b")
det, mi = d["details"], d["model_info"]
arch = det.get("family") or mi.get("general.architecture")
pc = mi.get("general.parameter_count")
pc_str = f"{pc/1e9:.1f}B" if isinstance(pc,(int,float)) else det.get("parameter_size")
ctx = mi.get(f"{arch}.context_length") or mi.get("general.context_length")
print(pc_str, det.get("quantization_level"), ctx, arch, det.get("format"))
```
Run: `python scripts/pull_ollama_meta.py http://192.168.1.215:11434` (optional model args).

## Responsiveness timing (multi-host probe)
```
for ip in 192.168.1.218 192.168.1.215 192.168.1.21; do
  for i in 1 2 3; do
    curl -s -m 5 --output /dev/null --write-out "$ip connect=%{time_connect} total=%{time_total}\n" "http://$ip:11434/api/tags"
  done
done
```
PITFALL: `curl -s -o /dev/null -w '...'` can return **exit code 23** (write error) in
some MSYS/curl combinations even though timing values printed correctly. Do NOT treat
exit 23 as failure for a timing probe — trust the printed `%{time_connect}`/`%{time_total}`
numbers. Average the 3 runs per host; `time_connect` ≈ network proximity, `time_total`
≈ endpoint load + proximity (control-plane latency, NOT token throughput).

## LiteLLM config ↔ fleet route-table validation
When the owner asks to *validate a LiteLLM proxy config* (its `model_list`) against the
real fleet, emit a WORKS/TIMEOUT/AUTH-FAIL table + flag config drift. Full method +
auth-disambiguation + the false-timeout/malformed-image traps:
`references/litellm-config-validation.md`. Re-runnable drift + sampled-probe sweep:
`python scripts/validate_litellm_routes.py <config.yaml>`. Key gotchas baked into the
script/reference:
- Match on `litellm_params.model:` (`ollama/<tag>`), NOT `model_name:` alias — else every
  aggregate alias falsely flags as drift.
- Ollama needs NO key (sk-na or no-key both 200); a 401 means the **proxy** `master_key`
  gate, not Ollama. A prior "N1 requires a key" lead claim was disproven this way.
- Don't fire 70b+ loads concurrently — VRAM saturation yields false TIMEOUTs; probe ≥32b
  sequentially (70b cold-load ~256s). A 500 *in isolation* (e.g. llama3.3:70b) is a real
  route defect, not a slow cold-load.
- Vision probes need a valid PNG (build one in-memory) — a 1x1 dummy 400s as malformed.

## Topology facts (verified 2026-07-10)
- Node-4 = **192.168.1.215** — the heavy-inference host; carries the 70B quartet
  (deepseek-r1:70b, llama3.1:70b, llama3.3:70b ~42.5GB each; qwen2.5:72b ~47.4GB).
- Node-1 = **192.168.1.218** — local desk machine; most responsive on raw HTTP probe.
- Node-2 = **192.168.1.21** — mid-tier.
- All instruct/70B/32B models on this fleet are imported as **Q4_K_M** (4-bit) so 70B
  fits in ~42–48GB instead of ~140GB FP16. `bge-m3` is the only **F16** model
  (embeddings kept in float16 for retrieval fidelity; bert architecture, 0.6B).

## Fleet census & health check (4-part method) — READY-TO-RUN
When the owner asks for a "fleet-wide census & health check" / "for EACH node do X",
run the consolidated 4-part probe and emit REAL numbers (models/GB per node,
reachable vs not, which hang). Re-runnable one-shot: `python scripts/ollama_fleet_census.py`
(stdlib only; defaults to the 4 ZQM nodes). Full method + the localhost-bound
determination logic + the 2026-07-10/11 live result table:
`references/ollama-fleet-census-healthcheck.md`.
The four steps, in order, per node:
1. **Reachability** — `curl -s --max-time 5 http://<ip>:11434/api/tags` → HTTP 200
   = answering; **HTTP 000 / exit 28 = timed out = port NOT answering** (do NOT
   infer models).
2. **Inventory** — if reachable, parse `/api/tags` and sum the `size` bytes for GB
   + count (compute it; don't hand-count a long JSON blob).
3. **Generate / HANG test — CONTROL SHOT FIRST, then escalate. Do NOT skip the control.**
   This step is what separates a COLD-LOAD / thinking-model **false-hang** from a PERMANENT
   GPU/VMM **wedge** (the single most mis-diagnosed outcome on this fleet). Run ALL THREE
   shots, in order, on the node's default/largest model. Strip MSYS CRLF from the model
   name first (`echo $MODEL | tr -d '\r'`) or you get a bogus sub-0.1s 400, not a hang.
   (a) **CONTROL shot** — `POST /api/generate` with `options.num_predict:1`, `--max-time 15`.
       A **200 in <2s = node ALIVE** (model loads + emits one token). A failing control
       (000) ⇒ escalate before concluding; the node itself may still be wedged.
   (b) **FULL escalate** — same prompt, **NO num_predict cap**: `--max-time 20` first, then
       `--max-time 45` if it 000s. 000 at BOTH tiers WITH a *passing* control = **FALSE HANG**
       (thinking model emitting 100+ tokens of CoT, 25–50s), NOT a wedge. 000 at BOTH tiers
       WITH a *failing* control = real INFERENCE WEDGE.
   (c) **CORROBORATE** — bounded `num_predict:20` (`--max-time 60`) must return 200 with
       `eval_count:20, done_reason:"length"` (REAL tokens). A small non-thinking model
       (`mistral:7b`) should complete a full gen 200 in ~15s. Either proves NOT wedged.
   ⚠ FALSE-HANG TRAP: a SINGLE fixed-timeout probe mislabels slow models as hung.
   qwen3:32b / qwq:32b "thinking" models emit full chain-of-thought and will 000 a single
   45s shot while being perfectly healthy. Full re-runnable recipe + the live 2026-07-11
   case where this protocol **disproved a "permanent hang" lead claim** (N4 control 200@<2s,
   np:20 emitted real tokens, mistral full gen 200@14s): `references/ollama-hang-disambiguation.md`.
   **Reconciliation tags:** when re-verifying a prior claim, label each node PROVEN /
   NOT PROVEN / **UNRESOLVED** (your live machine truth contradicts the prior claim — surface
   BOTH, recommend a re-run, do NOT silently agree).
4. **localhost-bound determination** (only for nodes failing step 1) — ping the host
   (ICMP 0% loss = host up). host-up + :11434 LAN TCP-timeout ⇒ **NOT LAN-exposed**
   (localhost-bound). HONEST CAVEAT: an external probe can't prove 127.0.0.1-vs-firewall;
   state "NOT LAN-exposed (localhost-bound per intent)", not "PROVEN localhost-bound",
   unless you logged into the box. Always also spew the machine-truth (HTTP code,
   seconds) separately from the interpretation, and say "UNREACHABLE" PLAINLY — never
   necessarily assume a dark node's model list. Reconcile vs prior claims with PROVEN / NOT PROVEN /
   **UNRESOLVED** (UNRESOLVED = this turn's live machine truth contradicts the prior claim; surface
   BOTH and recommend a re-run rather than silently agreeing).  See references/ollama-hang-disambiguation.md.

## Stability / flapping dual-probe (counts stable across probes?)
When the owner asks whether reachable nodes' model counts are STABLE / not flapping,
run the endpoint TWICE (~5s apart) per node and compare `(model_count, total_GB)`.
Re-runnable one-shot: `python scripts/ollama_stability_probe.py [ip ...] [--gap 5]`
(defaults to the 4 ZQM nodes; prints Run1 / Run2 / STABLE|MISMATCH|UNREACHABLE).
Inline equivalent (MSYS bash, parallel per node):
  for ip in 192.168.1.218 192.168.1.21 192.168.1.215; do
    echo "=== $ip ===";
    curl -s --max-time 5 http://$ip:11434/api/tags | python -c "import json,sys; d=json.load(sys.stdin); print(len(d['models']), round(sum(m['size'] for m in d['models'])/1e9,2))";
    sleep 5;
    curl -s --max-time 5 http://$ip:11434/api/tags | python -c "import json,sys; d=json.load(sys.stdin); print(len(d['models']), round(sum(m['size'] for m in d['models'])/1e9,2))";
  done
PITFALL: parse count + total GB together — never hand-count a long /api/tags blob, and
`size` is in BYTES (divide by 1e9 for GB). Identical (count, GB) both runs ⇒ STABLE;
any drift ⇒ flapping (investigate Ollama reload / concurrent `ollama pull`).
When this is part of a multi-agent swarm run (swarm/YYYYMMDD_swarmN/blackboard.md),
log the result as a `### LEAF <X>` block under `## ROUND 1 FINDINGS`, resolve the
relevant Q (e.g. Q3 = stability), and state PROVEN. Full pattern + 2026-07-11 result:
`references/ollama-stability-swarm.md`.

## Verification discipline (ZQM standing rule)
Every number in a capability profile must come from a LIVE command this turn — never from
memory or a prior summary. Label each figure PROVEN (live output shown). The lead agent's
census is a claim until you re-pull. Pre-check reachability with a 1-line `curl -m 4
http://<ip>:11434/api/tags` (HTTP 200 = alive) before pulling metadata.

## Reference files
- references/ollama-api-show-profiling.md — full /api/show anatomy, key map, worked
  example JSON, and the null-details pitfall with reproductions.
- references/zqm-ollama-model-census.md — knowledge bank of REAL measured numbers from
  the 2026-07-10 profile (8 models' params/quant/ctx/arch/format, timing averages,
  duplication/VRAM findings). Condensed authoritative excerpts, not a full mirror.
- references/ollama-fleet-census-healthcheck.md — the 4-part census/health-check
  method (reachability → inventory → generate-hang test → localhost-bound determination),
  the ICMP+TCP disambiguation for dark nodes, and the 2026-07-10/11 live result table.
- references/ollama-hang-disambiguation.md — CONTROL-SHOT + ESCALATING recipe that
  separates cold-load/thinking false-hang from a real GPU/VMM wedge, with the 2026-07-11
  live case that disproved a "permanent hang" lead claim.
- templates/best-model-matrix.md — starter "best model per task" matrix to fill in.
- references/ollama-stability-swarm.md — dual-probe stability method, the count+GB
  parse one-liner, the swarm-blackboard LEAF logging convention, and the 2026-07-11
  live stability result table (N1/N2/N4 all STABLE).
- references/litellm-config-validation.md — how to live-validate a LiteLLM `model_list`
  against the fleet: drift-diff on the real `ollama/<tag>`, sampled /api/chat|embeddings|
  generate probes with `sk-na`, Ollama-vs-proxy auth disambiguation, concurrency false-
  timeout trap, malformed-image 400 trap, and the WORKS/TIMEOUT/AUTH-FAIL/DRIFT verdicts.

## Scripts
- scripts/pull_ollama_meta.py — re-runnable metadata extractor (host + model args).
  Prints a table of model | params | quant | ctx | arch | fmt using the model_info map.
- scripts/ollama_fleet_census.py — 4-part fleet census + health check (stdlib only).
  Run `python ollama_fleet_census.py [ip ...]`; defaults to the 4 ZQM nodes. Prints
  PROVEN/NOT-PROVEN verdicts and a plain UNREACHABLE line for dark nodes (never assumes
  their model list). Imports subprocess for the ICMP disambiguation.
- scripts/ollama_stability_probe.py — dual-probe stability check (stdlib only).
  Run `python ollama_stability_probe.py [ip ...] [--gap 5]`; defaults to the 4 ZQM
  nodes. Prints per-node Run1 / Run2 / STABLE|MISMATCH|UNREACHABLE. Use when the owner
  asks whether model counts are STABLE across repeated probes (no flapping).
- scripts/validate_litellm_routes.py — live-validate a LiteLLM config vs the fleet:
  drift diff (real ollama tag vs node /api/tags) + sampled /api/chat|embeddings|generate
  probe. Run `python validate_litellm_routes.py <config.yaml> [--key sk-na]`. Stdlib only.
