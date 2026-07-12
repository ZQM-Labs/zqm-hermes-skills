# Redis Live-Auth (close RCE without node cred)
# ZQM-Computing fleet — 2026-07-11 verified recipe

## When to use
Redis answers `PING` → `+PONG` with no `AUTH` from a remote unauth socket.
You can harden it from the remote session BEFORE any node credential exists.

## The sequence (raw socket, no redis-cli)
```python
import socket, os
HOST,PORT="192.168.1.21",6379
def cmd(s,c):
    s.sendall((c+"\r\n").encode()); time.sleep(0.25); raw=b""
    try:
        while True:
            d=s.recv(65536)
            if not d: break
            raw+=d
    except socket.timeout: pass
    return raw.decode(errors="replace").strip()

# 1. generate strong pass (48 hex) — never hardcode, never persist to a repo file
raw=os.urandom(24); PASS=bytes.hex(raw)

# 2. requirepass takes effect IMMEDIATELY (no restart)
s=socket.socket(); s.connect((HOST,PORT))
print(cmd(s,"CONFIG SET requirepass "+PASS))   # +OK

# 3. NOW every unauth cmd returns NOAUTH — RCE closed from LAN
#    test from a fresh unauth socket: PING -> -NOAUTH Authentication required.

# 4. AUTH on the SAME socket, then set the rest (these may be startup-only on old builds)
print(cmd(s,"AUTH "+PASS))                       # +OK
print(cmd(s,"CONFIG SET protected-mode yes"))    # OK on most; see caveat
print(cmd(s,"CONFIG SET bind 127.0.0.1"))     # OK on most; see caveat
s.close()
```

## CRITICAL caveat — Redis v3.0.504 (Windows / Memurai build)
`CONFIG SET protected-mode` and `CONFIG SET bind` return:
`"-ERR Unsupported CONFIG parameter: bind"` / `"...protected-mode"`.
These are **startup-only** on that build. They MUST go via `redis.windows.conf`
+ a service restart. Live `requirepass` is the only thing that closes RCE immediately;
bind/firewall are defense-in-depth that need node-side execution (N2 break-glass cred).

## Verify after
- From LAN (remote, unauth): `PING` → `-NOAUTH Authentication required.` ✅
- Loopback (on node, AUTHed): `redis-cli -h 127.0.0.1 -a <PASS> ping` → `PONG` ✅

## Consumer trace FIRST (read-only, before locking)
A "stale idle connection" from another host is usually YOUR OWN orphaned probe socket,
not an attacker. Scan the consumer host: `netstat -ano | grep :6379`, map PIDs to
process names, grep the fleet configs for `192.168.1.21:6379` / `redis`. If only
venv libs match (apscheduler jobstores, botocore elasticache examples) → orphan → safe to lock.

## Hygiene
- Display the generated PASS once; operator stores it on the node
  (`C:\ProgramData\Redis\redis.pass`, ACL SYSTEM+Admins only).
- Do NOT write the pass into any git-tracked file (see zqm-repo-inventory-verification:
  SECRETS in tree → `git add` only explicit paths, never `.`).
- Burn the in-session pass after the node-side `n2_redis_auth.ps1` run regenerates + ACL-stores it.
