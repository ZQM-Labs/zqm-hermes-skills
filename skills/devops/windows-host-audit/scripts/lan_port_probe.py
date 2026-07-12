#!/usr/bin/env python3
"""
lan_port_probe.py — fast, read-only LAN TCP endpoint review.

Why this exists: a "full read-only endpoint review" of a fleet node where an
earlier (heavier) probe TIMED OUT. The fix that worked: a curated port list
+ a short per-port connect timeout instead of a full-range scan or a slow
banner-grab. Pure-python (no nmap), runs from the agent host against a LAN
target. Completed a 16-port scan of N4 in ~5s at 0.4s/port.

Now ALSO confirms the two headline unauthenticated risks with live probes:
  - Redis  :6379  -> RESP PING -> +PONG unauth = CRITICAL RCE primitive
  - Ollama :11434 -> GET /api/tags -> 200 + model list = unauthenticated exposure
and emits an overall NODE GRADE (A-F).

Usage:
  python lan_port_probe.py [TARGET] [--timeout 0.4] [--no-ollama] [--no-redis]
  python lan_port_probe.py 192.168.1.21
If TARGET omitted, defaults to DEFAULT_TARGET below.

Read-only: sends no mutations — just TCP SYN + one Redis PING + one HTTP GET.
"""
import socket
import json
import time
import argparse
import urllib.request

DEFAULT_TARGET = "192.168.1.215"

# Curated port map — add/remove per node class. Keep this SHORT: the whole
# point is efficiency vs a timed-out heavy scan.
PORTS = {
    22: "SSH", 135: "MS-RPC", 139: "NetBIOS", 445: "SMB",
    2179: "VM-RDP", 3389: "RDP", 5040: "WinNAT",
    5357: "WSDAPI", 5985: "WinRM-HTTP", 5986: "WinRM-HTTPS",
    47001: "WinRM-CBD", 11434: "Ollama", 4001: "LiteLLM",
    8400: "ZBit-Agent", 6379: "Redis", 18789: "OpenClaw-MESH",
}


def probe(host, port, to):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(to)
    t0 = time.time()
    try:
        s.connect((host, port))
        return True, round((time.time() - t0) * 1000, 1)
    except (socket.timeout, OSError):
        return False, None
    finally:
        s.close()


def verify_ollama(host, to=3):
    try:
        req = urllib.request.Request(
            f"http://{host}:11434/api/tags",
            headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=to) as r:
            data = json.loads(r.read().decode())
            models = [m.get("name") for m in data.get("models", [])]
            return {"status": "UP", "lan_exposed": True,
                    "models": len(models), "http": r.status}
    except Exception as e:
        return {"status": "FAIL", "lan_exposed": False, "error": str(e)}


def redis_unauth(host, to=1.0):
    """Open :6379 + PING -> +PONG with NO AUTH = CRITICAL RCE primitive.
    Returns dict. NOTE (2026-07-11, live evidence): on Node-2 (192.168.1.21)
    Redis was LAN-OPEN and FULLY unauthenticated — do NOT assume 6379 is
    loopback-only. A raw PING returned +PONG with no AUTH."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(to)
        s.connect((host, 6379))
        s.sendall(b"PING\r\n")
        resp = s.recv(200)
        s.close()
        if b"+PONG" in resp:
            return {"status": "UNAUTH", "detail": resp.decode(errors="replace").strip()}
        if b"-NOAUTH" in resp or b"-ERR" in resp:
            return {"status": "AUTH_REQUIRED", "detail": resp.decode(errors="replace").strip()}
        return {"status": "RESP_UNKNOWN", "detail": resp.decode(errors="replace").strip()}
    except Exception as e:
        return {"status": "CLOSED_OR_ERR", "error": str(e)}


RISK_RANK = {"LOW": 0, "MED": 1, "HIGH": 2, "CRIT": 3}
PORT_BASE_RISK = {
    22: "MED", 135: "MED", 139: "MED", 445: "HIGH", 2179: "MED",
    3389: "HIGH", 5040: "LOW", 5357: "LOW", 5985: "HIGH", 5986: "MED",
    47001: "LOW", 11434: "HIGH", 4001: "MED", 8400: "MED",
    6379: "CRIT", 18789: "LOW",
}


def node_grade(open_ports, ollama, redis):
    risks = [PORT_BASE_RISK.get(p["port"], "LOW") for p in open_ports]
    if redis and redis.get("status") == "UNAUTH":
        return "F / CRITICAL"   # unauth Redis = RCE primitive, caps grade
    if any(r == "CRIT" for r in risks):
        return "F / CRITICAL"
    high = [r for r in risks if r == "HIGH"]
    med = any(r == "MED" for r in risks)
    if len(high) >= 2:
        return "D / HIGH"
    if high or (ollama and ollama.get("lan_exposed")):
        return "C / ELEVATED"
    if med:
        return "B / MODERATE"
    return "A / LOW"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", nargs="?", default=DEFAULT_TARGET)
    ap.add_argument("--timeout", type=float, default=0.4)
    ap.add_argument("--no-ollama", action="store_true")
    ap.add_argument("--no-redis", action="store_true")
    args = ap.parse_args()

    print(f"=== LAN endpoint probe: {args.target} ===")
    open_ports = []
    for p, name in PORTS.items():
        ok, rtt = probe(args.target, p, args.timeout)
        flag = "OPEN " if ok else "closed"
        extra = f" ({rtt}ms)" if ok else ""
        print(f"  {p:6} {name:12} {flag}{extra}")
        if ok:
            open_ports.append({"port": p, "name": name, "rtt_ms": rtt})

    ollama = None
    if not args.no_ollama:
        print("\n=== Ollama :11434 LAN verification ===")
        ollama = verify_ollama(args.target)
        if ollama.get("status") == "UP":
            print(f"  HTTP {ollama['http']} OK — models returned: {ollama['models']}")
        else:
            print(f"  FAILED: {ollama.get('error')}")

    redis = None
    if not args.no_redis:
        print("\n=== Redis :6379 unauth check ===")
        redis = redis_unauth(args.target)
        print("  " + redis.get("status", "n/a") +
              ((" — " + redis["detail"]) if redis.get("detail") else ""))

    grade = node_grade(open_ports, ollama, redis)
    print("\nNODE GRADE:", grade)
    print("OPEN PORTS:", [p["port"] for p in open_ports])
    print("OLLAMA:", ollama)
    print("REDIS:", redis)
    print("JSON:" + json.dumps({"target": args.target, "grade": grade,
                                "open_ports": open_ports, "ollama": ollama,
                                "redis": redis}))


if __name__ == "__main__":
    main()
