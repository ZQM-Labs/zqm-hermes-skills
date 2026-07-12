---
name: zqm-lan-node-reachability
description: Verify connectivity to ZQM homelab LAN nodes (Node-1..Node-4). Resolve
  .lan DNS, probe TCP ports with Python socket timeouts, interpret 'dark' nodes, and
  avoid the bash /dev/tcp hang. Use when asked 'can we connect to Node-N yet', 'is
  Node-N up', or any ZQM multi-host reachability check on 192.168.1.0/24.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - windows
    - homelab
    - lan
    - reachability
    - networking
    - nodes
    related_skills:
    - ollama-fleet-lb
    - ollama-recovery
    - windows-local-service-restoration
    - zqm-local-setup
    - zqm-systems-review
---
# ZQM LAN Node Reachability

## Overview
Recurring ZQM question: "can we connect to Node-2 / Node-3 / Node-4 yet?" This skill gives the verified, non-hanging way to answer it from Node-1 (the host Hermes runs on). It also carries the authoritative node topology, which was found **STALE** in `zqm-local-setup` (that file mislabeled Node-2 as "this host" and omitted Node-3/Node-4 entirely). Treat the topology in this skill as canonical until re-verified.

## Canonical Topology (DNS-verified 2026-07-10)
- Node-1: `192.168.1.218` / `ZQM-Node-1.lan` / MAC `08:9d:f4:aa:d2:82` — **THIS host** (where Hermes runs)
- Node-2: `192.168.1.21`  / `ZQM-Node-2.lan`
- Node-3: `192.168.1.46`  / `ZQM-Node-3.lan`  ← NOT .22
- Node-4: `192.168.1.215` / `ZQM-Node-4.lan`  ← NOT .23/.24
- **ZQM-Garden-01: `192.168.1.173` — Synology NAS** (NOT a numbered Node). Hosts the SMB share `\\\\ZQM-Garden-01\\web` (reachable + WRITABLE via native PS `Copy-Item`; ~7 items incl. Node-2/3/4 response.txt). Resolve as `ZQM-Garden-01` (no `.lan` needed). Do not conflate it with the .21/.46/.215 nodes.
- **ZQM-GARDEN-04: `192.168.1.144` — Garden appliance** (NetBIOS-resolved 2026-07-12 via `nbtstat -A`; device class not yet confirmed). Separate from GARDEN-01. Another Garden node on the LAN.

**CRITICAL: do NOT guess node IPs sequentially (.21/.22/.23/.24).** The `.lan` names resolve to a non-contiguous block. Always resolve first: `socket.gethostbyname("ZQM-Node-N.lan")` or `nslookup ZQM-Node-N.lan`. The mapping above is what DNS actually returned.

## ARP-first recon (the "arp the network" / broad-scan case)
For an open-ended "scan the network" or quick fleet liveness hint, start with the
neighbor cache rather than a full probe. Recipe in `references/arp-recon.md`:
`arp -a` → `ipconfig` → per-target `ping -n 1 -w 800` → `nbtstat -A <ip>` to name
unknowns. **Key insight:** a fleet node that is OFF/off-subnet is *absent* from
`arp -a` (not merely `dynamic`+unpingable) — absence is the earlier warning sign.
Note the 172.17.160.0/20 `vEthernet (Default Switch)` interface carries only
multicast/broadcast static rows = no real peers (ignore it). Filter all
224.0.0.x / 239.255.255.250 / 255.255.255.255 rows as noise. Use `nbtstat -A`
to resolve bare IPs to NetBIOS names (e.g. ZQM-GARDEN-04 @ .144).

## Probing Method (DO THIS)
Use the recipe in `references/lan-node-probe.md`. Essentials:
1. Resolve each node name to an IP via DNS — never assume the IP.
2. TCP probe candidate ports with `socket.socket(); s.settimeout(0.6)` then `s.connect((ip, port))`. This slides cleanly past unresponsive hosts (no hang).
3. Cross-check with ICMP `ping -n 2 -w 1000 <ip>` to separate "alive but firewalled" from "not on the wire".
4. Interpret: open ports = service up; no ports + no ICMP = off / disconnected / fully firewalled.

## Endpoint review: CLOSED remote port ≠ "localhost-bound confirmed"
When an endpoint review asks "confirm service X is localhost-bound (not LAN-exposed)"
and your **remote** TCP probe finds the port closed/filtered: that proves only
**"not reachable from this vantage,"** NOT "bound to 127.0.0.1." A closed remote
result is equally consistent with (a) loopback-only binding, (b) a firewall
allow-rule scoped to a different subnet / a block rule, or (c) the service down.
Report it as **"CLOSED on LAN (not LAN-exposed from Node-1)"**. If the task literally
says "confirm localhost-bound," positive confirmation requires an ON-HOST check:
`netstat -ano | findstr 11434` showing `127.0.0.1:11434` vs `0.0.0.0:11434`, or
`Get-NetTCPConnection -LocalPort 11434 | Select LocalAddress`.
[2026-07-11 N3/192.168.1.46: :11434 closed on LAN — correctly means not-LAN-exposed,
but "localhost-bound CONFIRMED" overreached what a remote probe can establish;
firewall RemoteIP scoping produces the identical closed result.]

## Per-port risk grading (endpoint-review deliverable)
When the ask is "assign per-port risk + node grade," use this rubric for consistency:
- **HIGH**: LAN-exposed Windows legacy/mgmt with pre-auth or plaintext exposure —
  SMB (445), NetBIOS (139), MS-RPC (135), WinRM-HTTP (5985, no TLS).
- **MED**: credential-gated or discovery mgmt — SSH (22), WinRM-HTTPS (5986),
  RDP (3389), Hyper-V VM-RDP (2179), WSDAPI (5357).
- **LOW**: local infra with low reach — WinNAT (5040), loopback-bound AI services
  (Ollama/LiteLLM/agent ports when confirmed 127.0.0.1).
- **Node grade** = worst-case posture: any HIGH LAN-exposed mgmt port with no source
  scoping ⇒ node grade HIGH until patch level + firewall RemoteIP scoping verified.
  A correctly loopback-bound AI stack does NOT lower a grade already HIGH from
  SMB/RPC/WinRM. The re-runnable Python-socket probe (0.4s timeout, port→service
  table) worked cleanly — see `references/lan-node-probe.md`.

## Remediation (bring a dark node up / open remote mgmt)
See `references/lan-node-remediation.md` — firewall-open commands (Private profile +
scoped inbound rule for the indexer port) and PowerShell Remoting (Enable-PSRemoting on
the target + TrustedHosts on Node-1). The agent's PowerShell is non-elevated, so
admin steps must be delivered as copy-paste blocks for the user to run on the target host.

## Pitfalls
- **NEVER use bash `/dev/tcp/ip/port` for reachability scanning.** It has NO timeout and HANGS indefinitely on an unresponsive host (observed: a 180s stall on 192.168.1.22 before being killed). Always use Python `socket` + `settimeout()`.
- Don't conclude "can't connect" from ICMP alone — ICMP may be firewalled while services still listen. Probe ports too.
- Don't conclude "up" from DNS resolution alone — the `.lan` A records persist even when the host is powered off (observed: all four names resolved, but only Node-1 actually answered).
- PSRemoting: `Set-Item WSMan:\\localhost\\Client\\TrustedHosts` on Node-1 needs the LOCAL WinRM service running first — `winrm quickconfig -q`. If it errors "client cannot connect to the destination", that's Node-1's own WinRM, not the remote node. See `references/lan-node-remediation.md`.
- **ARP absence ≠ firewalled:** an off/off-subnet host drops out of `arp -a` entirely; a firewalled-but-on host usually retains a (stale) dynamic entry. So a fleet node missing from the cache + failing ICMP = OFF, not just firewalled. Lead with `arp -a` for the earliest signal (see `references/arp-recon.md`).
- **Ignore ARP noise rows:** 224.0.0.x, 239.255.255.250, 255.255.255.255, and any `ff:ff:ff:ff:ff:ff` / `01-00-5e-*` static entries are multicast/broadcast — not hosts. Also disregard the `vEthernet (Default Switch)` (172.17.160.0/20) interface; it shows only broadcast/multicast, no real peers.

## Baseline (2026-07-10, probed from Node-1 — REFRESHED SAME DAY)
- **Early probe (port-only + ICMP):** only Node-1 answered (open ports 139,445,5000); Nodes 2-4 DNS-resolvable but NO ICMP + NO open ports on 22/80/139/445/5000/8000/8080/9000 → logged as **dark**.
- **Later full /24 ping sweep (same day):** ALL FOUR nodes answered ICMP — `.21`, `.46`, `.215` (fleet) + `.218` (this box) ALIVE, plus gateway `.1` and NAS `.173`. 43 hosts total alive on 192.168.1.0/24. → **Reconciliation: the fleet nodes were merely firewalled on probed TCP ports but were ON and ICMP-reachable.** Treat "dark" as STALE; re-sweep before reporting.
**Lesson:** a single port+ICMP pass can mislabel live hosts as dark. For "are the nodes up" questions, prefer a full /24 `ping.exe -n 1 -w 500` sweep (see `references/lan-node-probe.md` §sweep) — it is authoritative for liveness. `Test-Connection -AsJob` is UNRELIABLE in this env (returned 0 alive); use `ping.exe`.

## Baseline (2026-07-12, ARP-first recon from Node-1)
- `arp -a` on 192.168.1.0/24: Node-1 (.218), GW (.1), N3 (.46), N4 (.215) present; **Node-2 (.21 ABSENT from cache**. 5 unknown unicast hosts present: .82, .91, .144, .170, .172, .220. `vEthernet (Default Switch)` 172.17.160.0/20 showed only multicast/broadcast static rows (no peers).
- ICMP confirm: UP = .1/.46/.215/.82/.91/.144/.170/.172/.220; **DOWN = .21 (Node-2)** — absent from ARP + no ICMP = OFF, not merely firewalled.
- `nbtstat -A .144` → `ZQM-GARDEN-04 <00> UNIQUE Registered` (a Garden appliance, class TBD; added to topology above). The other unknowns (.82/.91/.170/.172/.220) did not resolve NBT (likely non-Windows / NetBIOS-off).
- **Unknown-host fingerprint chain applied** (recipe in `references/arp-recon.md` §Identify unresolved unknowns): OUI lookup via macvendors.com (RATE-LIMITED → space calls with `sleep 3`/`sleep 4`); port scan via `powershell.exe Test-NetConnection -Port` (NOT bash /dev/tcp — hangs); HTTP banner via `curl -I` / `curl -sk -I`. Verified results: `.82` & `.172` = Google Inc. (8443 only → Nest/Chromecast/Wifi); `.91` = HP Inc. (80+443, nginx 301 → printer); `.170` = ASUSTek (22+80+443+8443, `httpd/3.0` → ASUS router/appliance); `.220` = Intel NIC (22+80+8443, `httpd/3.0` → server/PC). Vendor + banner = INFERENCE only, never authenticate.
- **Reconciliation vs 2026-07-10 baseline:** Node-2 was alive on 2026-07-10 (.21 answered ICMP in the full sweep); by 2026-07-12 it was down. Fleet liveness is NOT static — re-recon before reporting, and treat "Node-N up" as a point-in-time fact.

## Notes
- `zqm-local-setup` SKILL.md is stale on topology (wrong "this host"; missing Node-3/4; implies a tidy .21-.24 block). This skill is the maintained source of truth for reachability. Flag the overlap to the curator for consolidation.
- For Windows-hosted service health on a node that IS reachable, see `windows-local-service-restoration` and `local-service-verification`.
