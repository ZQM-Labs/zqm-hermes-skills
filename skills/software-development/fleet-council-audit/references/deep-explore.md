# Deep Explore — read-only content/relationship/version pass

Used when the user says **"explore deeply"** (or equivalently wants to go past port/service ID
into what's actually running, what data is exposed, what talks to what, and version risk).
OBSERVATION-ONLY: no ledger writes, no remediation, no config change. Reuse the
`scripts/exposure_scan.py` connect engine for the port matrix, then layer the probes below.

## 1. Redis data + role + access history (unauth, RESP over socket)
Redis 3.0.504 on Windows (Node-2 :6379) speaks RESP in plaintext with NO auth. Use a tiny
socket client (see `scripts/redis_forensic_probe.py` for the canonical version) and run:
- `INFO server` -> version, uptime, run_id, config_file path.
- `INFO replication` -> role (master/slave), connected_slaves.
- `INFO clients` -> connected_clients (who is touching it right now).
- `INFO memory` / `INFO keyspace` -> used_memory, db0:keys=N.
- `KEYS *` then `TYPE`/`TTL`/`GET` per key -> what data is actually stored (often just your own
  probe footprint; an empty DB means exposure is an RCE *vector*, not a data *leak*).
- `CLIENT LIST` -> live connection sources (addr=192.168.1.x:port) = access evidence.
- `SLOWLOG GET 10` -> what commands ran historically (catch intruder activity; empty = untouched).
- `CONFIG GET requirepass` / `bind` / `dir` / `dbfilename` -> RCE-primitive grading (see
  `references/redis-rce-grading.md`). Empty requirepass + EMPTY bind + dir under a
  service-writable path = CRITICAL RCE, not just "exposure".

STR TYPE PITFALL: the socket `recv` returns `bytes`; if your `redis()` helper `.decode()`s
before handing to `parse()`, then `parse()` calling `.decode()` on a `str` raises
`AttributeError: 'str' object has no attribute 'decode'`. Keep `redis()` returning **bytes** and
let `parse()` decode — or normalize `parse()` to accept both (`if isinstance(b,str): b=b.encode()`).

## 2. Synology HTTP app enumeration (G1/G2/NAS :80 / :5000 / :7000)
`urllib` GET `/` on each web port; extract `<title>` + Server header + scan the body for
signatures: `Web Station`, `Synology`, `Container` (-> Container Manager / Docker installed),
`webman` (-> DSM desktop reachable on non-standard port), `phpMyAdmin`, `WordPress`, `Portainer`,
`Apache`, `nginx`, `Docker`, `Download Station`, `Photo Station`, `Video Station`,
`Surveillance`, `Node.js`. A bare "Hello! Welcome to Synology Web Station!" on :80 means a web
server faces the LAN — if any Web Station vhost / Container app is misconfigured that's a
secondary surface, but an unauth fingerprint usually shows only the default page. Note: :443/:5001
plain `urllib` fails TLS cert validation (SSL CERTIFICATE_VERIFY_FAILED) — that's expected for DSM
HTTPS, not a finding.

## 3. Ollama runtime detail (Node-2 / Node-4)
- `GET /api/version` -> version string (e.g. `0.31.2`). A `401` means auth is now required
  (changed state — flag, don't assume open).
- `GET /api/ps` -> `models[]` = currently-loaded (VRAM-resident) models. An EMPTY list means no
  model is resident -> explains why generates are fast/cold and WHY an earlier "hang" was just
  cold-load contention, not a fault. `running_models=[]` + occasional 30s timeouts = intermittent
  GPU/VMM flap (see `references/ollama-forensic-variance.md`), NOT a dead card.
- Node-4 :11435 (2nd Ollama) flaps open->closed->timeout across passes — if it's meant to be
  persistent, that's a service-stability item to check, not a security finding.

## 4. Cross-host correlation + version risk
Build a version-risk table per host:
- **Redis 3.0.504** -> END-OF-LIFE (2016), no protected-mode/ACL, known RCE patterns -> upgrade/isolate.
- **OpenSSH 8.2** (Synology) -> 2020 build; CVE-2020-14145 / CVE-2023-38408 class; acceptable if DSM
  on latest 7.2.x. **OpenSSH_for_Windows 10.0 / 9.5** (Node-1/4) -> recent, fine.
- **Synology DSM 7.x** -> keep latest 7.2.x; DSM had CVE-2024-1040/1041 auth-bypass class — verify patched.
- **Ollama 0.31.2** -> <0.34 had CVE-2024-39720 GPU overflow -> minor upgrade candidate.

## 5. Relationship map (what talks to what)
Summarize the fleet as a graph: control-plane (Node-1, scanner) -> AI nodes (Node-2 unauth Redis +
Ollama, Node-4 dual-Ollama) -> Synology units (Web Station + Container Manager on :80/:5000/:7000,
plus FTP/Telnet/NFS). The single genuine exploitable weakness is usually Node-2 Redis; everything
else is expected stock surface or minor version hygiene.

## CONNECT-SCAN BUG (bit us live)
When mapping `scan(ip,p)` results, `filter(None, ex.map(scan, ports))` keeps the RETURN VALUE of
`scan` — if `scan` returns `True` (bool) on success, you get a list of `True`, NOT ports, and every
row prints `srvTrue`. Fix: make `scan` return the PORT on success (`return p`) and `None` on
failure, so `filter(None, ...)` yields the actual port numbers. `scripts/exposure_scan.py` does this
correctly — reuse it.
