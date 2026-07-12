# ZBit Agent — Live Fleet & Infra Alignment Audit Evidence (2026-07-11)

Independent verification of the ZBit agent revival against REAL infra. Every number below is
from a LIVE command run this turn, not memory. Verdict: **ALIGNED** (agent disclaims its own
fictional doc claims and binds to the real fleet).

## 1. Ollama fleet census (live `curl /api/tags`)
| Node | IP | Result | Count |
|------|-----|--------|-------|
| N1 | 192.168.1.218 | **HTTP 401** (auth-gated) | not enumerable (key-gated at Ollama service level) |
| N2 | 192.168.1.21 | 200 | **8** (llava:7b, deepseek-r1:1.5b, nomic-embed-text, phi3:mini, deepseek-coder-v2:16b, qwen3.6, gemma4, hermes3) |
| N3 | 127.0.0.1 | 200 | **2** (qwen3:8b, qwen3.6:latest) |
| N4 | 192.168.1.215 | 200 | **45** (incl. deepseek-r1:70b, llama3.3:70b, qwen2.5:72b, etc.) |

Note: N1's 401 is the REAL host being key-gated — confirms `192.168.1.218` = live control-plane box.
N3 = `127.0.0.1` resolves to the Ollama running ON the proxy/agent host (Node-1), NOT a separate
LAN node. (Reconciliation flag: some older skills list a "Node-3 = 192.168.1.46 localhost-only";
in THIS deployment the agent's FLEET map binds N3 to 127.0.0.1. Treat the live /api/tags output as
ground truth, not the older IP.)

## 2. LiteLLM proxy (:4001)
- `GET /v1/models` (NO key) → `['zbit-router','zbit-fast','zbit-heavy']` ✅
- `POST /v1/chat/completions {model:zbit-fast, messages:[{role:user,content:'ping'}], max_tokens:8}`
  → **HTTP 200**, reply `"\n\nCould you clarify what"` ✅
- Config (`litellm_config.yaml`): zbit-fast + zbit-heavy → `http://192.168.1.21:11434/v1` (N2);
  zbit-router → N2 + 127.0.0.1 (N3). N1 is commented OUT of the LB.

## 3. ZBit agent control (:8400, `X-Api-Key` header)
- `GET /health` (open) → `{"status":"alive","host":"ZQM-NODE-1","fleet_nodes":["N1","N2","N4","N3"],"litellm":true}` ✅
- `GET /v1/agent/status` →
  `real_node: "Node-1 / 192.168.1.218 / ASUS Vivobook K6602VV"`,
  `note: "Re-homed from dead Amanda-Panda/DFORGE-11 (HP/.241). Old doc claims (11 models/HP) are FICTION; bound to real fleet."` ✅
  Runtime loaded; skills: base_convert, ledger_append/status, mesh_scan, qseal_* , qubit_measure.
- `GET /v1/mesh/scan` → `returncode:0`, **17 LAN hosts** discovered (port-443 beacon, read-only).

## 4. COLD model
- N4 `deepseek-r1:70b`: `POST /api/chat` → **HTTP 000 @25s timeout** (unloaded, COLD).
  N4 `qwen3:8b`: 200 @16.6s (warm-ish). LB avoids 70B on hot path → zbit-heavy → N2 hermes3.

## Audit-port lesson (carried into SKILL.md)
Agent control endpoints (`/v1/agent/status`, `/v1/mesh/scan`, `/v1/ledger`, `/v1/skills`) are on
**:8400** with `X-Api-Key`. LiteLLM (`:4001`) only knows `/v1/models` + `/v1/chat/completions`
with `Authorization: Bearer`. Probing :4001 for agent endpoints → 404 (false "missing").
