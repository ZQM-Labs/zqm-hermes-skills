#!/usr/bin/env python3
"""Re-runnable Ollama model-metadata extractor for the ZQM homelab fleet.

Why this exists: POST /api/show's `details` block returns NULL for
parameter_count / context_length / architecture on the GGUF imports used on
this fleet. The authoritative values live in the `model_info` GGUF header map.

Usage:
  python pull_ollama_meta.py [HOST] [MODEL ...]
  python pull_ollama_meta.py http://192.168.1.215:11434
  python pull_ollama_meta.py http://192.168.1.215:11434 qwen3:32b bge-m3:latest
"""
import json
import sys
import urllib.request

DEFAULT_HOST = "http://192.168.1.215:11434"
DEFAULT_MODELS = [
    "deepseek-r1:70b", "qwq:32b", "qwen2.5:72b", "llama3.3:70b",
    "qwen3:32b", "qwen2.5-coder:32b", "qwen2.5vl:7b", "bge-m3:latest",
]


def show(host: str, name: str) -> dict:
    req = urllib.request.Request(
        host + "/api/show",
        data=json.dumps({"model": name}).encode(),
        headers={"Content-Type": "application/json"},
    )
    return json.load(urllib.request.urlopen(req, timeout=15))


def main() -> None:
    host = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_HOST
    models = sys.argv[2:] or DEFAULT_MODELS

    print(f"host={host}")
    header = f"{'model':24} {'params':>8} {'quant':>9} {'ctx':>9} {'arch':>10} {'fmt'}"
    print(header)
    print("-" * len(header))
    for m in models:
        d = show(host, m)
        det = d.get("details", {})
        mi = d.get("model_info", {})
        arch = det.get("family") or mi.get("general.architecture") or "n/a"
        pc = mi.get("general.parameter_count")
        pc_str = (
            f"{pc/1e9:.1f}B" if isinstance(pc, (int, float)) else (det.get("parameter_size") or "n/a")
        )
        ctx = (
            mi.get(f"{arch}.context_length")
            or mi.get("general.context_length")
            or det.get("context_length")
            or "n/a"
        )
        ql = det.get("quantization_level") or mi.get("general.file_type") or "n/a"
        fmt = det.get("format") or "n/a"
        print(f"{m:24} {pc_str:>8} {str(ql):>9} {str(ctx):>9} {str(arch):>10} {fmt}")


if __name__ == "__main__":
    main()
