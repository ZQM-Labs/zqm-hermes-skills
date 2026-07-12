#!/usr/bin/env python3
"""remote_forensics_probe.py — read-only unauthenticated LAN forensics.

Probes a target for: (a) Redis :6379 unauth exposure (RESP socket protocol),
(b) Ollama :11434 protocol health (version/tags/ps/embed/generate variance).
No creds needed for the unauth path. Run from the Node-1 sandbox (can reach
192.168.1.0/24). Prints raw evidence; writes nothing by default.

Usage:  python remote_forensics_probe.py <ip> [--redis-port 6379] [--ollama-port 11434]
"""
import socket, json, sys, time, argparse, urllib.request, urllib.error

def redis(ip, port, *args, to=4):
    cmd = f"*{len(args)}\r\n" + "".join(f"${len(a)}\r\n{a}\r\n" for a in args)
    with socket.create_connection((ip, port), timeout=to) as s:
        s.sendall(cmd.encode()); s.settimeout(to); buf = b""
        while True:
            try: c = s.recv(65536)
            except socket.timeout: break
            if not c: break
            buf += c
            if buf.endswith(b"\r\n") and buf[:1] in b"+-:$*": break
            if len(buf) > 60000: break
    return buf

def parse(b):
    if not b: return None
    if b[:1] == b"+": return b[1:].decode(errors="ignore").strip()
    if b[:1] == b"-": return "ERR:" + b[1:].decode(errors="ignore").strip()
    if b[:1] == b":": return int(b[1:])
    if b[:1] == b"$":
        n = int(b[1:].split(b"\r\n")[0]); 
        if n == -1: return None
        return b.split(b"\r\n", 1)[1][:n].decode(errors="ignore")
    if b[:1] == b"*":
        lines = b.split(b"\r\n"); count = int(lines[0][1:]); out = []; i = 1
        while i < len(lines) and len(out) < count:
            if lines[i][:1] == b"$":
                ln = int(lines[i][1:]); i += 1
                out.append(lines[i][:ln].decode(errors="ignore")); i += 1
            else:
                out.append(lines[i].decode(errors="ignore")); i += 1
        return out
    return b.decode(errors="ignore")

def ollama_get(ip, port, path, to=8):
    try:
        with urllib.request.urlopen(urllib.request.Request(f"http://{ip}:{port}{path}"), timeout=to) as r:
            return ("OK", json.loads(r.read().decode()))
    except urllib.error.HTTPError as e: return ("HTTP"+str(e.code), None)
    except Exception as e: return ("ERR:"+str(e)[:50], None)

def ollama_gen(ip, port, model, to=35):
    body = json.dumps({"model": model, "prompt": "x", "stream": False, "options": {"num_predict": 2}}).encode()
    try:
        t0 = time.time()
        with urllib.request.urlopen(urllib.request.Request(f"http://{ip}:{port}/api/generate", data=body, headers={"Content-Type":"application/json"}), timeout=to) as r:
            r.read()
        return ("OK", int((time.time()-t0)*1000))
    except Exception as e: return ("HANG/ERR", str(e)[:60])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ip"); ap.add_argument("--redis-port", type=int, default=6379)
    ap.add_argument("--ollama-port", type=int, default=11434)
    a = ap.parse_args()
    print(f"=== FORENSIC PROBE {a.ip} ===")
    # Redis
    try:
        with socket.create_connection((a.ip, a.redis_port), timeout=0.8): pass
        print(f"\n[Redis :{a.redis_port}] OPEN")
        p = parse(redis(a.ip, a.redis_port, "PING"))
        print("  PING:", repr(p))
        if p == "+PONG":
            info = parse(redis(a.ip, a.redis_port, "INFO", "all")) or ""
            for sec in ["# Server", "# Memory", "# Replication", "# Keyspace"]:
                if sec in info:
                    blk = info.split(sec)[1].split("#", 1)[0]
                    print("  " + sec)
                    for ln in [x for x in blk.strip().splitlines() if x and not x.startswith("#")][:8]:
                        print("    " + ln)
            rp = parse(redis(a.ip, a.redis_port, "CONFIG", "GET", "requirepass"))
            print("  CONFIG GET requirepass:", rp)
            cl = redis(a.ip, a.redis_port, "CLIENT", "LIST")
            print("  CLIENT LIST:", cl.strip()[:160])
            print("  VERDICT: UNAUTHENTICATED REDIS -> CRITICAL (RCE-capable)")
        else:
            print("  VERDICT: auth required -> good")
    except Exception as e:
        print(f"\n[Redis :{a.redis_port}] closed/not present ({e})")
    # Ollama
    print(f"\n[Ollama :{a.ollama_port}]")
    v = ollama_get(a.ip, a.ollama_port, "/api/version")
    print("  version:", v[0], v[1] if v[0]=="OK" else "")
    t = ollama_get(a.ip, a.ollama_port, "/api/tags")
    print("  tags:", t[0], (f"count={len(t[1]['models'])}") if t[0]=="OK" else "")
    ps = ollama_get(a.ip, a.ollama_port, "/api/ps")
    print("  ps:", ps[0], (json.dumps(ps[1])[:120]) if ps[0]=="OK" else "")
    if t[0] == "OK":
        smallest = min((m["name"] for m in t[1]["models"]), key=lambda n: int((n.split(":")[-1].replace("b","") or 0) or 1e9))
        for i in range(3):
            st, ms = ollama_gen(a.ip, a.ollama_port, smallest)
            print(f"  generate({smallest}) run{i+1}:", f"{ms}ms" if st=="OK" else st)
            time.sleep(1)

if __name__ == "__main__":
    main()
