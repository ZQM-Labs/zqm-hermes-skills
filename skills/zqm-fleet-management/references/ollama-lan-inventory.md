# Ollama LAN Inventory — Verified (2026-07-10)

## Hard-learned pitfall (FIRST-CLASS)
The user runs **Cline** (a separate AI agent) and pastes its output into chat.
Cline's Ollama report was **FALSE on two material points**:
  - claimed only **2** Ollama hosts on the LAN (actual: **3**),
  - claimed `192.168.1.21` is a **DNS alias of `192.168.1.215`** (actual: **distinct
    machine** — their model lists are disjoint except 3 shared models).
RULE: treat ANY pasted / Cline / secondhand infra output as UNVERIFIED. Re-probe live
(`curl /api/tags`) before trusting or reporting it. The agent's own sandbox terminal CAN
reach `192.168.1.0/24` (got real HTTP 200), so there is no excuse to forward Cline's numbers.

## Verified endpoint census (live /api/tags from sandbox)
| Host | Role | Models | Size | Reachable |
|------|------|--------|------|-----------|
| 192.168.1.218 | Local / Node-1 (desk) | 2 | 29.2 GB | yes (200) |
| 192.168.1.215 | ZQM-Node-4 | 45 | 451.6 GB | yes (200) |
| 192.168.1.21  | ZQM-Node-2 | 8 | 55.4 GB | yes (200) |
| 192.168.1.46  | ZQM-Node-3 | — | — | **no Ollama** (000) |
| 192.168.1.173 | Synology GARDEN-01 | — | — | no Ollama |
| 192.168.1.40  | Synology GARDEN-02 | — | — | no Ollama |
| all other /24 | — | — | — | no Ollama |

Full /24 port scan on :11434 returned ONLY .218, .215, .21.

## Node-4 (192.168.1.215) — 45 models / 451.6 GB (the heavy farm)
Reasoning: deepseek-r1 (1.5b,7b,8b,14b,32b,70b), qwq:32b.
Chat: qwen3 (0.6b,1.7b,4b,8b,14b,32b), qwen3.6:latest, qwen2.5 (1.5b,3b,7b,14b,72b),
llama3.1 (8b,70b), llama3.2 (1b,3b), llama3.3:70b, mistral:7b, mistral-nemo:12b,
mixtral:8x7b, phi3.5, phi4, gemma2:9b, gemma3 (4b,12b).
Coder: qwen2.5-coder (7b,14b,32b). Vision: llava:13b, llava-phi3, minicpm-v, moondream,
qwen2.5vl (3b,7b). Embedding: nomic-embed-text, mxbai-embed-large, all-minilm, bge-m3.

## Node-2 (192.168.1.21) — 8 models / 55.4 GB (edge/generalist)
qwen3.6:latest, deepseek-r1:1.5b, gemma4:latest, deepseek-coder-v2:16b, hermes3:latest,
llava:7b, phi3:mini, nomic-embed-text:latest.
UNIQUE to Node-2 (not on Node-4): gemma4, deepseek-coder-v2:16b, hermes3, llava:7b, phi3:mini.

## Node-1 (192.168.1.218) — 2 models / 29.2 GB (local dev)
qwen3.6:latest, qwen3:8b.

## Shared / duplicated across nodes
- `qwen3.6:latest` on ALL THREE (newest model everywhere — likely current default).
- `deepseek-r1:1.5b` + `nomic-embed-text:latest` on Node-2 AND Node-4.
- Total fleet footprint ≈ 537 GB (counting duplicates).

## Security posture (confirmed)
- Ollama ships with **NO native auth**. From the sandbox we read /api/tags, /api/version,
  /api/ps, and POST /api/show unauthenticated → Ollama is bound to LAN (0.0.0.0), not
  127.0.0.1-only. Anyone on 192.168.1.0/24 can list, run (/api/generate), pull (/api/pull),
  and delete (/api/delete) models.
- WAN exposure UNVERIFIED — check the router for :11434 port-forward / open WAN.

## Reusable probe commands (copy-paste)
Full /24 discovery (parallel, ~1s/timeout):
```bash
for i in $(seq 1 254); do echo "192.168.1.$i"; done \
  | xargs -P 60 -I{} curl -s -m 1 --connect-timeout 1 -o /dev/null -w "%{http_code} {}\n" \
    "http://{}:11434/api/tags" 2>/dev/null | grep -v '^000'
```
Per-host model dump + size parse:
```bash
ip=192.168.1.215
curl -s -m 4 "http://$ip:11434/api/tags" -o /tmp/t.json
python3 -c "import json; d=json.load(open('/tmp/t.json')); ms=d['models'];
print(len(ms),'models', round(sum(m.get('size',0) for m in ms)/1e9,1),'GB');
[print(m['name'], round(m.get('size',0)/1e9,1),'GB') for m in ms]"
```
Alias / distinct-machine check (compare two hosts' model-name sets):
```bash
python3 -c "import json; a={m['name'] for m in json.load(open('/tmp/a.json'))['models']};
b={m['name'] for m in json.load(open('/tmp/b.json'))['models']}; print('identical:',a==b)"
```
Real model metadata (params/quant/context) — safe, existing model only:
```bash
curl -s -X POST "http://192.168.1.215:11434/api/show" -d '{"model":"qwen2.5:72b"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['details'])"
```
Latency probe (x3 each):
```bash
for ip in 218 215 21; do
  curl -s -o /dev/null -w "$ip connect=%{time_connect} total=%{time_total}\n" \
    "http://192.168.1.$ip:11434/api/tags"; done
```
