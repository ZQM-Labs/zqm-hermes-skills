# Best Model per Task — Matrix Template

Fill from a LIVE `POST /api/show` + `/api/tags` pull this turn. Reference only models
actually present on the LAN (verify via `curl http://<ip>:11434/api/tags`).

| Task | Recommended Model | Why (real specs) |
|------|-------------------|------------------|
| **Coding** | `qwen2.5-coder:32b` | 32.8B Q4_K_M, 32768 ctx, qwen2 arch — purpose-built code model |
| **Heavy reasoning** | `deepseek-r1:70b` | 70.6B, 131072 ctx, native CoT; alt `qwq:32b` (40960 ctx) |
| **Fast / cheap chat** | `qwen3:8b` / `qwen3:32b` | lightest real chat option / 32B quality |
| **Vision** | `qwen2.5vl:7b` | 8.3B qwen25vl, 128000 ctx — strongest multimodal on LAN |
| **Embeddings / RAG** | `bge-m3:latest` | 0.6B F16 bert, 8192 ctx, multilingual; alt `nomic-embed-text` |
| **Large-context** | `deepseek-r1:70b` / `llama3.3:70b` | only models reaching 131072 ctx |

## Footprint notes
- 70B-class (deepseek-r1:70b, llama3.1:70b, llama3.3:70b ~42.5GB; qwen2.5:72b ~47.4GB)
  need ~48GB+ VRAM or aggressive quant/CPU offload.
- Flag cross-node duplication (e.g. `qwen3.6:latest` duplicated on all 3 nodes).

## Provenance
- Host(s) probed:
- Pull command: `python scripts/pull_ollama_meta.py <host>`
- Timing: `for ip in ...; do curl -s --output /dev/null -w '%{time_connect} %{time_total}' http://$ip:11434/api/tags; done`
