---
name: windows-lan-investigator
description: "Use when investigating a Windows LAN host on a workgroup/home network. Covers evidence-gathering from identity/ports/services/SMB/firewall on Windows 10+ with real LAN triage patterns from Node-1/Node-2 diagnosis."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [windows, lan, networking, smb, netbios, portscan, wmi, firewall, evidence]
    related_skills: [networking-tools, localhost-management, python-windows-project-setup]
---

# Windows LAN Investigator

## Overview

This skill codifies the evidence-gathering pattern that actually worked across two Windows 10 WORKGROUP nodes on `192.168.1.0/24`. The goal is not broad recon — it is producing evidence that distinguishes "closed," "reachable but auth-required," "service present," and "firewall filtering."

Do not stop at port lists. Run the chain below unless the user explicitly asks for less.

## When to Use

- User asks to investigate, enumerate, or diagnose a Windows LAN host
- User says "investigate properly" or "what is running on node-X"
- Mapping broadcast sources to actual PIDs/services on Node-2
- Verifying whether a Node-1-style host is reachable and what it exposes
- Auditing firewall/port exposure from a Windows endpoint itself

Do not use for:
- Linux/UNIX LAN hosts without modification
- WAN/internet reconnaissance
- Domain-joined hosts with AD tools available
- Passive monitoring without an active target

## Prerequisites

- Windows 10+ host as vantage point (Node-2 in our topology)
- Python 3.10+ stdlib available for targeted probes
- Optional: `nmap` for initial port survey
- Admin rights are helpful but not required for most read-only steps

---

## Phase 1: Identity Matrix

Run these first. They are fast and tell you whether the target actually exists on the LAN from this vantage point.

### 1.1 ARP + MAC

```bash
# From Node-2:
arp -a 192.168.1.218
```

Record the MAC. If there is no ARP entry, ICMP may be filtered, but the host might still answer TCP.

### 1.2 mDNS / hostname confirmation

```python
import socket
socket.getaddrinfo("ZQM-Node-1.local", None)
```

If this resolves, mDNS is functional. If it raises, don't treat that as "host down" — it only means mDNS is not reachable from this vantage point.

### 1.3 NetBIOS name table

```bash
nbtstat -a 192.168.1.218
```

Look for `WORKGROUP<00>` and the host's `<20>` unique name. An empty/refused result is meaningful: it means the host is not accepting NetBIOS queries from this source.

---

## Phase 2: TCP Port Survey

Do not scan all 65k ports. Target known service ports plus local discovery ports.

### 2.1 Port list for Windows workgroup hosts

```
21,22,23,25,53,80,110,123,135,139,143,389,443,445,465,587,593,631,636,993,995,
1433,1521,2049,2375,3000,3306,3389,5432,5900,5901,6379,7001,8000,8008,8080,
8443,8888,9000,9001,9092,9093,9200,9300,11211,27017,50000,2177,5050,51225,
1900,3702
```

### 2.2 Scanning rules on Windows

- TCP SYN/connect scan only. On Windows 10, half-open SYN may fail without Npcap/Admin; connect scan is the reliable default.
- Keep scans targeted: `-p` with a narrow range, or `--top` with a short list.
- Fake timeouts under 1s still spend ~1s due to Windows TCP timeout behavior. Factor this into total runtime.

### 2.3 Banner grab

Send protocol-aware probes, not just connect-check:

- SMB2 negotiate on 445
- HTTP request on web-ish ports (80, 443, 8000, 8080, 8443)
- `\r\n` on line-oriented daemons

### 2.4 SMB behavior triage

```bash
# TCP reachability:
Test-NetConnection 192.168.1.218 -Port 445

# SMB share enumeration:
net view \\192.168.1.218
```

Interpretation:
- `net view` returns `Access is denied` on an open 445 = **auth-required**. Do not report it as closed.
- `net view` times out with open 445 = firewall is filtering SMB specifically at an upper layer.

---

## Phase 3: UDP Reachability

UDP is often misleading on Windows. Run this deliberately.

### 3.1 Send 0x00 to closed UDP ports

Send an empty datagram to a known-closed UDP port and classify:
- **ICMP unreachable** = host is reachable, port is closed
- **Timeout** = firewall is dropping inbound ICMP or UDP entirely, or host is not answering

### 3.2 Interpretation

If every UDP test times out, treat that as evidence: "Host firewall is likely blocking inbound ICMP/UDP from this vantage point." Do not retry indefinitely.

---

## Phase 4: Unicast Discovery Probes

Do not rely on broadcast captures alone.

### 4.1 UPnP / WS-Discovery

```
M-SEARCH to UDP 1900
WS-Discovery SOAP to UDP 3702
```

### 4.2 mDNS query

Query UDP 5353 directly from Node-2. If it times out, the discovery stack is not responding to unicast from this vantage point.

### 4.3 Interpretation

Timeout = not necessarily "no service"; it means "no unicast response to this probe." Record that distinction.

---

## Phase 5: Firewall State on the Target Host

The goal is to understand what the host itself allows, not just what is visible externally.

### 5.1 From the target host itself

```powershell
# Preferred on Windows 10 / git-bash:
netsh advfirewall firewall show rule name=all

# Alternative from PowerShell, if netsh is insufficient:
Get-NetFirewallProfile | Format-List
```

### 5.2 From Node-2 vantage point

```bash
# Port state:
netstat -ano | grep ':PORT '

# Owner mapping:
tasklist /svc /FI "PID eq <PID>"
```

### Known Windows service mappings

| Port | Service | Notes |
|------|---------|-------|
| 2177 | QWAVE | QoS / stream quality |
| 3702 | fdPHost / FDResPub | Function Discovery / WS-Discovery |
| 1900 | SSDPSRV | UPnP / SSDP |
| 5353 | Dnscache + Chrome | mDNS / Bonjour |
| 5355 | Dnscache | LLMNR |
| 5050 | CDPSvc | Connected Devices Platform |
| 51225 | SSDPSrv | Ethernet discovery |

---

## Phase 6: Remote Introspection Limits

### 6.1 WMI / remote registry

Against a non-domain Windows 10 host, WMI and remote registry almost always return `Access is denied` unless explicit credentials are provided.

- Enumerate remotely only what the network stack exposes.
- Do not retry `Get-Service` / `Get-WmiObject` as if credentials were implied.
- If remote WMI fails, record "Access is denied" as evidence, not as an error to brute-force.

### 6.2 When credentialed access is available

If you have explicit admin credentials for the remote host:
- Use them explicitly on each command.
- Record the account used in your findings matrix.
- Do not store the credential in repo files.

---

## Phase 7: Evidence Output Format

Produce a structured evidence file. Use this schema:

```json
{
  "target": "192.168.1.218",
  "hostname": "ZQM-Node-1.lan",
  "mac": "08:9d:f4:aa:d2:82",
  "arp_entry": "present",
  "mdns_resolution": "failed",
  "netbios_name_table": "refused",
  "tcp_open": [135, 139, 445],
  "tcp_closed": [21,22,23,...],
  "udp_timeout_all": true,
  "smb_share_access": "Access is denied",
  "firewall_rules_local": "empty or not available",
  "remote_wmi": "Access is denied",
  "notes": ["Service X is auth-required, not closed"]
}
```

Save as `investigation-<hostname>.json` in `logs/` or the project's evidence directory.

---

## Common Pitfalls

1. **Reporting auth-required services as closed.** `Access is denied` on an open SMB port means reachable, not closed.
2. **Relying on broadcast captures for unicast evidence.** Always pair with directed probes.
3. **Expecting UDP to behave like TCP.** UDP timeouts on Windows are ambiguous; classify explicitly.
4. **Retrying WMI without credentials.** It will not silently succeed.
5. **Confusing mDNS timeout with host down.** mDNS being filtered is normal inside some firewall/network configurations.
6. **Confusing firewall-empty output with firewall-off.** `Get-NetFirewallProfile` returning nothing is a known Windows 10 behavior under some shells; prefer `netsh advfirewall`.
7. **Scanning `C:\Windows` and `C:\PerfLogs` for local content.** These inflate skip counts with near-zero coverage value. Put them in `SKIP_ROOTS` instead.

---

## Verification Checklist

- [ ] ARP entry captured or explicitly recorded as absent
- [ ] Hostname/MAC identity recorded
- [ ] TCP port list distinguished open vs auth-required vs filtered
- [ ] UDP behavior classified: closed vs timeout
- [ ] SMB behavior classified: reachable/auth-required/filtered
- [ ] Unicast discovery probes run and classified
- [ ] Owner mapping done for any suspicious local ports on Node-2
- [ ] Evidence output written in JSON form
- [ ] No committed credentials in findings files
