# ZQM Fleet Forensics (unauthenticated read-only evidence collection)

Class of work: collecting HARD, probe-backed evidence from a LAN peer WITHOUT
holding that node's admin/break-glass credential. The ZQM sandbox (Node-1
192.168.1.218) can reach 192.168.1.0/24 directly, so many "needs Node-2 creds"
questions are actually answerable with zero creds — by speaking the service's
own plaintext protocol over a socket.

## Why this exists
A symptom probe (port open? generate hangs?) is NOT root cause. The user asked
for "diagnostics and forensic science" — that means read-only protocol-level
evidence, then a verdict, NOT an immediate fix. Fixing without evidence risks
acting on a transient fluke (this session: Node-2 Ollama generate "hang" was a
flap, not a dead GPU).

## PATTERN 1 — Unauthenticated Redis forensics (no creds)
Redis 3.0.504 on Windows (seen on Node-2 .21:6379) has NO ACL subsystem — only
`requirepass`. A `PING` that returns `+PONG` with no auth PROVES it is an
unauthenticated RCE surface. Read everything else unauth:

RESP wire format (send `*N\r\n$len\r\nARG\r\n...`, read reply):
  - `+...` inline/status  -> e.g. `+PONG`
  - `-...` error          -> e.g. `-NOAUTH Authentication required`
  - `:N`  integer
  - `$N\r\n<body>\r\n` bulk string (N=-1 = nil)
  - `*N\r\n...` multibulk (N = count of following bulk/inline items)
Use a raw `socket.create_connection` + `sendall`; parse the bulk/multibulk
reply yourself (don't assume one recv gets it all — loop until `\r\n` ends a
complete reply, cap at ~60KB). Reusable: `scripts/remote_forensics_probe.py`.

Commands that PROVE state (all unauth if requirepass empty):
  - `PING`                   -> if `+PONG` unauth => CRITICAL exposure
  - `CONFIG GET requirepass` -> `*` bulk; empty `$0` value = no password
  - `INFO all`               -> version, role, uptime, memory, clients, keyspace
  - `CLIENT LIST`            -> who is connected (src IP = access evidence)
  - `DBSIZE` + `KEYS *`      -> data present? (small = low blast radius)
  - `TTL <key>` / `PTTL`     -> -1 = persistent; note YOUR probe keys land here
  - `SLOWLOG GET 10`         -> command history (empty = untouched since boot)

Verdict logic: open + `PING`->`+PONG` + `requirepass` empty = critical, RCE-capable.
If SLOWLOG shows only your own probes and keyspace ~1 key, note "exposed but
holding no valuable data, no prior-intruder evidence" — still fix, report radius honestly.

## PATTERN 2 — Ollama protocol diagnostics (separate the fault axes)
  - `/api/version`  -> cheap, proves process up + version (0.31.2).
  - `/api/tags`     -> lists models; slow/timeout = server/manifest stuck.
  - `/api/ps`       -> loaded models + VRAM. DYNAMIC — timestamp it.
  - `/api/embed`    -> embedding models ONLY; text-gen model -> 400 here.
  - `/api/generate`-> the inference path; GPU/VMM faults surface here.
FAULT MATRIX (Node-2 .21 this session):
  tags OK (8) + /api/ps empty + generate HANGS 30s+ (HTTP 000) = GPU/VMM-stuck
  pattern. BUT re-probe 2 min later -> generate 300-2600ms. => ONE timeout is NOT
  proof of a dead card; it is an INTERMITTENT flap (VRAM contention). Distinguish
  from cold-load stall (first generate slow, retry -> fast; N4 :11435 went 30s->2.67s).
  A dead VMM does NOT recover on retry.
VERDICT RULE: classify generate OK/SLOW(>15s)/HANG, RE-RUN 2-3x before "persistent".
Log every attempt's raw ms — that IS the evidence.

## PATTERN 3 — TCP "open" is NOT proof of a listener (FALSE POSITIVE trap)
A `socket.connect` success (or a reset the OS reports as "answered") is weaker
than a full 3-way handshake. This session: a connect sweep reported `:23 Telnet
OPEN` on G1/G2/NAS; a council leaf's handshake probe showed NO `:23` (connect had
hit a scanner-host-side reset artifact).
MITIGATION: when a surprising port appears, confirm with a second method (HTTP GET
/ banner / handshake) before reporting. Prefer the council's handshake-confirmed
inventory over a single connect() sweep. Never report exposure on connect() alone.

## PATTERN 4 — Topology corrections (2026-07-11)
  - "Gateway G1" (.173) / "Gateway G2" (.40) are Synology DSM 7.x appliances
    (ZQM-Garden-01 / ZQM-GARDEN-02), NOT HA, NOT routers. `:5000` = HTTP->HTTPS
    redirect stub; `:5001` = DSM login (open on both).
  - NO Home Assistant: `:8123` CLOSED on all 7 hosts. HASS_TOKEN plan is moot
    until an HA host exists on the fleet.
  - NAS .53 = primary Synology DSM (same ZQM-Garden-01 string, + :873 rsync).
  - Node-1 (.218) = OpenSSH_for_Windows_10.0 (newer than N3/N4's 9.5).

## Ledger discipline (shared with fleet-council-audit)
When a finding is SUPERSEDED (e.g. "persistent Ollama hang" -> "intermittent
flap"), RETRACT it (UPDATE severity='retracted' + append the correction) — do NOT
silently DELETE. A retracted row with its reason is honest history; a deleted row
hides that you were wrong. This session retracted both the false `:23 Telnet`
finding and the false "persistent Ollama dead-GPU" finding, recording why.
