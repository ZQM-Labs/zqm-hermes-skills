#!/usr/bin/env python3
"""Redis UNAUTH forensic read — raw RESP over socket, no creds needed if requirepass is empty.
Reusable for homelab security audits: proves unauth access AND reveals access history.
Usage: python redis_forensic_probe.py <host> <port=6379>
Reads: PING, INFO all, CLIENT LIST, SLOWLOG, DBSIZE, KEYS *, TTL/GET of each key, CONFIG GET requirepass.
Read-only. Never writes.
"""
import socket, sys

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
    return buf

def parse(b):
    if not b: return None
    if b[:1] == b"+": return b[1:].decode(errors="ignore").strip()
    if b[:1] == b"-": return "ERR:" + b[1:].decode(errors="ignore").strip()
    if b[:1] == b":": return int(b[1:])
    if b[:1] == b"$":
        n = int(b[1:].split(b"\r\n")[0])
        if n == -1: return None
        return b.split(b"\r\n", 1)[1][:n].decode(errors="ignore")
    if b[:1] == b"*":
        lines = b.split(b"\r\n"); count = int(lines[0][1:]); out = []; i = 1
        while i < len(lines) and len(out) < count:
            if lines[i][:1] == b"$":
                ln = int(lines[i][1:]); i += 1; out.append(lines[i][:ln].decode(errors="ignore")); i += 1
            else:
                out.append(lines[i].decode(errors="ignore")); i += 1
        return out
    return b.decode(errors="ignore")

def main():
    ip = sys.argv[1]; port = int(sys.argv[2]) if len(sys.argv) > 2 else 6379
    print(f"=== Redis forensic read {ip}:{port} (unauth) ===")
    ping = parse(redis(ip, port, "PING"))
    print("PING:", ping, "->", "UNAUTH-OPEN (CRITICAL)" if ping == "+PONG" else ("auth-required" if str(ping).startswith("ERR") else "closed/unreachable"))
    info = parse(redis(ip, port, "INFO", "all")) or ""
    for sec in ["Server", "Clients", "Memory", "Stats", "Replication", "Persistence", "Keyspace"]:
        if f"#{sec}" in info:
            blk = info.split(f"#{sec}")[1].split("#", 1)[0]
            print(f"\n--- {sec} ---")
            for l in [x for x in blk.strip().splitlines() if x and not x.startswith("#")][:14]:
                print("  " + l)
    print("\n--- CLIENT LIST ---")
    for line in (parse(redis(ip, port, "CLIENT", "LIST")) or "").strip().splitlines():
        print("  " + line[:160])
    print("\nDBSIZE:", parse(redis(ip, port, "DBSIZE")))
    print("SLOWLOG:", (parse(redis(ip, port, "SLOWLOG", "GET", "10")) or "")[:400])
    keys = parse(redis(ip, port, "KEYS", "*", to=6)) or []
    print("KEYS:", keys)
    for k in (keys if isinstance(keys, list) else []):
        print(f"  TTL {k}:", parse(redis(ip, port, "TTL", k)), "| GET:", repr(parse(redis(ip, port, "GET", k)))[:60])
    print("CONFIG requirepass:", repr(parse(redis(ip, port, "CONFIG", "GET", "requirepass"))))

if __name__ == "__main__":
    main()
