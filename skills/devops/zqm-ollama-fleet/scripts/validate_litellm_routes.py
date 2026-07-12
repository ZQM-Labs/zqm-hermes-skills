#!/usr/bin/env python3
"""Validate a LiteLLM model_list config against the live ZQM Ollama fleet.

Does two things:
  1. CONFIG DRIFT  - every ollama/<tag> in the config must exist in the target
     node's live /api/tags (and reverse: served models with no route).
  2. SAMPLED PROBE - POST /api/chat|embeddings|generate to a sample of routes and
     report WORKS / TIMEOUT(0) / AUTH-FAIL(401/403) / HTTP<code>.

URL-based (urllib), parallel via ThreadPoolExecutor. stdlib only.
Usage:  python validate_litellm_routes.py <config.yaml> [--key sk-na]
"""
import re, json, time, base64, zlib, struct, argparse, concurrent.futures, urllib.request, urllib.error
from collections import defaultdict

def _png(w=32, h=32, rgb=b"\xff\x00\x00"):
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + rgb * w for _ in range(h))
    return base64.b64encode(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")).decode()

IMG = _png()

def live_tags(ip, tmo=10):
    try:
        req = urllib.request.Request(f"http://{ip}:11434/api/tags")
        d = json.load(urllib.request.urlopen(req, timeout=tmo))
        return {m["name"] for m in d.get("models", [])}
    except Exception:
        return None

def parse_cfg(text):
    out = []
    for b in re.split(r"(?=^- model_name:)", text, flags=re.M):
        name = re.search(r"model_name:\s*(\S+)", b)
        ip = re.search(r"api_base:\s*http://(\d+\.\d+\.\d+\.\d+)", b)
        tag = re.search(r"model:\s*ollama(?:_chat)?/([^\s]+)", b)
        if name and ip and tag:
            out.append((name.group(1), tag.group(1), ip.group(1)))
    return out

def probe(kind, ip, model, key, tmo):
    url = f"http://{ip}:11434/{kind}"
    body = {"model": model, "stream": False}
    if kind == "api/chat":
        body["messages"] = [{"role": "user", "content": "hi"}]
    elif kind == "api/embeddings":
        body["prompt"] = "test"
    else:
        body["prompt"] = "describe the image"; body["images"] = [IMG]
    h = {"Content-Type": "application/json"}
    if key:
        h["Authorization"] = f"Bearer {key}"
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=h, method="POST")
    t = time.time()
    try:
        r = urllib.request.urlopen(req, timeout=tmo); return r.status, round(time.time()-t, 1)
    except urllib.error.HTTPError as e:
        return e.code, round(time.time()-t, 1)
    except Exception:
        return 0, round(time.time()-t, 1)

def route_kind(tag):
    if tag in ("bge-m3:latest", "nomic-embed-text:latest", "mxbai-embed-large:latest", "all-minilm:latest"):
        return "api/embeddings"
    if any(v in tag for v in ("llava", "minicpm-v", "moondream", "qwen2.5vl")):
        return "api/generate"
    return "api/chat"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config")
    ap.add_argument("--key", default="sk-na")
    ap.add_argument("--tmo-chat", type=int, default=120)
    ap.add_argument("--tmo-heavy", type=int, default=300)
    args = ap.parse_args()

    text = open(args.config).read()
    entries = parse_cfg(text)
    print(f"Parsed {len(entries)} model_list entries")

    live = {ip: live_tags(ip) for ip in set(ip for _, _, ip in entries)}
    for ip, tags in live.items():
        print(f"  live {ip}: {'UNREACHABLE' if tags is None else str(len(tags))+' models'}")

    print("\n== CONFIG DRIFT ==")
    drift = [e for e in entries if live.get(e[2]) is not None and e[1] not in live[e[2]]]
    if drift:
        for n, t, ip in drift:
            print(f"  DRIFT {n} -> ollama/{t} not on {ip}")
    else:
        print("  NONE (every ollama tag is served by its target node)")
    byip = defaultdict(set)
    for _, t, ip in entries:
        byip[ip].add(t)
    for ip, tags in live.items():
        if tags is None:
            continue
        gap = sorted(tags - byip[ip])
        print(f"  coverage gap {ip}: {gap if gap else 'NONE'}")

    print("\n== SAMPLED PROBE ==")
    jobs = []
    for n, t, ip in entries:
        if n in ("fast-chat", "heavy-reasoning", "qwen3-32b", "embeddings", "vision"):
            continue
        kind = route_kind(t)
        tmo = args.tmo_heavy if ("70b" in t or "72b" in t) else args.tmo_chat
        jobs.append((n, t, ip, kind, tmo))
    jobs = jobs[:16]
    def run(j):
        n, t, ip, kind, tmo = j
        return j, probe(kind, ip, t, args.key, tmo)
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as ex:
        for fut in concurrent.futures.as_completed([ex.submit(run, j) for j in jobs]):
            (n, t, ip, kind, _), (code, sec) = fut.result()
            verdict = "WORKS" if code == 200 else ("AUTH-FAIL" if code in (401, 403) else ("TIMEOUT" if code == 0 else f"HTTP{code}"))
            print(f"  {verdict:9s} {n:20s} {t:20s} {ip} {kind} ({sec}s)")

if __name__ == "__main__":
    main()
