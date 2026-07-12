# Ollama Model-Service Inventory & Node Architecture (ZQM fleet)

Reference for reconciling the LLM model libraries across the Ollama nodes.
Companion script: `scripts/ollama_inventory.py` (re-runnable pull + reconciliation).

## The Ollama REST surface (no client binary needed)
Ollama exposes a plain HTTP API. From the bash terminal:
- `curl -s -m 8 http://<ip>:11434/api/tags` → JSON `{ "models": [ {name, model, size, digest, modified_at, details} ] }`
- `size` is bytes (convert ÷1e9 for GB). `digest` is the content hash — two models
  with the same name AND same size almost always share a digest (true duplicate).
- No `ollama` CLI required. Python `urllib` is enough (uses stdlib, no pip).

## Verified topology (live, 2026-07-10) — pin these
| Host | IP | Role | Models | GB |
|------|----|------|--------|-----|
| Node-4 | 192.168.1.215 | Central heavy-inference farm | 45 | 451.60 |
| Node-2 | 192.168.1.21  | Edge / generalist | 8  | 55.41  |
| Node-1 | 192.168.1.218 | Local dev / minimal | 2  | 29.16  |
| TOTAL | | | 55 installs / 51 distinct | 536.22 |

## Environment gotchas (the agent hit these — don't repeat)
- **MSYS `/tmp` is NOT writable** for shell `> /tmp/x` redirects (No such file or
  directory). Use `$HOME` (i.e. `C:\Users\zqmco`) for any output the agent writes.
  Python `os.environ["HOME"]` resolves correctly under the MSYS bash.
- `jq` is NOT installed in the sandbox — parse JSON with Python, not jq.
- The hosts are reachable from the agent sandbox (the agent and fleet are on the
  same LAN). A plain `curl`/`urllib` GET is sufficient; no tunneling needed.

## Reconciliation method (master table)
For each host: list `name | size_GB | family | unique?`.
"Unique-to-host? = N" when the model *name* also appears on ≥1 other node.
Cross-node map this session (exact, identical sizes):
- `qwen3.6:latest` — on ALL THREE (23.94 GB each) → 2 redundant copies
- `deepseek-r1:1.5b` — Node-4 + Node-2 (1.12)
- `nomic-embed-text:latest` — Node-4 + Node-2 (0.27)
- `qwen3:8b` — Node-4 + Node-1 (5.23)
Pure-duplication reclaim ≈ **54.5 GB** (≈10% of 536).

## GPU-tier inference (⚠ INFERENCE, not measured)
Deduce VRAM from *what a node stores / could serve*, never claim it's measured.
- Node-4 holds FOUR 70b-class weights (deepseek-r1:70b 42.52, llama3.1:70b 42.52,
  llama3.3:70b 42.52, qwen2.5:72b 47.42). One 70b fp16 needs ~43–48 GB weights →
  to serve all four concurrently implies ~160 GB (2×80) or ~192 GB (4×48) aggregate
  VRAM, or heavy CPU/RAM offload. → high-tier multi-GPU inference server.
- Node-2 largest model 23.94 GB → fits a single 24 GB card (RTX 3090/4090).
  → modest single-GPU tier.
- Node-1 23.94 + 5.23 → single 24–32 GB card. → light local-dev tier.

## Recommended roles
- Node-4 = central heavy-inference farm (single source of truth, only node with VRAM for 70b).
- Node-2 = edge/generalist (8-model daily-driver set, low-latency near users).
- Node-1 = local dev/minimal (qwen3.6 + qwen3:8b; both already on Node-4 → rebuildable centrally).

## Storage optimization playbook
1. Canonicalize ONE copy of each duplicate on Node-4 (frees ~54.5 GB). Keep edge
   copies only if offline operation is required (trades disk for LAN latency).
2. Prune redundant 70b-class: deepseek-r1:70b / llama3.1:70b / llama3.3:70b are all
   *exactly* 42.52 GB — rarely need all three resident. Pruning 1–2 frees 42.5–85 GB.
3. Embedding sprawl on Node-4 (5 models): keep one (bge-m3 or nomic) and prune rest (~2.1 GB).
   Effective footprint from 536 → ~400–440 GB with no capability loss.

## Node-2 unique/recent models — mirror to Node-4?
| Model | Size | Mirror? | Why |
|-------|------|---------|-----|
| gemma4:latest | 9.61 | YES | Newest Gemma; Node-4 stops at gemma3. Real gap. |
| hermes3:latest | 4.66 | YES | Distinct open-instruct voice vs Qwen/Llama defaults. |
| deepseek-coder-v2:16b | 8.91 | YES | Only DeepSeek-Coder in fleet; complements qwen2.5-coder. |
| llava:7b | 4.73 | SKIP | Node-4 already has llava:13b + llava-phi3. |
| phi3:mini | 2.18 | SKIP | Node-4 has phi3.5 + phi4 (newer). Superseded. |
Net: mirror gemma4 + hermes3 + deepseek-coder-v2:16b (+23.18 GB, fills 3 gaps).

## Default model flag
`qwen3.6:latest` (23.94 GB) is present and NEWEST on ALL THREE hosts — the only model
common to every node. Treat as the active fleet default; pin Node-4 as the authoritative copy.
