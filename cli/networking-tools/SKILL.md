---
name: networking-tools
description: "Use when the user asks for ping, ping sweep, port scan, traceroute, DNS lookup, HTTP/TCP probes, capture summaries, or a zero-dependency Windows-friendly Python networking CLI. Stdlib-only template with Windows-specific pitfalls and LAN investigation patterns."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [networking, cli, scanner, dns, ping, portscan, traceroute, windows]
---

# Networking Tools

Use this skill to build a single-file CLI networking kit (`netsuite.py`) and to remember Windows-specific behaviors we rely on.

## Triggers

- User asks for ping, ping sweep, port scanner, traceroute, DNS lookup, HTTP/TCP check, local network info, or "all of the above" networking tools.
- Need a zero-dependency networking CLI template (stdlib only, Python 3.10+).
- LAN device diagnosis on Windows: mapping `192.168.x.x` hosts, resolving broadcast sources, inspecting services behind discovery ports.

## Workflow

1. Scaffold one Python script with: `info`, `ping`, `sweep`, `portscan`, `trace`, `dns`, `rdns`, `http`, `tcp`, `cap`.
2. Make all output scriptable - XML/JSON optional, default human readable.
3. Install alongside user home (`~/netsuite.py`) and keep a project copy under `~/net-tools/`.
4. Prefer stdlib (`socket`, `subprocess`, `urllib`) so it runs without `pip install`.

## Windows Pitfalls

- `tracert`/`traceroute`: when spawned from Python, `tracert.exe` may only emit output when stdout is attached to an interactive console. If parsing yields `*` for every hop, run the traceroute as an interactive call instead of per-hop subprocess invocations. Each TTL-specific invocation is unreliable on this host.
- `ping -n N -w MS` is Windows syntax; Linux/macOS uses `-c` and `-W`.
- Port scanning is slow on Windows due to TCP timeout behavior. Fake timeouts under 1s still spend ~1s. Keep scans targeted with `-p` or `--top`.
- Raw packet capture requires Npcap + Administrator; without it, show `netstat -ano` instead.
- `Get-NetFirewallRule` can return empty or fail in git-bash/PS on Windows 10. Prefer `netsh advfirewall`, `netstat`, or `Get-NetTCPConnection` for port-state evidence.
- `tasklist /FO TSV` is invalid on this host; use `/FO CSV` or `/FO LIST`.
- `nbtstat`, `arp`, and `net view` are the LAN evidence tools actually available here.

## Windows LAN Investigation Workflow

When asked to "investigate properly" a Windows LAN host, do not stop at broadcast-port lists. Run this chain from Node-2 against Node-1:

1. Identity matrix
   - `arp -a <target>` for MAC
   - `socket.getaddrinfo("<hostname>.local")` from Node-2 to confirm mDNS registration
   - `nbtstat -a <target>` for NetBIOS name table

2. TCP port survey with banner grab
   - Scan well-known service ports plus local discovery ports: 21,22,23,25,53,80,110,123,135,139,143,389,443,445,465,587,593,631,636,993,995,1433,1521,2049,2375,3000,3306,3389,5432,5900,5901,6379,7001,8000,8008,8080,8443,8888,9000,9001,9092,9093,9200,9300,11211,27017,50000,2177,5050,51225,1900,3702
   - Send protocol-aware probes: SMB2 negotiate on 445, HTTP request on web-ish ports, `\r\n` on line-oriented daemons.

3. UDP reachability paths
   - Send `0x00` to closed UDP ports and classify timeout vs ICMP unreachable. If every UDP test times out, the host's firewall is likely blocking inbound ICMP or inbound UDP entirely. Treat that as evidence, not as a failed command.

4. mDNS / UPnP / WS-Discovery unicast probe
   - Do not rely on broadcast captures alone. Send unicast `M-SEARCH` to 1900, WS-Discovery SOAP to 3702, and mDNS query to 5353. If they time out, the discovery stack is not responding to unicast from this vantage point.

5. SMB behavior triage
   - `Test-NetConnection dst -Port 445` verifies TCP reachability.
   - `net view \\dst` returning `Access is denied` on an open SMB port means **auth-required**, not closed. Do not report it as closed.

6. Local broadcast-source owner mapping
   - Pair every suspicious local port with its owner:
     - `netstat -ano | findstr /R /C:":<port> "`
     - `tasklist /svc /FI "PID eq <pid>"`
   - Known Windows service mapping:
     | Port | Service | Notes |
     |------|---------|-------|
     | 2177 | QWAVE | Windows QoS / stream quality |
     | 3702 | fdPHost / FDResPub | Function Discovery / WS-Discovery |
     | 1900 | SSDPSRV | UPnP/SSDP |
     | 5353 | Dnscache + Chrome | mDNS/Bonjour |
     | 5355 | Dnscache | LLMNR |
     | 5050 | CDPSvc | Connected Devices Platform |
     | 51225 | SSDPSrv | Ethernet discovery |

7. Remote introspection limits
   - WMI and remote registry queries against a non-domain Windows 10 host almost always fail with `Access is denied` unless explicit credentials/admins are used. Enumerate remotely only what the network stack exposes; do not retry `Get-Service`/`Get-WmiObject` as if credentials were implied.

## Verification

```bash
python netsuite.py info
python netsuite.py ping 192.168.1.1
python netsuite.py dns google.com
python netsuite.py http example.com
python netsuite.py tcp 192.168.1.1 80
```

## References

- `references/windows-lan-investigation.md`: Windows LAN diagnosis playbook with evidence from Node-1/Node-2 investigation.
- `scripts/netsuite.py`: generated main.py copy.
