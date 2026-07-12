#!/usr/bin/env python3
"""gen_litellm_config.py — regenerate litellm_config.yaml for the ZQM Ollama fleet.

Reads each Ollama host's /api/tags (live, or from a cached JSON) and emits a full
LiteLLM proxy config: every install under its real tag, chat models with the
ollama_chat/ prefix, load-balanced aliases (fast-chat / heavy-reasoning / embeddings /
vision), router fallbacks, and general_settings.master_key from ${LITELLM_MASTER_KEY}.

Avoids the two pitfalls baked into the 2026-07-10 first build:
  * keep_alive is a TTL (default 10m), NOT '-1' — '-1' OOMs Node-4 (45 models can't
    all stay resident in VRAM). Override with KEEP_ALIVE_TTL env / --ttl.
  * every fallback target is a defined model_name (qwen3-32b is always emitted).

Usage:
  python gen_litellm_config.py --hosts 192.168.1.215 192.168.1.21 192.168.1.218 \
      --out litellm_config.yaml
  python gen_litellm_config.py --from-json tags_215.json tags_21.json tags_218.json
  KEEP_ALIVE_TTL=10m python gen_litellm_config.py --hosts 192.168.1.215
Stdlib only.
"""
import argparse
import json
import os
import sys
import urllib.request

CHAT_HINTS = ("llama3", "qwen3", "qwen2.5", "phi", "gemma", "mistral",
              "deepseek", "hermes", "mixtral", "qwq")


def is_chat(name: str) -> bool:
    return any(h in name for h in CHAT_HINTS)


def fetch_tags(host: str) -> list:
    url = f"http://{host}:11434/api/tags"
    try:
        with urllib.request.urlopen(url, timeout=8) as r:
            data = json.load(r)
        return data.get("models", [])
    except Exception as e:  # read-only probe only — never abort the whole run
        print(f"  ! {host}: tags fetch failed ({e})", file=sys.stderr)
        return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hosts", nargs="+", default=["192.168.1.215", "192.168.1.21", "192.168.1.218"])
    ap.add_argument("--from-json", nargs="+", default=[],
                    help="host=path pairs OR just paths; we derive host from filename IP")
    ap.add_argument("--out", default="litellm_config.yaml")
    ap.add_argument("--ttl", default=os.environ.get("KEEP_ALIVE_TTL", "10m"))
    args = ap.parse_args()

    # host -> list of model name strings
    hosts: dict[str, list[str]] = {}
    for h in args.hosts:
        hosts[h] = [m["name"] for m in fetch_tags(h)]

    if args.from_json:
        for p in args.from_json:
            # derive host IP from a filename like tags_192.168.1.215.json
            base = os.path.basename(p).replace(".json", "")
            ip = base.split("_")[-1]
            try:
                with open(p) as f:
                    models = json.load(f).get("models", [])
                hosts.setdefault(ip, [m["name"] for m in models])
            except Exception as e:
                print(f"  ! could not read {p}: {e}", file=sys.stderr)

    if not any(hosts.values()):
        print("No models discovered from any host. Aborting.", file=sys.stderr)
        sys.exit(1)

    ttl = args.ttl
    entries = []
    for ip, models in hosts.items():
        for name in models:
            prefix = "ollama_chat/" if is_chat(name) else "ollama/"
            params = {"model": f"{prefix}{name}", "api_base": f"http://{ip}:11434"}
            if is_chat(name):
                params["keep_alive"] = ttl
            entries.append({"model_name": name, "litellm_params": params})

    # aggregated aliases
    fast_hosts = [ip for ip, ms in hosts.items() if "qwen3:8b" in ms]
    for ip in fast_hosts:
        entries.append({"model_name": "fast-chat",
                        "litellm_params": {"model": "ollama_chat/qwen3:8b",
                                           "api_base": f"http://{ip}:11434", "keep_alive": ttl}})
    node4 = "192.168.1.215"
    if node4 in hosts:
        for m in ["deepseek-r1:70b", "qwq:32b", "deepseek-r1:32b", "llama3.3:70b"]:
            if m in hosts[node4]:
                entries.append({"model_name": "heavy-reasoning",
                                "litellm_params": {"model": f"ollama_chat/{m}",
                                                   "api_base": f"http://{node4}:11434", "keep_alive": ttl}})
        # fallback target always defined
        entries.append({"model_name": "qwen3-32b",
                        "litellm_params": {"model": "ollama_chat/qwen3:32b",
                                           "api_base": f"http://{node4}:11434", "keep_alive": ttl}})
        # embeddings: bge-m3 primary
        if "bge-m3:latest" in hosts[node4]:
            entries.append({"model_name": "embeddings",
                            "litellm_params": {"model": "ollama/bge-m3:latest",
                                               "api_base": f"http://{node4}:11434"}})
        vision_models = ["qwen2.5vl:7b", "llava:13b", "minicpm-v:latest", "moondream:latest"]
        for m in vision_models:
            if m in hosts[node4]:
                entries.append({"model_name": "vision",
                                "litellm_params": {"model": f"ollama/{m}",
                                                   "api_base": f"http://{node4}:11434"}})
    node2 = "192.168.1.21"
    if node2 in hosts:
        if "nomic-embed-text:latest" in hosts[node2]:
            entries.append({"model_name": "embeddings",
                            "litellm_params": {"model": "ollama/nomic-embed-text:latest",
                                               "api_base": f"http://{node2}:11434"}})
        if "llava:7b" in hosts[node2]:
            entries.append({"model_name": "vision",
                            "litellm_params": {"model": "ollama/llava:7b",
                                               "api_base": f"http://{node2}:11434"}})

    config = {
        "model_list": entries,
        "router_settings": {
            "routing_strategy": "simple-shuffle",
            "num_retries": 2,
            "timeout": 120,
            "retry_after": 5,
            "fallbacks": [
                {"fast-chat": ["heavy-reasoning"]},
                {"heavy-reasoning": ["qwen3-32b"]},
            ],
        },
        "litellm_settings": {"drop_params": True, "request_timeout": 120},
        "general_settings": {"master_key": "${LITELLM_MASTER_KEY}", "store_model_in_db": False},
    }

    try:
        import yaml
        text = yaml.safe_dump(config, sort_keys=False, default_flow_style=False, width=4096)
    except ImportError:
        import json as _json
        text = _json.dumps(config, indent=2)
        print("  (PyYAML not present — wrote JSON-shaped YAML; install pyyaml for clean output)",
              file=sys.stderr)

    with open(args.out, "w") as f:
        f.write(text)
    print(f"Wrote {args.out}: {len(entries)} routing entries across {len(hosts)} hosts "
          f"(keep_alive TTL={ttl}).")


if __name__ == "__main__":
    main()
