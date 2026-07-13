# ZQM Topology (verified 2026-07-12)

## Windows Nodes (workgroup, NOT domain-joined)
| Name | IP | .lan | Notes (2026-07-12) |
|------|-----|------|-------|
| Node-1 | 192.168.1.218 | ZQM-Node-1.lan | This host (agent runs here as zqmco). WinRM 5985 OPEN, fed-indexer 5000 OPEN, SMB 445 OPEN, Ollama/SearXNG/AnythingLLM running. |
| Node-2 | 192.168.1.21 | ZQM-Node-2.lan | ON but NO open ports (22/80/445/5985 all closed). Untouchable — cannot host a peer. |
| Node-3 | 192.168.1.46 | ZQM-Node-3.lan | **LIVE FEDERATION PEER** (fleet_nodes=1). SSH✓ as zqmlocal (Win32-OpenSSH 9.5). Embedded Python 3.12 at C:\py312; peer runs as AtStartup scheduled task `ZQM-NodeIndexer`. SMB 445 OPEN, WinRM 5985 CLOSED. |
| Node-4 | 192.168.1.215 | ZQM-Node-4.lan | Ollama LIVE (qwen3:32b etc). SSH✗ + WinRM✗ as zqmlocal — AUTH GATE. Needs local Set-LocalUser on .215 to match node-local DPAPI cred before it can be a peer. |
| xyo-bridge | 192.168.1.164 | xyo-bridge.lan | Raspberry Pi (B8:27:EB). :22 OPEN. **Next viable peer candidate** — SSH login not yet known (node-local & garden-admin both rejected). |

## TrustedHosts on Node-1
WSMan:\localhost\Client\TrustedHosts = "192.168.1.21,192.168.1.46,192.168.1.215"

## Synology "Garden" NAS (DSM on :5001 / :5000) — staging/NAS only, NOT peer hosts
10 Gardens accept DSM login (account `azelenski`) on :5001:
- GARDEN-02 family: 192.168.1.32, .37, .38, .39, .40
- GARDEN-03: 192.168.1.64
- Garden-01 family: 192.168.1.52, .53, .169, .173

2 outliers (NO DSM — Noon Technology Co., Ltd, MAC 6C:BF:B5):
- GARDEN-04: 192.168.1.144, 192.168.1.147 (open 80/443/5443, self-signed TLS)

## Staging drop channel
Garden-02 .40 `web` share = reliable fleet staging drop point. From Node-1: SSH as `azelenski` writes work; SMB from Node-1 is denied (per-IP allowlist). Node peer files (node_indexer.py, indexer_lib.py, requirements.txt, zqm-bootstrap.ps1) staged there 2026-07-12.

## Accounts
- Desktop/PowerShell human login: zqm-node-1\alexz
- Synology DSM admin: azelenski
- Node local (zqmlocal): DPAPI-stored (C:\zqm\cred\zqm-cred-node-local.json) — works on Node-3, rejected on Node-4.

## DEAD (router-confirmed offline 2026-07-12)
192.168.1.20 (S124FNTF23026628), .90 (SHENZHEN BILIAN), .91 (HPI4DF291), .172 (Google-Nest-Mini)

## Federation status
- Aggregator: Node-1 (.218) — /api/federate merges local + peer results, tags by source IP.
- Peers live: Node-3 (.46). Peers pending: xyo-bridge (.164, needs SSH cred); Node-4 (.215, needs local pw reset).
