---
name: Ollama fleet chaining (multi-instance aggregation)
class: LLM homelab service orchestration
verified: 2026-07-10 (web research: LiteLLM docs, Open WebUI docs, Ollama FAQ) + ZQM real topology
---

# Why chain
- Ollama: NO native auth; processes ONE request at a time per instance; models fragmented
  + duplicated across the 4 nodes (~536 GB total). 3 hosts LAN-exposed (.218/.215/.21),
  Node-3 (.46) localhost-only.
- Goal: one coherent, secure, load-balanced endpoint over all instances.

# Three patterns (research-backed)
1. LiteLLM proxy — RECOMMENDED control plane
   - Single OpenAI-compatible endpoint; virtual API keys (the auth Ollama lacks);
     load-balancing, fallbacks, retries, background health checks (drops a dead node
     from the pool BEFORE a user request fails).
   - Map each backend as a model_list entry. DUPLICATE model_name across hosts =>
     load-balanced pool. routing_strategy: simple-shuffle (LiteLLM prod default).
   - Run via Docker on the proxy host (Node-4 .215 natural choice).
2. Open WebUI multi-connection — UI layer only
   - OLLAMA_BASE_URLS accepts a LIST with per-connection tags ("gpu","fast").
     Connection mgmt per session — NOT true LB. Best as UI ON TOP of LiteLLM
     (point Open WebUI at LiteLLM's OpenAI-compatible endpoint).
3. Plain reverse proxy (nginx/Caddy) — auth + TLS only, no routing smarts.
   - basic-auth + bind 127.0.0.1. Use only if you want minimal moving parts.

# Node-3 decision
- localhost-only today = zero LAN risk. LEAVE private unless it has compute worth
  sharing; then expose it behind the authenticated proxy (change OLLAMA_HOST + add to
  LiteLLM behind the gateway).

# Security ordering (NEVER expose before auth)
1. Stand up LiteLLM w/ auth, bound 127.0.0.1 on the proxy host.
2. Point clients at the proxy, NOT directly at :11434.
3. Firewall :11434 on .218/.215/.21 so ONLY the proxy IP reaches it.
4. Router: ensure NO :11434 WAN port-forward.
5. Only THEN consider joining Node-3.
Converts "3 open unauth endpoints" -> "1 authed gateway, backends locked to gateway IP".

# Windows OLLAMA_HOST set
[System.Environment]::SetEnvironmentVariable("OLLAMA_HOST","0.0.0.0","User") then
restart the Ollama service. Default (unset) = 127.0.0.1 = localhost-only.

# Migration / dedup AFTER chaining (pruning is transparent to clients via LiteLLM)
- qwen3.6:latest x3 -> keep 1 on Node-4 (~-48 GB).
- dedupe deepseek-r1:1.5b, nomic-embed-text, qwen3:8b to 1 host each.
- optionally drop 1-2 redundant 70B-class models on Node-4 (-42 to -85 GB) with zero
  capability loss if only one 70B runs at a time.

# LiteLLM config template (ZQM real hosts/models — expand to all 55)
model_list:
  - model_name: deepseek-r1-70b
    litellm_params: { model: ollama/deepseek-r1:70b, api_base: http://192.168.1.215:11434 }
  - model_name: fast-chat
    litellm_params: { model: ollama/qwen3:8b, api_base: http://192.168.1.215:11434 }
  - model_name: fast-chat
    litellm_params: { model: ollama/qwen3:8b, api_base: http://192.168.1.21:11434 }
  - model_name: fast-chat
    litellm_params: { model: ollama/qwen3:8b, api_base: http://192.168.1.218:11434 }
  - model_name: gemma4
    litellm_params: { model: ollama/gemma4:latest, api_base: http://192.168.1.21:11434 }
  - model_name: embeddings
    litellm_params: { model: ollama/bge-m3:latest, api_base: http://192.168.1.215:11434 }
router_settings:
  routing_strategy: simple-shuffle
  num_retries: 2
  timeout: 60
  fallbacks: [ { fast-chat: [deepseek-r1-70b] } ]
Run:
  docker run -p 4000:4000 -v ./litellm_config.yaml:/app/config.yaml \
    -e LITELLM_MASTER_KEY=sk-master-<rand> ghcr.io/berriai/litellm:main \
    --config /app/config.yaml

# Full plan on disk
C:\Users\zqmco\Desktop\Ollama_Fleet_Chaining_Plan.md

# Caveat
None of this was DEPLOYED — the above is a design + template from live research and the
verified inventory. It needs a real run + smoke test before it is "working"; the agent
should execute/verify it if asked to build it for real (don't claim success from the plan).
