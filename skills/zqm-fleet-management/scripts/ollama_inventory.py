#!/usr/bin/env python3
"""Cross-node Ollama inventory for the ZQM homelab fleet.

Pulls /api/tags from each Ollama host, parses sizes, builds a reconciliation
table (Host / Model / Size GB / Family / Unique?), flags exact cross-node
duplicates, and prints the total footprint.

Verified topology (2026-07-10, live):
  Node-4  192.168.1.215  Central heavy-inference farm   45 models / 451.60 GB
  Node-2  192.168.1.21   Edge / generalist               8 models /  55.41 GB
  Node-1  192.168.1.218  Local dev / minimal             2 models /  29.16 GB
  TOTAL ~ 536.22 GB across 55 installs (51 distinct names)

Run:  python ollama_inventory.py
Writes raw pull to $HOME/ollama_raw.json for audit.
No external deps (urllib + json only). Works on the MSYS/Windows bash terminal
where /tmp is not writable — uses $HOME instead.
"""
import json, os, urllib.request

HOSTS = [
    ("192.168.1.215", "Node-4", "Central heavy-inference farm"),
    ("192.168.1.21",  "Node-2", "Edge / generalist"),
    ("192.168.1.218", "Node-1", "Local dev / minimal"),
]
PORT = 11434


def fetch(ip):
    try:
        with urllib.request.urlopen(f"http://{ip}:{PORT}/api/tags", timeout=8) as r:
            return json.load(r)["models"]
    except Exception as e:
        return {"_error": str(e)}


def gb(s):
    return round(s / 1e9, 2)


def family(name):
    n = name.split(":")[0].lower()
    emb = {"all-minilm", "bge-m3", "mxbai-embed-large", "nomic-embed-text"}
    vis = {"llava", "llava-phi3", "minicpm-v", "moondream", "qwen2.5vl"}
    if n in emb:
        return "Embedding"
    if n in vis:
        return "Vision/Multimodal"
    if "deepseek-r1" in name:
        return "DeepSeek-R1"
    if "deepseek-coder" in name:
        return "DeepSeek-Coder"
    if "qwq" in name:
        return "QwQ"
    if "mixtral" in name:
        return "Mixtral(MoE)"
    return n.capitalize()


def main():
    out = {}
    for ip, label, role in HOSTS:
        models = fetch(ip)
        out[ip] = {"label": label, "role": role, "models": models}

    raw = os.path.join(os.environ["HOME"], "ollama_raw.json")
    with open(raw, "w") as f:
        json.dump(out, f, indent=2)

    presence = {}
    for ip, label, role in HOSTS:
        models = out[ip]["models"]
        if isinstance(models, dict) and "_error" in models:
            print(f"!! {label} ({ip}) ERROR: {models['_error']}")
            continue
        for m in models:
            presence.setdefault(m["name"], []).append((label, m["size"]))

    for ip, label, role in HOSTS:
        models = out[ip]["models"]
        if isinstance(models, dict) and "_error" in models:
            continue
        print(f"\n===== {label} ({ip}) — {role} =====")
        total = 0
        uniq = 0
        for m in sorted(models, key=lambda x: x["name"]):
            sz = gb(m["size"])
            total += m["size"]
            shared = len(presence[m["name"]]) > 1
            if not shared:
                uniq += 1
            flag = "shared" if shared else "UNIQUE"
            print(f"  {m['name']:28s} {sz:8.2f} {family(m['name']):16s} {flag}")
        print(f"  models={len(models)} total={gb(total):.2f}GB unique={uniq}")

    print("\n===== CROSS-NODE DUPLICATES =====")
    reclaim = 0
    for name, occ in sorted(presence.items(), key=lambda kv: -len(kv[1])):
        if len(occ) > 1:
            hosts = [o[0] for o in occ]
            sz = gb(occ[0][1])
            red = len(occ) - 1
            reclaim += sz * red
            print(f"  {name:28s} on {','.join(hosts)} x{sz}GB redundant_copies={red}")
    print(f"  RECLAIMABLE from pure duplication: {reclaim:.2f} GB")

    tot = 0
    installs = 0
    for ip, label, role in HOSTS:
        models = out[ip]["models"]
        if isinstance(models, list):
            for m in models:
                tot += m["size"]
                installs += 1
    print(f"\nTOTAL footprint: {gb(tot):.2f} GB across {installs} installs "
          f"({len(presence)} distinct)")
    print(f"Raw pull saved: {raw}")


if __name__ == "__main__":
    main()
