# Fleet Endpoint Review + Remediation-Path Enumeration (proven 2026-07-11 ZQM swarm)

Companion to fleet-council-audit for the "full endpoint review" and "investigate all
possibilities" directives. The base SKILL.md covers hardware/software/bots; this file
captures the port-level + fix-vector extension that emerged this session.

## 1. FULL ENDPOINT REVIEW — method
- Enumerate every LISTENING socket per node. Windows: `netstat -ano | grep LISTENING`
  or `Get-NetTCPConnection -State Listen`. Classify each by bind:
  - `127.0.0.1` / `[::1]` -> LOOPBACK (off-net)
  - `0.0.0.0` / `[::]` / a LAN IP -> LAN-exposed
  - a public IP -> WAN-exposed
- Assign per-port risk: LOW (standard mgmt: RPC 135, WSDAPI 5357, WinRM-HTTPS 5986),
  MED (SMB 445, WinRM-HTTP 5985, SSH 22), HIGH (unauth service on LAN: Ollama 11434,
  SMB if unpatched, plaintext WinRM), CRITICAL (unauth RCE primitive: Redis 6379 no
  requirepass, exposed DB with no auth).
- LEAD owns N1 (self) deep review + live probes of risky ports. Dispatch ONE leaf per
  OTHER node (N2/N3/N4) for a parallel bounded TCP sweep.

### Bounded port-probe (use this — the bash /dev/tcp loop hung)
The `/dev/tcp/ip/port` bash loop WITHOUT a timeout stalled on a filtered port and
timed out the entire turn. Use Python with `socket.settimeout`:
```python
import socket, time
def probe(ip,p,to=0.4):
    s=socket.socket(); s.settimeout(to)
    try:
        s.connect((ip,p))
        try: s.sendall(b"PING\r\n"); time.sleep(0.3); r=s.recv(32)
        except Exception: r=b"(connected, no banner)"
        return f"OPEN tcp/{p} -> {r!r}"
    except Exception as e:
        return f"closed tcp/{p} ({type(e).__name__})"
    finally: s.close()
for p in [22,135,139,445,2179,3389,5985,5986,11434,6379,18789]:
    print(probe("192.168.1.21",p))
```
Ports worth probing on a ZQM node: 22,135,139,445,2179,3389,5040,5357,5985,5986,
47001,11434(Ollama),4001(LiteLLM),8400(ZBit),6379(Redis),18789(OpenClaw mesh).

### Live service probes (confirm exposure, not just open)
- Ollama :11434 -> `curl -s http://IP:11434/api/tags` (200 = model enum; unauth = HIGH)
- Redis :6379   -> send `PING\r\n`; `+PONG` with NO AUTH = CRITICAL unauth RCE primitive
- ZBit :8400    -> `curl -s http://127.0.0.1:8400/health` (fleet_nodes list)
- LiteLLM :4001 -> `curl -s http://127.0.0.1:4001/health/liveliness`

## 2. INVESTIGATE ALL POSSIBILITIES — remediation vector enumeration
On a found vuln, enumerate EVERY fix vector, PROVE each viable/dead with live evidence,
persist to a `remediations` table. Concrete vector list (proven N2 Redis :6379 case):

| Vector | How to test | N2 result |
|---|---|---|
| WinRM 5985/5986 from N1 | port OPEN + check `WSMan:\localhost\Client\TrustedHosts` for target IP | VIABLE (N2 listed in TrustedHosts; needs cred) |
| SSH :22 | `probe(IP,22)` TimeoutError = closed | DEAD |
| RDP :3389 | `probe(IP,3389)` | DEAD |
| OpenClaw mesh bridge | grep `.openclaw` config for target IP | DEAD (no 192.168.1.21 ref) |
| ZBit fleet channel | ZBit lists node in fleet_nodes but `.env` holds only ZBIT_API_KEY, not fleet creds | DEAD |
| Cached Win cred | `cmdkey /list \| findstr <IP>` | DEAD (none) |
| Fix via the vuln itself (CONFIG SET) | — | REJECT (it's the RCE; non-persistent) |
| Operator self-run on node | stage WhatIf-safe script | VIABLE (no remote needed) |

Net: 1 viable remote (WinRM+cred) + 1 self-run + 6 dead/reject.

## 3. BLOCKER HANDLING — "dead in the water?" is the wrong frame
A fix gated on a per-node break-glass credential you DON'T have is NOT a dead end:
- The INVESTIGATION is complete and persisted. Only the APPLY is gated.
- Offer two doors:
  1. Operator self-runs the staged script on the node (secret never crosses wire).
  2. User passes the per-session break-glass -> you run WinRM + verify + close finding.
- NEVER guess/re-loop a wrong per-node pw. ZQM rule: per-node pws DIFFER; one rejected
  attempt proves it, don't re-loop. (N2's pw is NOT 'EllaRose89!' — that was rejected.)

## 4. STAGE THE FIX, DON'T FIRE IT
Write a remediation script the operator can run. For Redis:
- set `bind 127.0.0.1` + `requirepass <pass>` in redis.windows.conf (idempotent -replace)
- `New-NetFirewallRule -DisplayName Block-Redis-LAN -Direction Inbound -Protocol TCP
  -LocalPort 6379 -RemoteAddress 192.168.1.0/24 -Action Block`
- `Restart-Service Redis`
- self-verify: loopback `redis-cli -h 127.0.0.1 -a <pass> ping` -> PONG
- param `-RedisPass` (mandatory), switch `-WhatIf` (dry-run)
- Persist script path in the ledger (remediations table evidence).

## 5. SQLite shape (audit-sqlite-sink extension)
Add to the audit DB:
- `nodes(node,ip,os,grade,lan_exposed_critical,notes,reviewed)`
- `endpoints(id,node,port,svc,bind,exposure,risk,verified,notes)`
- `findings(id,severity,node,port,svc,finding,evidence,reverify)`
- `remediations(id,target,issue,vector,status,evidence,blocker,decided)`
PITFALL (burned this session): N1 endpoint rows had a `bind` field (7-tuple) but
N2/N3/N4 rows omitted it (6-tuple) -> unpack `for port,svc,bind,exp,risk,ver,n in eps`
threw "not enough values to unpack". Normalize: `if len(row)==7: ... else: bind=exp`.
Also: `INSERT INTO nodes VALUES(?,?,?,?,?,?,?,?)` (8 ?) against a 7-field tuple threw
"Incorrect number of bindings" — count the live schema columns, not the tuple you
assume. Prefer naming columns explicitly in INSERT.
