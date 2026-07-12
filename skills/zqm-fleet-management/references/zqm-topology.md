# ZQM Topology (verified 2026-07-10)

## Windows Nodes (workgroup, NOT domain-joined)
| Name | IP | .lan | Notes |
|------|-----|------|-------|
| Node-1 | 192.168.1.218 | ZQM-Node-1.lan | This host (agent runs here as zqmco). WinRM 5985 OPEN, indexer 5000 OPEN, SMB 445 OPEN. |
| Node-2 | 192.168.1.21 | ZQM-Node-2.lan | WinRM 5985 OPEN, SMB 445 OPEN, 5000 CLOSED. PSRemoting verified working. |
| Node-3 | 192.168.1.46 | ZQM-Node-3.lan | 445 OPEN only; 5985/5986/22 CLOSED (bootstrap NOT yet run — failed with UNC "-File does not exist" on Node-3 console; re-run via IP `\\192.168.1.173\web\zqm-bootstrap.ps1` or the local-copy `oneline-fix.txt` wrapper). |
| Node-4 | 192.168.1.215 | ZQM-Node-4.lan | **BOOTSTRAPPED (end-of-session):** 5985 (quickconfig) + 5986 (HTTPS WinRM) + 22 (OpenSSH) all OPEN; zqmlocal DPAPI-stored. NOTE: its zqmlocal password must match Node-1's `zqm-cred-node-local.json` or the fleet loop gets "Access is denied" (pitfall #13). |

## TrustedHosts on Node-1 (end-of-session)
WSMan:\localhost\Client\TrustedHosts = "192.168.1.21,192.168.1.46,192.168.1.215"  (all three nodes — widened by user, verified readable).
## Synology "Garden" NAS (DSM on :5001 / :5000)
10 Gardens accept DSM login (account `azelenski`) on :5001:
- GARDEN-02 family: 192.168.1.32, .37, .38, .39, .40
- GARDEN-03: 192.168.1.64
- Garden-01 family: 192.168.1.52, .53, .169, .173

2 outliers (NO DSM — Noon Technology Co., Ltd, MAC 6C:BF:B5):
- GARDEN-04: 192.168.1.144, 192.168.1.147  (open 80/443/5443, self-signed TLS; API unknown)

## Accounts
- Desktop/PowerShell human login: zqm-node-1\alexz
- Synology DSM admin: azelenski
| Node-3 | 192.168.1.46 | ZQM-Node-3.lan | 445 OPEN only; 5985/5986/22 CLOSED (bootstrap NOT yet run — failed with UNC "-File does not exist" on Node-3 console; re-run via IP `\\192.168.1.173\web\zqm-bootstrap.ps1` or the local-copy `oneline-fix.txt` wrapper). |
| Node-4 | 192.168.1.215 | ZQM-Node-4.lan | **BOOTSTRAPPED (end-of-session):** 5985 (quickconfig) + 5986 (HTTPS WinRM) + 22 (OpenSSH) all OPEN; zqmlocal DPAPI-stored. NOTE: its zqmlocal password must match Node-1's `zqm-cred-node-local.json` or the fleet loop gets "Access is denied" (pitfall #13). |

## TrustedHosts on Node-1 (end-of-session)
WSMan:\localhost\Client\TrustedHosts = "192.168.1.21,192.168.1.46,192.168.1.215"  (all three nodes — widened by user, verified readable).
