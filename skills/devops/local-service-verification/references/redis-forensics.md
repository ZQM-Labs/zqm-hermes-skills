# Redis UNAUTH forensic root-cause (Windows, no redis-cli)

Use when a Redis on the LAN/localhost answers `PING` with `+PONG` and no
`AUTH` was sent. This proves the exposure is live and lets you classify
ACCIDENTAL (default config) vs BY-DESIGN before recommending a fix.

## Raw-socket probe (no redis-cli needed)
Redis speaks RESP over a plain TCP socket. From Python (git-bash safe):

    import socket, time
    def cmd(host, port, c):
        s = socket.socket(); s.settimeout(4)
        s.connect((host, port))
        s.sendall((c + "\r\n").encode())
        time.sleep(0.3); raw = b""
        try:
            while True:
                d = s.recv(65536)
                if not d: break
                raw += d
        except socket.timeout: pass
        finally: s.close()
        return raw.decode(errors="replace")

## Genesis evidence to pull (the smoking gun)
    PING                 -> +PONG           # confirms unauth works
    CONFIG GET bind       -> ""  (empty)    # listens on ALL ifaces
    CONFIG GET requirepass -> ""             # no auth
    CONFIG GET protected-mode -> "*0"        # 0 == DISABLED (key switch!)
    CONFIG GET dir / dbfilename / appendonly / databases
    INFO server           -> redis_version, uptime_in_seconds, process_id
    INFO keyspace        -> db0:keys=N      # how loaded
    INFO clients         -> connected_clients
    CLIENT LIST          -> who is connected (your IP vs unknown)

## Classification rule
- `bind` empty + `requirepass` empty + `protected-mode *0`  ->  **ACCIDENTAL**
  (vanilla install, protective switches disabled, never hardened). NOT by-design.
- If `requirepass` is set but you reached it unauth -> misroute/another instance.
- Contrast with an INTENTIONAL exposure: e.g. an Ollama fleet bound to LAN IPs
  with a comment in litellm_config.yaml ("Hot LB = N2 open") = BY DESIGN mesh.

## Reliability hazard (separate from security)
An unauth LAN Redis is also a reliability landmine: any host on the subnet can
`FLUSHALL`, `CONFIG SET dir` + `dbfilename` to write arbitrary files, or
`MODULE LOAD`. Flag both: CRITICAL (RCE) + reliability (wipe risk).

## Remediation (needs node cred; staged, WhatIf-safe)
1. Immediate, no restart: `CONFIG SET requirepass <strong>`
2. Lock to loopback: `CONFIG SET protected-mode yes` + `CONFIG SET bind 127.0.0.1`
   + firewall block :6379 on LAN.
3. Persist: `CONFIG REWRITE` (writes redis.conf) so it survives restart.
Re-run this probe after to confirm `+NOAUTH` / connection refused.

## Session note (ZQM fleet, 2026-07-11)
N2 (192.168.1.21:6379) was vanilla Memurai/MSOpenTech Redis 3.0.504:
bind empty, requirepass empty, protected-mode *0, uptime ~10h, db0:keys=1,
695KB — an orphan/test instance with ONE stale idle conn from N1. The only
ACCIDENTAL exposure in an otherwise by-design-exposed fleet. The Ollama LAN
exposure was intentional (ZBit mesh); the Redis was not.
