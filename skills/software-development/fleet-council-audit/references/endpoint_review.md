# Full Endpoint Review — per-node port sweep + fleet rollup

Technique developed during 2026-07-11 "investigate all systems / full endpoint review".

## Shape
- LEAD owns Node-1 (self): full `netstat -ano | grep LISTENING`, classify every listener (bind 0.0.0.0/[::]=LAN-exposed, 127.0.0.1/[::1]=loopback), live-probe risky ones (curl/nc).
- Spawn N parallel leaf subagents (delegate_task, batch mode, max 3) — one per remote node. Each does a bounded TCP port probe + per-port risk grade. LEAD does NOT poll; leaves re-enter as one message.
- Consolidate all into ONE SQLite ledger (nodes, endpoints, findings, meta) — see audit-sqlite-sink for the persistent/claim-chain pattern.

## Bounded port probe (hand each leaf this, self-contained — no file dependency)
```python
import socket, sys, time
TARGET = sys.argv[1]
TO = float(sys.argv[2])/1000 if len(sys.argv)>2 else 0.4
PORTS = {22:"SSH",135:"RPC",139:"NetBIOS",445:"SMB",2179:"VM-RDP",3389:"RDP",
 5040:"WinNAT",5357:"WSDAPI",5985:"WinRM-HTTP",5986:"WinRM-HTTPS",47001:"WinRM-CBD",
 11434:"Ollama",4001:"LiteLLM",8400:"ZBit-Agent",6379:"Redis",18789:"OpenClaw-MESH"}
for p in sorted(PORTS):
    s=socket.socket(); s.settimeout(TO); t=time.time()
    try: s.connect((TARGET,p)); st="OPEN"
    except socket.timeout: st="FILTERED"
    except OSError: st="CLOSED"
    s.close()
    print(p, PORTS[p], st)
```
- KEY: 0.4s/port timeout prevents the whole scan hanging (a filtered port on naive /dev/tcp stalls — that's why the LEAD N4 probe timed out earlier; the python socket version fixed it).

## Live checks that proved load-bearing
- Redis unauth: `printf 'PING\r\n' | nc <ip> 6379` → `+PONG` with NO AUTH = CRITICAL RCE primitive. Verify verbatim, never assume.
- Ollama LAN exposure: `curl -s http://<ip>:11434/api/tags` → 200 + model list = LAN-exposed unauth.
- Loopback services (ZBit 8400, litellm 4001, OpenClaw 18789) = low risk if truly 127.0.0.1; still probe to CONFIRM bind, not trust process args.

## Risk grading
- CRITICAL: unauth service reachable from LAN that yields RCE (Redis no-auth, etc.).
- HIGH: LAN-exposed unauth service (Ollama, SMB, plaintext WinRM 5985), pre-auth exploit surface.
- MED: plaintext mgmt plane, loopback-open-but-unkeyed service.
- LOW: standard Windows RPC/WSDAPI/loopback.

## ZQM fleet live state (2026-07-11, re-probe each turn — drifts)
- N1 192.168.1.218: Ollama 11434 LAN-exposed (HIGH); 22/445/5985/5986 open; ZBit 8400 + litellm 4001 loopback; Redis CLOSED. Node grade MEDIUM-HIGH.
- N2 192.168.1.21: 🔴 CRITICAL — Redis 6379 UNAUTH (PING→+PONG); Ollama 11434 unauth; SMB/WinRM open. FIX FIRST: requirepass + bind 127.0.0.1.
- N3 192.168.1.46: Ollama 11434 CLOSED on LAN (localhost-bound, good); SMB/RPC/WinRM triplet HIGH. Grade HIGH.
- N4 192.168.1.215: Ollama 11434 unauth (45 models/450GB); SMB HIGH. Grade HIGH.

## Pitfalls
- Don't `git add .` anything near the skills repo (SECRETS in tree — see memory).
- Remote fix (e.g. N2 Redis requirepass) needs explicit consent + per-node break-glass pw; NOT applied in a read-only review.
- Consolidation script bug pattern: keep tuple shapes consistent across nodes (N1 rows had bind field, N2/N3/N4 omitted it → normalize by len(row) in the insert loop). Schema col count must match INSERT list exactly.
