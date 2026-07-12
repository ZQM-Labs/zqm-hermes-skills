import socket, time, sys

# Redis UNAUTH forensic trace (read-only). No redis-cli needed.
# Usage: python redis_trace.py <host> <port>
HOST = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.21"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 6379

def cmd(c):
    s = socket.socket(); s.settimeout(4)
    try:
        s.connect((HOST, PORT))
        s.sendall((c + "\r\n").encode())
        time.sleep(0.3); raw = b""
        try:
            while True:
                d = s.recv(65536)
                if not d: break
                raw += d
        except socket.timeout:
            pass
        return raw.decode(errors="replace")
    finally:
        s.close()

print("=== %s:%d REDIS TRACE (read-only) ===" % (HOST, PORT))
print("PING ->", cmd("PING").strip())
for line in cmd("INFO server").splitlines():
    if line.startswith(("redis_version", "redis_mode", "uptime_in_seconds",
                        "uptime_in_days", "arch_bits", "os ", "process_id")):
        print("  ", line)
for k in ["bind", "requirepass", "protected-mode", "port", "dir",
          "dbfilename", "appendonly", "databases"]:
    r = cmd("CONFIG GET " + k)
    parts = r.replace("\r\n", "\n").split("\n")
    val = parts[4] if len(parts) > 4 else r.strip()
    print("  CONFIG %s = %s" % (k, val[:90]))
ks = cmd("INFO keyspace")
print("  KEYSPACE:", [l for l in ks.splitlines() if l.startswith("db")])
cl = cmd("INFO clients")
for l in cl.splitlines():
    if l.startswith(("connected_clients", "blocked_clients")):
        print("  ", l)
mem = cmd("INFO memory")
for l in mem.splitlines():
    if l.startswith(("used_memory_human", "used_memory_peak_human")):
        print("  ", l)
cll = cmd("CLIENT LIST")
print("  CLIENT LIST:")
for l in cll.splitlines():
    if l.strip():
        print("    ", l[:130])
