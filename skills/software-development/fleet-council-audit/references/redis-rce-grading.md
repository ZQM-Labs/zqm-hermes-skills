# Redis exposure grading — "exposed" vs "live RCE feasible"

## Why this exists
A fleet audit finding "Redis :6379 open to LAN" undersells the risk. On Redis <3.2 there is
NO `protected-mode` (that feature landed in 3.2.0). If `requirepass` is empty AND an
unauthenticated `CONFIG GET` succeeds, an attacker on the LAN can run `CONFIG SET dir <writable>
dbfilename <evil>` then trigger a `SAVE` -> arbitrary file write -> RCE. So the correct severity
is CRITICAL RCE, not "exposure / warn".

## Grading recipe (read-only, no creds needed if unauth)
```python
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
    return buf  # MUST stay BYTES for parse()

def parse(b):
    if not b: return None
    if isinstance(b, str): b = b.encode()   # defends against a caller that pre-decoded
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
            else: out.append(lines[i].decode(errors="ignore")); i += 1
        return out
    return b.decode(errors="ignore")

ip, port = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 6379
vals = {}
for k in ["requirepass", "bind", "protected-mode", "dir", "dbfilename"]:
    v = parse(redis(ip, port, "CONFIG", "GET", k))
    if isinstance(v, list) and len(v) == 2: v = v[1]
    vals[k] = v
print(vals)
```
Reusable wrapper: `scripts/redis_forensic_probe.py` (it returns bytes from `redis()`, which is
what `parse()` expects — see GOTCHA below).

## Severity decision
- `requirepass` empty + `CONFIG GET` works unauth:
  - `dir` is a service-writable path (e.g. `C:\Program Files\Redis`) AND `bind` empty (not
    `127.0.0.1`) -> **CRITICAL: live RCE primitive** (file-write via `CONFIG SET dir/dbfilename`).
  - `bind=127.0.0.1` only -> unauth read is local-only; downgrade to INFO (still set a pw).
- `requirepass` set + PING returns `-NOAUTH` -> INFO (auth-gated, no RCE).
- `PING` returns `+PONG` with no auth but `protected-mode:yes` (Redis >=3.2) -> Redis will
  REFUSE CONFIG SET from a non-loopback, unauth client; severity stays "exposure" not RCE.

## STR-vs-BYTES GOTCHA (bit me live 2026-07-11)
If you `return buf.decode(...)` from `redis()` instead of raw `buf`, then `parse()` later calls
`b.decode(errors="ignore")` on an already-decoded `str` -> `AttributeError: 'str' object has no
attribute 'decode'`. Keep `redis()` returning BYTES. The shipped `redis_forensic_probe.py` already
does this correctly — only ad-hoc copies of the function hit the bug. Also: a multibulk
`CONFIG GET x` reply is `[key, value]`; collapse `if isinstance(v,list) and len(v)==2: v=v[1]`.

## CONFIG GET * PARSE GOTCHA (HIT 2026-07-11 deep-scan)
A bare `CONFIG GET *` returns a multibulk whose EVEN elements are config KEYS and ODD elements are
VALUES, interleaved. Naive `parse_pairs` that splits on `\r\n` and pairs `[i]→[i+1]` MIS-PARSES when
a value itself contains a line starting with `$` (e.g. `pidfile : /var/run/redis.pid` returns a
value whose RESP framing re-injects `$`-prefixed lines, so the "value" of `pidfile` lands as `$9`
and the real path falls onto the next key). SYMPTOM: config dump looks garbled / values shifted by
one column. FIX: do NOT hand-parse `CONFIG GET *`. Either (a) query KNOWN keys individually
(`CONFIG GET requirepass` etc. — each is a clean 2-element bulk), or (b) if you need the full dump,
parse RESP properly: walk the top-level `*N` array, and for each element read its `$len\r\n<bytes>\r\n`
framing to extract the key, then the next framed element as its value — never assume line structure.
The security-relevant keys (requirepass/bind/protected-mode/dir/dbfilename) come through cleanly
even in a garbled full dump, so grade severity from those individually-queried values and don't
depend on the full-dump parse. ALSO: the `/var/run/redis.pid` pidfile value (a *nix-style path) on
a Windows Redis install is itself a tell — it means the default config was never customized, i.e.
the instance is a stock leftover, not a purpose-built service (supports the "orphaned dependency"
hypothesis when deciding whether locking it down is low-risk).

## DEEP-PROBE DATE FIELDS (fuse into the single-subject brief)
From `INFO ALL` you can derive a timeline WITHOUT the broken full-dump parse:
- PROCESS STARTED = now - `uptime_in_seconds` (both from the live probe; convert to ISO).
- LAST RDB SAVE = `datetime.utcfromtimestamp(int(rdb_last_save_time))` (epoch in INFO).
- `total_connections_received` / `total_commands_processed` / `instantaneous_ops_per_sec` +
  the `COMMANDSTATS` block tell you whether any REAL app is using Redis or if every command is
  YOUR probes (this session: 53 commands over 4h, all from the agent's own info/config/keys probes
  -> strong "nothing else uses it" signal).
- `CLIENT LIST` shows every connected client's source IP; `connected_clients:1` = just you.
- `SLOWLOG GET 10` reveals exactly which commands ran (and when, in epoch) — an empty/self-only
  slowlog (your own CONFIG GET + PING) = no prior third-party intrusion, just an exposed surface.
Fuse these with the version-lifecycle dates from `references/redis-version-lifecycle.md` (and a
parallel web-search when the version is novel) into the brief. The "scan deeply around X + its
critical dates" verb specifically wants the DATED timeline + AGE grading.

## Live case (ZQM fleet, 2026-07-11)
Node-2 `192.168.1.21:6379` -> redis_version 3.0.504 (no protected-mode), requirepass EMPTY,
bind EMPTY, dir=`C:\Program Files\Redis`, dbfilename=`dump.rdb`. Unauth `CONFIG GET` succeeded.
Verdict: **CRITICAL, live RCE primitive** for any host on 192.168.1.0/24. Recorded as a 2nd
critical finding (alongside the basic "unauthenticated" finding). Fix: set strong requirepass
+ `bind 127.0.0.1` (or firewall 6379) on Node-2 — needs this session's per-node WinRM
break-glass pw, so it stays gated behind explicit GO.
