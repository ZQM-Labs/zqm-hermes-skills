# Endpoint Review / Silent Recon — scan pattern + confirmation recipes

Companion to the SKILL.md `## SILENT RECON` heavy variant. Used by "full silent recon" /
"full endpoint review": scan + probe every host, report live evidence, WRITE NOTHING to
disk/ledger. Pure observation.

## Full TCP exposure scan (the review primitive)
Ports: `range(1,1025)` + a curated high-port list. Use `ThreadPoolExecutor` (≤250 workers).
`socket.create_connection` with 0.3–0.5s timeout; **return the PORT (not a bool)** so the open
list is real ports. A `filter(None, ...)` over a `scan()` that returns `True` keeps `True` and
LOSES the port number — emit the port, not a truthy sentinel.

HIGH ports to always include for this fleet:
```
111,135,139,143,389,443,445,465,587,636,873,993,995,1433,1521,1863,2049,2100,3128,
3306,3389,3690,4369,5000,5001,5432,5672,5900,5985,5986,6379,7000,8000,8080,8443,
8888,9000,9090,9200,9300,11211,11434,11435,18789,27017,50000
```

## Port → service → risk classifier (review output)
```
CRIT : 3306,5432,1521,1433,27017,11211,3389,5900,6379   (DB/desktop exposed)
MED  : 23 telnet, 2049 NFS, 5985 WinRM-HTTP (plaintext)
LOW  : 135,139,445(SMB,null-session denied),111,873,892,662,548,53,161
INFO : 22 SSH, 443/5001/5986 TLS, 80/5000/7000 HTTP, 11434 Ollama /api/version
```
- Telnet `:23` on Synology = **REAL** (IAC-confirmed), NOT a false positive. G1/G2/NAS expose
  21/23/111/2049/892 (+548 AFP on G2). A council leaf's "3-way handshake proved no :23" was
  the buggy check (see TCP-connect pitfall in SKILL.md).
- Node-1 Ollama `:11434` returning HTTP 401 = auth now required (changed state — flag).
  Node-4 `:11435` is intermittent (open/closed across passes).

## Protocol-confirmation recipes (STRONGER than connect()) — prove a port is a real service
`connect()` success alone is weak (scanner-host reset artifacts happen). Confirm with a
real handshake / banner grab before reporting exposure.

Redis (unauth): `socket` -> send `*1\r\n$4\r\nPING\r\n` -> expect `+PONG\r\n`.
  `CONFIG GET requirepass` / `dir` / `bind` / `protected-mode` proves RCE primitive
  (Redis <3.2 has NO protected-mode). RESP parse gotcha: the socket reader must return
  BYTES; if you decode to str first, the parser's `.decode()` call throws AttributeError.
  (Full grading: `references/redis-rce-grading.md`.)

Telnet `:23`: `socket` -> send `b"\xff\xfb\x01"` (IAC WILL ECHO) -> a real daemon replies with
  its own IAC negotiation bytes (`\xff\xfb%...`). connect() alone is not proof.

FTP `:21`: `recv()` after connect -> `220 <host> FTP server ready.\r\n`.

NFS `:2049`: send an RPC NULL call — `xid` + CALL + `rpcvers=2` + `prog=100003` + `vers=4`
  + `proc=0` + `AUTH_NULL` cred/verf (struct-packed `>I`) -> any reply (even empty) confirms
  the NFS service is answering.

SSH `:22`: `recv()` -> `SSH-2.0-<impl>` (OpenSSH_for_Windows_10.0 / 9.5 / OpenSSH_8.2).

HTTP/S: `GET /` -> status + `Server` header + `<title>`. DSM `:5000` body is a JS redirect
  stub (no title); `:5001` plain-HTTP returns `400 ... nginx` (expects HTTPS).

## Output shape
Group by host: `host (ip) — N endpoints`, then one line per port `PORT SERVICE [RISK] evidence`.
End with a RISK TALLY (crit/med/low/info counts). State re-probe facts vs the prior ledger
(e.g. "Node-1 Ollama now 401", "Node-4 :11435 closed this pass") so drift is visible.
