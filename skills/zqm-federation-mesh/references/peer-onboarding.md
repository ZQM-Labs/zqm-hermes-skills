# Peer Onboarding (Windows node) — proven on Node-3 (.46), 2026-07-12

Goal: bring a new Windows fleet node online as a federation indexer peer + CoreDNS client.

## 1. Python (node has none by default)
  • SCP embedded Python zip to C:\python312-embed.zip, unzip to C:\py312.
  • FIX python312._pth: add `import site` + `Lib\site-packages` (without this,
    pip-installed flask/whoosh are invisible — cost one debug cycle).
  • bootstrap pip: `C:\py312\python.exe get-pip.py` → pip in C:\py312\Lib\site-packages.

## 2. Deps
  C:\py312\python.exe -m pip install flask==3.0.0 whoosh==2.7.4 waitress==2.1.2

## 3. Drop peer code
  • node_indexer.py + indexer_lib.py into C:\zqm-indexer\.
  • Index roots: DEFAULT_ROOTS = ZQM_INDEX_ROOT env OR C:\Users\<user>\ZQM.
    Put files there (or set ZQM_INDEX_ROOT) BEFORE first index, else index is empty.
    NOTE: build_index(None) returns EMPTY by design (never walk bare home dir).

## 4. Firewall (:5000 must be in ActiveStore + active profile)
  New-NetFirewallRule -DisplayName "ZQM-NodeIndexer-5000" -Direction Inbound `
    -Protocol TCP -LocalPort 5000 -Profile Private -Action Allow -PolicyStore ActiveStore
  # verify: Get-NetFirewallRule -DisplayName "ZQM-NodeIndexer-5000" | Get-NetFirewallRule -PolicyStore ActiveStore
  (A rule landed in PersistentStore-only once and did NOT allow LAN probes — recreate against ActiveStore.)

## 5. Persist the process (survives SSH disconnect + reboot)
  • pythonw.exe ALONE via SSH does NOT survive session close.
  • Scheduled Task "AtStartup" with action `C:\py312\python.exe C:\zqm-indexer\node_indexer.py`
    (direct pythonw action, NOT `cmd /c start` wrapper — wrapper failed to bind :5000).
  • OR Win32_Process.Create via WMI to detach from the SSH session.

## 6. Join from Node-1 (aggregator)
  • Add peer IP to federation_nodes.json (runtime registry).
  • Hit http://127.0.0.1:5000/api/fleet/nodes/add  (or force rediscover).
  • Verify: GET /api/federate?q=<term> → fleet_nodes >= 1, peer hits tagged _node.

## 7. CoreDNS on the new node (CRITICAL — see CoreDNS pitfall in SKILL.md)
  Set-DnsClientServerAddress -InterfaceIndex <wifi> -ServerAddresses @('192.168.1.215','192.168.1.1')
  Disable-NetAdapterBinding -Name "Wi-Fi" -ComponentID ms_tcpip6   # MUST do this
  Clear-DnsClientCache
  # verify: Resolve-DnsName gateway.zqm  → 192.168.1.215 (NOT forced -Server)

## Verification checklist
  [ ] peer :5000/api/health returns ready from Node-1
  [ ] /api/federate on Node-1 shows fleet_nodes >= 1 and a peer-tagged hit
  [ ] new node resolves gateway.zqm via OS-default DNS (no -Server flag)
