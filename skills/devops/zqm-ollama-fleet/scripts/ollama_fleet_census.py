#!/usr/bin/env python3
"""
Ollama fleet census + health check (4-part method).
For each node: reachability (/api/tags) -> inventory (models + GB) ->
generate health check (/api/generate hang test) -> localhost-bound verdict.
Re-runnable, stdlib only. Usage:
  python ollama_fleet_census.py [ip1 ip2 ...]   (defaults to the ZQM fleet)

Prints PROVEN/NOT-PROVEN per node and a plain "UNREACHABLE" line when a node
does not answer :11434 (never assumes its model list).
"""
import json, sys, time, subprocess, urllib.request, urllib.error

NODES = ["192.168.1.218", "192.168.1.21", "192.168.1.46", "192.168.1.215"]
GEN_TIMEOUT = 15      # /api/generate hang test
TAGS_TIMEOUT = 5      # reachability


def _http(method, url, data=None, timeout=5):
    req = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:
        return 0, str(e).encode()


def census(ip):
    print(f"\n===== NODE {ip} =====")
    # 1. reachability
    code, body = _http("GET", f"http://{ip}:11434/api/tags", timeout=TAGS_TIMEOUT)
    if code != 200:
        # 4. localhost-bound disambiguation via ICMP
        print(f"  :11434 -> HTTP {code} (NOT reachable from this box)")
        ping = subprocess.run(
            ["ping", "-n", "3", ip], capture_output=True, text=True)
        up = ("0% loss" in ping.stdout) or ("Received = 3" in ping.stdout)
        print(f"  ICMP  -> {'HOST UP' if up else 'HOST DOWN/UNREACHABLE'}")
        verdict = ("NOT LAN-exposed (host-up + :11434 timeout = localhost-bound "
                   "per prior intent)") if up else "UNREACHABLE - host itself not responding"
        print(f"  VERDICT: {verdict}")
        print("  Models/GB: UNKNOWN (do not assume).")
        return
    # 2. inventory
    models = json.loads(body).get("models", [])
    total = sum(m["size"] for m in models)
    print(f"  :11434 -> HTTP 200 | models={len(models)} | total={total/1e9:.3f} GB ({total/2**30:.2f} GiB)")
    for m in models:
        d = m.get("details", {})
        print(f"    {m['name']:<28} {m['size']/1e9:7.3f} GB  ({d.get('parameter_size','?')}, {d.get('quantization_level','?')})")
    # 3. generate health check / HANG test
    smallest = min(models, key=lambda m: m["size"])["name"]
    payload = json.dumps({"model": smallest, "prompt": "ping",
                          "stream": False, "options": {"num_predict": 4}}).encode()
    t0 = time.time()
    gcode, _ = _http("POST", f"http://{ip}:11434/api/generate", data=payload, timeout=GEN_TIMEOUT)
    dt = time.time() - t0
    hung = (gcode == 0)
    print(f"  /api/generate({smallest}) -> HTTP {gcode} in {dt:.1f}s {'[HANG/000]' if hung else ''}")
    print(f"  VERDICT: LAN-exposed (reachable over LAN) | generate {'HUNG' if hung else 'OK'}")


if __name__ == "__main__":
    targets = sys.argv[1:] or NODES
    for ip in targets:
        census(ip)
