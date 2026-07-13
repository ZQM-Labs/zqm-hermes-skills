---
name: zqm-federation-mesh
description: Operation + capability map of the ZQM federation mesh — the 2-node (Node-1 + Node-3) cluster that provides unified cross-node file search (/api/federate) and local *.zqm DNS resolution via CoreDNS on Node-4. Use when the user asks what the mesh does, how to verify it, how to add a peer, or how to read the fleet watchdog.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - federation
    - mesh
    - indexer
    - coredns
    - homelab
    - watchdog
    related_skills:
    - zqm-fleet-management
    - zqm-local-setup
    - ollama-fleet-lb
---

# ZQM Federation Mesh

The ZQM federation mesh is the working glue between fleet nodes for (1) unified
content search and (2) name resolution. It is a SEED mesh: plumbing is in place
to scale to more nodes; only Node-1 + Node-3 are currently joined.

## What the mesh IS (verified live 2026-07-12)

Two joined members:
  • Node-1 (192.168.1.218) — aggregator. Runs zqm-indexer on :5000, plus the
    local AI stack (Ollama :11434, SearXNG :8080, AnythingLLM :3001).
  • Node-3 (192.168.1.46) — peer. Thin Whoosh indexer (node_indexer.py) on :5000,
    embedded Python at C:\py312, AtStartup scheduled task for persistence.

CoreDNS server: Node-4 (192.168.1.215) — serves :53 + :853 (DoT). It is the
*.zqm authority but is itself AUTH-GATED from Node-1 (SSH✗/WinRM✗).

## FUNCTIONALITY THAT EXISTS (proven)

1) UNIFIED CONTENT SEARCH (federation indexer)
   • GET http://127.0.0.1:5000/api/federate?q=<term>&limit=N on Node-1 searches
     Node-1's local Whoosh index AND every discovered peer's /api/search, merges
     results, tags each hit with `_node` (source IP).
   • Verified: total=merged(local+peer), fleet_nodes=N alive peers.
   • Lets you full-text search files across both boxes from one call.

2) AUTOMATIC PEER DISCOVERY
   • Node-1 probes known peer IPs (federation_nodes.json registry) and learns
     which are alive; /api/health reports fleet_nodes with status per peer.
   • Scales by adding IPs to the registry.

3) LOCAL .zqm NAME RESOLUTION (CoreDNS)
   • On Node-1 + Node-3, DNS is pointed at 192.168.1.215 (CoreDNS) primary,
     router .1 fallback. Forcing via Set-DnsClientServerAddress + DISABLING the
     Wi-Fi IPv6 binding (DHCPv6 keeps re-injecting Spectrum DNS that sorts first
     and returns NXDOMAIN for *.zqm).
   • Verified: gateway.zqm / node-1.zqm / node-3.zqm resolve to 192.168.1.215.

4) FLEET HEALTH WATCHDOG (fleet_watchdog.py)
   • Self-looping (every 15 min) process on Node-1. Checks: local /api/health,
     each peer /api/health, /api/federate merge, and CoreDNS resolution.
   • Writes fleet_watchdog.log (rolling) + prints HEALTHY/DEGRADED.
     Exit code 1 on any peer down or DNS broken (alertable).
   • Launched via Startup folder (start_watchdog.vbs) — non-admin, survives
     reboot. NOT a Task Scheduler task (UAC-gated in automation context).

## FUNCTIONALITY THAT DOES NOT EXIST (gaps — not code, but creds/perms)

  • Node-4 Ollama (:11434, 45 models) NOT federated into the indexer.
  • No shared auth / SSO across nodes.
  • No config/agent push to nodes you can't SSH/WinRM (Node-4, RPi blocked).
  • xyo-bridge (.164 RPi) — SSH :22 OPEN but NO credential known; not a peer.
  • Node-2 (.21) — dead, no services; not a peer.
  • Gardens (13 Synology/TerraMaster) — still on router DNS (write blocked by
    user; DSM also regenerates resolv.conf, so low value).
  • Node-4's OWN client DNS can't be set (auth-gated) — but it's the server, so
    it doesn't need it to serve others.

## VERIFY THE MESH (ad-hoc, read-only)

  PY="C:/Users/zqmco/AppData/Local/Programs/Python/Python312/python.exe"
  # federation
  $PY -c "import urllib.request,json; d=json.loads(urllib.request.urlopen('http://127.0.0.1:5000/api/federate?q=zqm&limit=3').read()); print('total',d['total'],'fleet_nodes',d['fleet_nodes'])"
  # peer health
  $PY -c "import urllib.request; print(urllib.request.urlopen('http://192.168.1.46:5000/api/health').read().decode()[:200])"
  # CoreDNS
  nslookup gateway.zqm 192.168.1.215     # expect 192.168.1.215
  # watchdog once-shot
  $PY fleet_watchdog.py

## ADD A PEER (Windows node, e.g. another NUC)

  See references/peer-onboarding.md (embedded Python + AtStartup task + IPv6
  unbind pattern). Core steps proven on Node-3:
    1. Embedded Python at C:\py312 (patch python312._pth for site).
    2. pip install flask whoosh waitress.
    3. Drop node_indexer.py + indexer_lib.py; set ZQM_INDEX_ROOT or put docs in
       C:\Users\<user>\ZQM (DEFAULT_ROOTS = env C:\ZQM or ~\ZQM).
    4. Firewall :5000 (Private profile, ActiveStore).
    5. Launch via AtStartup scheduled task (Win32_Process.Create / WMI detaches
       from SSH session; pythonw alone does NOT survive SSH disconnect).
    6. On Node-1: add peer IP to federation_nodes.json, re-discover.
    7. Set CoreDNS on the new node: Set-DnsClientServerAddress primary .215 +
       DISABLE Wi-Fi IPv6 binding (critical — see CoreDNS pitfall below).

## COREDNS PITFALL (cost 4 attempts to learn)

  Setting DNS to 192.168.1.215 is NOT enough. The Spectrum router pushes an
  IPv6 DNS (2603:…spectrum.com) via DHCPv6 that SORTS AHEAD of the IPv4
  CoreDNS entry, so Windows queries Spectrum first → NXDOMAIN for *.zqm.
  Forcing `Resolve-DnsName -Server 192.168.1.215` works; the default path
  fails until IPv6 is unbound from the Wi-Fi adapter:
    Disable-NetAdapterBinding -Name "Wi-Fi" -ComponentID ms_tcpip6
  Then re-assert IPv4 DNS. Without this step, *.zqm silently doesn't resolve.

## CREDENTIALS (DPAPI, never in chat)

  C:\zqm\cred\zqm-cred-node-local.json  (zqmlocal — Node-3 SSH/WinRM)
  C:\zqm\cred\zqm-cred-garden-admin.json (azelenski — Gardens SSH)
  Node-4 cred NOT held (auth gate). xyo-bridge cred NOT held.
  Use scripts/zqm-dpapi-ssh.ps1 (in zqm-local-setup) to SSH with decrypt.

## SECURITY NOTE

  zqm-hermes-skills repo contains real fleet passwords (344SW00DL4nd!,
  EllaRose89!) committed in 15 markdown docs — ROTATE + history-purge pending
  (see zqm-fleet-management findings). Treat as burned.
