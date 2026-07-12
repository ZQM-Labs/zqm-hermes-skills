#!/usr/bin/env python3
"""generate_health.py — Ollama /api/tags vs /api/generate health probe.
Proves the 'generate-hang' fault: tags=200 fast but generate=HTTP 000 (timeout).
Usage:  python generate_health.py <ip> [model] [generate_timeout_s]
"""
import sys, time, json, urllib.request, urllib.error

IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.215"
MODEL = sys.argv[2] if len(sys.argv) > 2 else None
GEN_TIMEOUT = int(sys.argv[3]) if len(sys.argv) > 3 else 30


def _req(url, data=None, timeout=10):
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, round(time.time() - t0, 2), None
    except urllib.error.HTTPError as e:
        return e.code, round(time.time() - t0, 2), None
    except Exception as e:  # timeout / connection refused => HTTP 000 class
        return 000, round(time.time() - t0, 2), type(e).__name__


def main():
    tags_code, tags_t, _ = _req(f"http://{IP}:11434/api/tags", timeout=5)
    print(f"tags  = HTTP {tags_code}  {tags_t}s")

    if tags_code != 200:
        print("tags endpoint failed -> service down / firewalled. NOT the generate-hang fault.")
        return

    if MODEL is None:
        try:
            with urllib.request.urlopen(f"http://{IP}:11434/api/tags", timeout=5) as r:
                models = [m["name"] for m in json.load(r).get("models", [])]
            MODEL = models[0] if models else None
        except Exception:
            MODEL = None
    if not MODEL:
        print("no local model to generate with; supply one as argv[2].")
        return

    gen_code, gen_t, err = _req(
        f"http://{IP}:11434/api/generate",
        data={"model": MODEL, "prompt": "ping", "stream": False},
        timeout=GEN_TIMEOUT)
    print(f"gen   = HTTP {gen_code}  {gen_t}s  model={MODEL}" + (f"  ({err})" if err else ""))

    if gen_code == 200:
        print("HEALTHY: generate works.")
    elif gen_code == 000:
        print("FAULT CONFIRMED: generate HANGS (GPU/VMM stuck). Run ollama-recovery STEP 2.")
    else:
        print(f"NOT the hang fault (HTTP {gen_code}). Fix the request / model name.")


if __name__ == "__main__":
    main()
