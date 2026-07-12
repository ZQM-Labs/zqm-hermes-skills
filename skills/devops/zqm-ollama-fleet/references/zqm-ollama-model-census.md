# ZQM Ollama Fleet — Model Census (REAL numbers, 2026-07-10)

All figures pulled LIVE via `POST /api/show` on Node-4 (192.168.1.215). Authoritative
values from `model_info`; `details` null fields excluded.

## Model metadata (Node-4, Q4_K_M gguf unless noted)

| Model | Parameters | Quant | Context | Architecture | Format |
|-------|-----------|-------|---------|--------------|--------|
| deepseek-r1:70b | 70.6B | Q4_K_M | 131072 | llama | gguf |
| qwq:32b | 32.8B | Q4_K_M | 40960 | qwen2 | gguf |
| qwen2.5:72b | 72.7B | Q4_K_M | 32768 | qwen2 | gguf |
| llama3.3:70b | 70.6B | Q4_K_M | 131072 | llama | gguf |
| qwen3:32b | 32.8B | Q4_K_M | 40960 | qwen3 | gguf |
| qwen2.5-coder:32b | 32.8B | Q4_K_M | 32768 | qwen2 | gguf |
| qwen2.5vl:7b | 8.3B | Q4_K_M | 128000 | qwen25vl | gguf |
| bge-m3:latest | 0.6B | F16 | 8192 | bert | gguf |

## Responsiveness (HTTP `/api/tags` timing, 3 runs each; avg)

| Host | Role | Avg connect (s) | Avg total (s) |
|------|------|-----------------|---------------|
| 192.168.1.218 | Node-1 (desk) | 0.000685 | 0.001914 |
| 192.168.1.21 | Node-2 | 0.010253 | 0.015799 |
| 192.168.1.215 | Node-4 (heavy) | 0.026954 | 0.053596 |

Most responsive: **Node-1 (.218)** — ~5-28x faster than the LAN nodes on control-plane
latency. These are NOT token-generation speeds, only endpoint/network proximity.

## VRAM / footprint
- 70B-class behemoths on Node-4: deepseek-r1:70b, llama3.1:70b, llama3.3:70b ~42.5GB
  each (Q4_K_M); qwen2.5:72b ~47.4GB. Four together ~175GB of weights. Each needs
  ~48GB+ contiguous VRAM or aggressive quant/CPU offload to run at speed.
- Duplication / sprawl:
  - `qwen3.6:latest` (23.9GB) duplicated across ALL THREE nodes (.218/.215/.21) ->
    ~71.7GB redundant. Consolidate onto Node-1.
  - `deepseek-r1:1.5b` present on two nodes (215 + 21) - minor redundancy.
  - Node-4 also carries llama3.1:70b + llama3.3:70b (redundant 70B Llama pair);
    llama3.3 supersedes llama3.1 for most uses.
- Everything <=32B (~20GB Q4) / 7-8B (~5GB) / embeddings (~1-2GB) runs comfortably on a
  single 24GB consumer GPU. Only the 70B quartet forces the quant/offload decision.

## Best-model-per-task (referenced to real models present)
- Coding -> qwen2.5-coder:32b (alt deepseek-coder-v2:16b on Node-2)
- Heavy reasoning -> deepseek-r1:70b (alt qwq:32b, both native thinking/CoT)
- Fast/cheap chat -> qwen3:8b (Node-1) or qwen3:32b (Node-4)
- Vision -> qwen2.5vl:7b (128K ctx); Node-2 also has llava:7b
- Embeddings/RAG -> bge-m3:latest (F16, multilingual) or nomic-embed-text:latest (Node-2)
- Large-context -> deepseek-r1:70b / llama3.3:70b (131072) or qwen2.5vl:7b (128000)
