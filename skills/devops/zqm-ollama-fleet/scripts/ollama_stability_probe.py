#!/usr/bin/env python3
"""ZQM Ollama fleet stability probe — dual probe per node to detect model-count flapping.

For each node, hits GET /api/tags twice (~5s apart) and compares (model_count, total_GB).
Prints a per-node table and a STABLE / MISMATCH / UNREACHABLE verdict. Stdlib only.

Usage:
  python ollama_stability_probe.py [ip ...] [--gap 5]
Defaults to the 4 ZQM nodes (N1 .218, N2 .21, N4 .215, N3 .46).
"""
import json, sys, time, urllib.request, argparse

DEFAULT_NODES = ["192.168.1.218", "192.168.1.21", "192.168.1.215", "192.168.1.46"]
PORT = 11434
TIMEOUT = 5

def probe(host):
    url = f"http://{host}:{PORT}/api/tags"
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT) as r:
            d = json.load(r)
        models = d.get("models", [])
        count = len(models)
        gb = round(sum(m.get("size", 0) for m in models) / 1e9, 2)
        return count, gb
    except Exception as e:
        return None, str(e)

def main():
    ap = argparse.ArgumentParser(description="Dual-probe Ollama fleet stability check.")
    ap.add_argument("ips", nargs="*", default=DEFAULT_NODES, help="node IPs to probe")
    ap.add_argument("--gap", type=float, default=5.0, help="seconds between the two probes")
    args = ap.parse_args()

    print(f"{'Node':<16}{'Run1':<18}{'Run2':<18}{'Stable?'}")
    for ip in args.ips:
        r1 = probe(ip)
        time.sleep(args.gap)
        r2 = probe(ip)
        if r1[0] is None or r2[0] is None:
            run1 = f"FAIL:{r1[1]}" if r1[0] is None else f"{r1[0]}/{r1[1]}GB"
            run2 = f"FAIL:{r2[1]}" if r2[0] is None else f"{r2[0]}/{r2[1]}GB"
            verdict = "UNREACHABLE"
        else:
            run1 = f"{r1[0]}/{r1[1]}GB"
            run2 = f"{r2[0]}/{r2[1]}GB"
            verdict = "YES" if r1 == r2 else "MISMATCH"
        print(f"{ip:<16}{run1:<18}{run2:<18}{verdict}")

if __name__ == "__main__":
    main()
