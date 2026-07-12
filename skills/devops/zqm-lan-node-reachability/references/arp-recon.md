# ARP-first LAN reconnaissance (Windows workgroup)

Fast first-pass when asked to "scan / arp the network" or to sanity-check fleet
liveness before a deeper probe. Goal: see WHO the host has actually talked to on
the wire, name the unknowns, and separate real hosts from ARP noise.

## Command sequence (run from Node-1 bash/MSYS)
```
arp -a                       # neighbor cache, per-interface
ipconfig                     # local IP(s) + subnet + default GW
for ip in <targets>; do ping -n 1 -w 800 "$ip" >/dev/null 2>&1 && echo "$ip UP" || echo "$ip DOWN"; done
nbtstat -A <ip>              # NetBIOS name table (resolves Windows/workgroup hosts)
```

## Why ARP first
`arp -a` shows only hosts the stack has spoken to recently. A fleet node that is
OFF or off-subnet will be **entirely ABSENT** from the cache — that absence is a
stronger signal than a single failed ping. (Observed 2026-07-12: Node-2 .21 was
missing from ARP AND failed ICMP, while N1/N3/N4 were present.)

## Classification of `arp -a` output
- **Real unicast hosts** = dynamic entries with a 1:1 IP<->MAC (e.g. 192.168.1.x).
- **Multicast / static noise** = 224.0.0.x, 239.255.255.250, 255.255.255.255,
  and broadcast rows (172.17.175.255 on the Hyper-V vSwitch). IGNORE these — they
  are not hosts.
- **Per-interface separation**: a 172.17.160.0/20 `vEthernet (Default Switch)`
  interface typically has only broadcast/multicast static rows = no real peers.

## Resolving unknowns
`nbtstat -A <ip>` returns the NetBIOS name table when the device is a Windows or
workgroup member with NetBIOS enabled. It can resolve a bare IP into a hostname
(e.g. `ZQM-GARDEN-04 <00> UNIQUE Registered` at .144). If NBT returns nothing,
the host is likely non-Windows or NetBIOS-disabled — fall back to the
fingerprint chain below.

## Identify unresolved unknowns (OUI + port scan + banner) — VERIFIED 2026-07-12
When `nbtstat -A` returns nothing for a live IP, fingerprint it so it can be
named in the report. This is the working chain; all three steps ran clean.

### 1. OUI vendor lookup (MAC → vendor)
```bash
curl -s --max-time 8 "https://api.macvendors.com/f8-0f-f9-56-9b-03"
```
- Results map strongly to device class: `Google Inc.` → Nest/Chromecast/Wifi;
  `HP Inc.` → printer; `ASUSTek` → router/appliance; `Intel` NIC → PC/server.
- **RATE LIMITED**: macvendors.com returns HTTP 429 ("Please slow down") after a
  few rapid calls. SPACE requests with `sleep 3`/`sleep 4` between them, or loop
  with backoff. Don't fire 5 lookups in a tight loop.

### 2. Port scan (PowerShell Test-NetConnection — always present on Windows)
Bash `/dev/tcp` HANGS (no timeout) — never use it. `Test-NetConnection` is the
reliable path, driven from MSYS via `powershell.exe`:
```bash
ports="22 53 80 443 445 3389 8080 8443 8000 5900"
for ip in 192.168.1.82 192.168.1.91 192.168.1.170 192.168.1.172 192.168.1.220; do
  open=""
  for p in $ports; do
    if powershell.exe -NoProfile -Command "Test-NetConnection -ComputerName $ip -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue" 2>/dev/null | grep -qi true; then
      open="$open $p"
    fi
  done
  echo "$ip -> open:${open:- none}"
done
```
- `Test-Connection -AsJob` is UNRELIABLE in this env (returned 0 alive) — use
  `ping.exe -n 1 -w 500` for liveness, `Test-NetConnection -Port` for ports.
- Open-port patterns that fingerprint device class: `22+80+8443` or
  `80+443+8443` → appliance/server; `80+443` only (+ nginx 301) → printer/webcam.

### 3. HTTP banner grab (confirm server type)
```bash
curl -s --max-time 5 -I "http://$ip"        | grep -iE "Server:|HTTP/|Location:"
curl -sk --max-time 5 -I "https://$ip:8443" | grep -iE "Server:|HTTP/|Location:"
```
- `Server: httpd/3.0` ⇒ ASUSWRT / embedded appliance; `nginx` + 301 ⇒ printer/
  off-the-shelf web UI. Banner is INFERENCE, not auth — do NOT authenticate.

### 2026-07-12 fingerprint results (verified, reusable as a known-host table)
| IP | MAC OUI | Vendor | Open ports | Inferred |
|----|---------|--------|-----------|----------|
| .82  | f8:0f:f9 | Google Inc.   | 8443 | Google device (Nest/Cast/Wifi) |
| .91  | 7c:4d:8f | HP Inc.       | 80(301→https),443 | HP printer |
| .170 | 10:7c:61 | ASUSTek       | 22,80(httpd/3.0),443,8443 | ASUS router/appliance |
| .172 | 20:1f:3b | Google Inc.   | 8443 | Google device (2nd) |
| .220 | a0:36:bc | Intel NIC     | 22,80(httpd/3.0),8443 | server/PC |
(ZQM-GARDEN-04 .144 resolved via nbtstat — Garden appliance, class TBD.)

## Anomaly pattern (the Node-2 case)
A fleet member that is (a) absent from `arp -a` AND (b) fails ICMP is OFF or
unreachable — do not assume it's merely firewalled (a firewalled-but-on host
usually still shows a stale ARP entry). Report it as DOWN and offer WoL / manual
check rather than a port probe.

## Caveats
- ARP cache is stale-prone: an entry can linger after a host goes offline, and a
  host that's up but un-talked-to won't appear. Treat ARP as a *first-pass hint*,
  not proof of liveness. Confirm with the ping sweep in `lan-node-probe.md`.
- `nbtstat` is Windows-only and slow/timeout-prone per host; loop it but don't
  block on a single non-responding target.
