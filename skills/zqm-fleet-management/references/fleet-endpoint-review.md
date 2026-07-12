# Fleet Endpoint Review + Remediation-Path Analysis

Reusable method + schemas for the user's "investigate all systems" / "full endpoint
review" / "investigate all possibilities" verbs. LEAD does Node-1 deep review; 3
parallel `delegate_task` leaves sweep N2/N3/N4. Everything lands in ONE SQLite ledger.

## 1. Bounded port probe (give leaves this; 0.4s/port, no hang)
```python
import socket
PORTS = {22:"SSH",135:"RPC",139:"NetBIOS",445:"SMB",2179:"VM-RDP",
 3389:"RDP",5357:"WSDAPI",5985:"WinRM-HTTP",5986:"WinRM-HTTPS",
 47001:"WinRM-CBD",11434:"Ollama",4001:"LiteLLM",8400:"ZBit-Agent",
 6379:"Redis",18789:"OpenClaw-MESH"}
def probe(ip,to=0.4):
    res={}
    for p,svc in PORTS.items():
        s=socket.socket(); s.settimeout(to)
        try:
            s.connect((ip,p)); res[p]=svc
        except: pass
        finally: s.close()
    return res   # only OPEN ports returned
```

## 2. Risk-grade scale
- CRITICAL = pre-auth RCE from LAN, no creds (unauth Redis :6379). Caps node grade.
- HIGH = unauth service leaking assets (Ollama :11434; SMB/WinRM-HTTP pre-auth surface).
- MED = plaintext mgmt / loopback-but-open (LiteLLM no master_key).
- LOW = standard Win surface (RPC/NetBIOS/WSDAPI) / loopback-only.

## 3. Consolidation SQLite schema
```sql
CREATE TABLE nodes (node TEXT, ip TEXT, os TEXT, grade TEXT,
  lan_exposed_critical TEXT, notes TEXT, reviewed TEXT);
CREATE TABLE endpoints (id INTEGER PRIMARY KEY, node TEXT, port INTEGER, svc TEXT,
  bind TEXT, exposure TEXT, risk TEXT, verified TEXT, notes TEXT);
CREATE TABLE findings (id INTEGER PRIMARY KEY, severity TEXT, node TEXT, port INTEGER,
  svc TEXT, finding TEXT, evidence TEXT, reverify TEXT);
CREATE TABLE remediations (id INTEGER PRIMARY KEY, target TEXT, issue TEXT, vector TEXT,
  status TEXT, evidence TEXT, blocker TEXT, decided TEXT);
CREATE TABLE meta (k TEXT, v TEXT);
```
- `findings` = discovered exposures (CRITICAL/HIGH/MED/LOW).
- `remediations` = per-vector viability for the TOP finding:
  VIABLE-BLOCKED (WinRM+cred) / VIABLE (self-run) / DEAD (ssh,rdp,mesh,agent,cmdkey) /
  REJECT (fix-via-vuln) / REPORT-ONLY (out of scope).

## 4. Staged fix script skeleton (idempotent, WhatIf-safe; do NOT run without cred)
```powershell
param([Parameter(Mandatory=$true)][string]$RedisPass,[switch]$WhatIf)
# 1. conf: bind 127.0.0.1 + requirepass  (idempotent -replace)
# 2. New-NetFirewallRule -DisplayName Block-Redis-LAN -Direction Inbound `
#      -Protocol TCP -LocalPort 6379 -RemoteAddress 192.168.1.0/24 -Action Block
# 3. Restart-Service Redis -Force
# 4. verify loopback PONG with auth; from Node-1 re-probe LAN PING -> expect NOAUTH/timeout
```
Rule: write it, hand it (or run -WhatIf), but gate execution on the node's break-glass
cred. If that cred was REJECTED before, do NOT re-loop — one retry proves it; ask for
the real cred or the self-run path.

## 5. Active-session diagnostic (separates exposure from intrusion)
```
netstat -ano | grep ESTABLISHED | grep -E ":11434|:4001|:8400|:5985|:445|:135|:6379"
# + check NON-fleet peers: netstat ... | grep ESTABLISHED | awk '{print $3}' | grep -vE "127.0.0.1|192.168.1.(218|21|46|215)"
```
Clean session list + `PING->+PONG` on the vuln = "door unlocked, nobody inside yet" =
still CRITICAL. Report CONFIG-LEVEL EXPOSURE vs ACTIVE ANOMALY explicitly.

## 6. Proven verdicts this session (2026-07-11, 4 nodes, 51 endpoints)
- N1 .218 MEDIUM-HIGH (Ollama :11434 LAN + WinRM open; loopback services clean)
- N2 .21 CRITICAL(F) — unauth Redis :6379 (REAL `+PONG` no-auth from N1)
- N3 .46 HIGH — mgmt/legacy surface; Ollama localhost-bound (good)
- N4 .215 HIGH — unauth Ollama (45 models) + SMB
- Remediation vectors for N2 Redis: WinRM VIABLE-BLOCKED (N2 in N1 TrustedHosts) /
  self-run VIABLE / ssh+rdp+mesh+agent+cmdkey DEAD / redis-self REJECT.
Artifacts: C:\Users\zqmco\swarm\fleet_endpoint_review\ (fleet_endpoint_audit.db +
consolidate_fleet.py + n2_redis_fix.ps1 + diagnostics.py + analyze_remediations.py).
