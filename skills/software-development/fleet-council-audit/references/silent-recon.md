# Silent Recon (no-write observation pass)

User command: "full silent recon" / "silent recon". Goal: re-baseline the live fleet
surface with ZERO writes — no SQLite, no file artifacts, no host-state change. Pure
read-only observation. Distinct from the ledger-writing "investigate fully" diagnostic pass.

## Pattern (copy-paste, fill HOSTS)

```python
import socket, time, concurrent.futures, urllib.request

HOSTS = {  # name: ip
 "Node-1":"192.168.1.218","Node-2":"192.168.1.21","Node-3":"192.168.1.46",
 "Node-4":"192.168.1.215","G1":"192.168.1.173","G2":"192.168.1.40","NAS":"192.168.1.53",
}
HIGH=[21,111,135,139,443,445,873,2049,3306,3389,5432,5900,5985,5986,6379,7000,
      8000,8080,8443,9000,9090,9200,11211,11434,11435,18789,27017,50000]
PORTS=sorted(set(list(range(1,1025))+HIGH))
SVCS={21:"FTP",22:"SSH",23:"Telnet",53:"DNS",80:"HTTP",111:"rpcbind",135:"MS-RPC",
      139:"NetBIOS",161:"SNMP",389:"LDAP",443:"HTTPS",445:"SMB",873:"rsync",
      993:"IMAPS",1433:"MSSQL",1521:"Oracle",2049:"NFS",3306:"MySQL",3389:"RDP",
      5432:"PostgreSQL",5900:"VNC",5985:"WinRM-HTTP",5986:"WinRM-HTTPS",
      6379:"Redis",7000:"?http",8000:"HTTP-alt",8080:"HTTP-alt",8443:"HTTPS-alt",
      9000:"Portainer",9090:"Prometheus",9200:"Elastic",11211:"Memcached",
      11434:"Ollama",11435:"Ollama-2",18789:"OpenClaw",27017:"MongoDB",50000:"DB2"}

def scan(ip,p,to=0.35):
    try:
        with socket.create_connection((ip,p),timeout=to): return p
    except: return None

def banner(ip,p,to=3,payload=b""):
    try:
        s=socket.create_connection((ip,p),timeout=to)
        if payload:
            s.settimeout(to); s.sendall(payload)
        s.settimeout(to)
        try: d=s.recv(300)
        except: d=b""
        s.close(); return d
    except: return b""

for n,ip in HOSTS.items():
    with concurrent.futures.ThreadPoolExecutor(max_workers=200) as ex:
        opens=list(filter(None, ex.map(lambda p: scan(ip,p), PORTS)))
    print(n, ip, "open=", sorted(opens))
    # evidence grabs for surprising/key ports
    if 22 in opens: print("  ssh:", banner(ip,22)[:50])
    if 23 in opens: print("  telnet IAC:", banner(ip,23, payload=b"\xff\xfb\x01")[:30])
    if 21 in opens: print("  ftp:", banner(ip,21)[:50])
# Redis unauth confirm
print("Node-2:6379 PING ->", banner("192.168.1.21",6379, payload=b"*1\r\n$4\r\nPING\r\n")[:12])
# Ollama version
for n,ip in [("Node-1","192.168.1.218"),("Node-2","192.168.1.21"),("Node-4","192.168.1.215")]:
    try:
        with urllib.request.urlopen(f"http://{ip}:11434/api/version",timeout=5) as r:
            print(n,"ollama:",r.read()[:30])
    except Exception as e: print(n,"ollama err:",e)
```

## Rules
- ~1066 ports × 7 hosts ≈ 7,400 probes in ~13s. Scale `max_workers` to host count.
- CONFIRM surprising ports with a stronger method than connect(): banner `recv`, protocol
  handshake, or telnet IAC negotiation (`s.sendall(b"\xff\xfb\x01")`). A council "handshake
  proved absent" can be a FALSE NEGATIVE — the connect() sweep + IAC is the stronger proof.
  (Live 2026-07-11: leaf denied :23; lead IAC proved it REAL alongside :21 FTP / :2049 NFS.)
- Record evidence VERBATIM (raw bytes), not paraphrased.
- NEVER write to the ledger in this mode. If the user wants persistence, that's a separate
  "investigate fully" pass that calls `scripts/audit_to_sqlite.py`.
- Re-probe hot items each turn (Redis unauth, Ollama health, OpenClaw :18789) — silent recon
  reflects CURRENT state, not memory.
