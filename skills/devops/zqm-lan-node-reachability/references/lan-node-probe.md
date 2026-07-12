# LAN Node Probe Recipe (ZQM 192.168.1.0/24)

Verified, non-hanging reachability probe. Run from Node-1 (192.168.1.218).

## 1. Resolve .lan names (NEVER guess IPs)
```python
import socket
names = {f"ZQM-Node-{n}.lan" for n in range(1,5)}
for n in names:
    try: print(n, "->", socket.gethostbyname(n))
    except Exception as e: print(n, "-> FAIL", e)
```
Observed 2026-07-10:
  ZQM-Node-1.lan -> 192.168.1.218
  ZQM-Node-2.lan -> 192.168.1.21
  ZQM-Node-3.lan -> 192.168.1.46
  ZQM-Node-4.lan -> 192.168.1.215
Note the non-contiguous mapping (.46, .215) — sequential guessing is wrong.
Also resolve the NAS: `socket.gethostbyname("ZQM-Garden-01")` -> 192.168.1.173
(Synology; serves writable SMB `\\ZQM-Garden-01\web`).

## 2. TCP port probe with timeout (DO NOT use bash /dev/tcp — it hangs)
```python
import socket
hosts = {  # fill from DNS step above
    "Node-1": "192.168.1.218",
    "Node-2": "192.168.1.21",
    "Node-3": "192.168.1.46",
    "Node-4": "192.168.1.215",
}
ports = [22, 80, 139, 445, 5000, 8000, 8080, 9000]
def open(ip, p, t=0.6):
    s = socket.socket(); s.settimeout(t)
    try: s.connect((ip, p)); s.close(); return True
    except Exception: return False
for name, ip in hosts.items():
    opens = [p for p in ports if open(ip, p)]
    print(f"{name} {ip}: open={opens or 'none'}")
```

## 3. ICMP cross-check (alive-but-firewalled vs not-on-wire)
```bash
for ip in 192.168.1.218 192.168.1.21 192.168.1.46 192.168.1.215; do
  ping -n 2 -w 1000 "$ip" >/dev/null 2>&1 && echo "REACHABLE(icmp) $ip" || echo "NO-ICMP $ip"
done
```

## 3b. FULL /24 LIVE-HOST SWEEP (authoritative liveness) — PREFERRED for "are the nodes up"
`Test-Connection -AsJob` is UNRELIABLE in this env (returned 0 alive despite known
live hosts). Use a `ping.exe` sequential loop via PowerShell `-File` (run from git-bash):
```powershell
# sweep24.ps1
$alive = @()
for ($x=1; $x -le 254; $x++) {
  $ip = "192.168.1.$x"
  if (ping.exe -n 1 -w 500 $ip 2>&1 | Select-String 'Reply from') { $alive += $ip }
}
"ALIVE: $($alive.Count) -> $($alive -join ', ')"
```
~2 min for 254 hosts at -w 500. Real alive count. (RTT capture via regex is flaky —
often yields "ms" with no number; treat liveness as authoritative, RTT best-effort.)
Cross-reference known nodes: .1 gateway, .21/.46/.215 fleet, .218 this box, .173 NAS.

## 4. Interpret
- open ports present  -> service up on that port
- no ports + ICMP ok   -> host alive, inbound firewalled
- no ports + NO ICMP   -> off / disconnected / fully firewalled (treat as DARK)

## Baseline snapshot — CORRECTED SAME DAY (2026-07-10)
Early port+ICMP pass mislabeled Nodes 2-4 as DARK (no open ports, no ICMP seen).
A later full /24 ping sweep found ALL FOUR nodes ICMP-ALIVE (.21/.46/.215/.218)
+ gateway .1 + NAS .173, 43 hosts total on the /24. The nodes were merely
firewalled on probed TCP ports but were ON and reachable. Always re-sweep before
calling a node "dark".
  Node-1 192.168.1.218  : ICMP alive, open=[139,445,5000]   (this host)
  Node-2 192.168.1.21   : ICMP alive  (early pass: dark — WRONG)
  Node-3 192.168.1.46   : ICMP alive  (early pass: dark — WRONG)
  Node-4 192.168.1.215  : ICMP alive  (early pass: dark — WRONG)
  ZQM-Garden-01 .173    : ICMP alive, Synology NAS, SMB \\web writable
