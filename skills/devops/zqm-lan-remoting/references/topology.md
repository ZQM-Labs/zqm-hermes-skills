# ZQM LAN Topology (verified 2026-07)

## Windows nodes — workgroup, NOT domain-joined
| Node   | IP             | .lan                  | MAC                     | Status (2026-07)                         |
|--------|----------------|-----------------------|-------------------------|------------------------------------------|
| Node-1 | 192.168.1.218  | ZQM-Node-1.lan        | 08:9d:f4:aa:d2:82       | This host. WinRM up, 445/5000/5985 open. |
| Node-2 | 192.168.1.21   | ZQM-Node-2.lan        | —                       | WinRM up (5985), reachable via .\zqmlocal |
| Node-3 | 192.168.1.46   | ZQM-Node-3.lan        | —                       | 5985 closed — bootstrap NOT yet run      |
| Node-4 | 192.168.1.215  | ZQM-Node-4.lan        | —                       | 5985 closed — bootstrap NOT yet run      |

NOTE: IPs are NON-sequential. Node-3=.46, Node-4=.215. Resolve `.lan` DNS; do not guess.

## Synology NAS "ZQM-Gardens" (SMB/445 open)
| Name                 | IP             | MAC                     | Notes                                    |
|----------------------|----------------|-------------------------|------------------------------------------|
| ZQM-Garden-01        | 192.168.1.173  | 90:09:D0:53:B6:44       |                                          |
| ZQM-Garden-02        | 192.168.1.40   | 90:09:D0:3D:D2:FC       | Node-1 holds live IPC$; `web` + `UNASSIGNED-01` writable w/o re-auth |
| ZQM-Garden-03        | 192.168.1.64   | 00:11:32:C7:95:D2       |                                          |
| ZQM-GARDEN-04        | 192.168.1.144  | 6C:BF:B5:02:83:2C       | (also .147)                              |
| ZQM-GARDEN-04        | 192.168.1.147  | 6C:BF:B5:02:83:2C       |                                          |

Garden-02 shares observed: NetBackup, UNASSIGNED-01, UNASSIGNED-02, UNASSIGNED-03, web, web_packages.

## Script drop location (verified writable)
  \\192.168.1.40\web\zqm-bootstrap.ps1
  \\192.168.1.40\UNASSIGNED-01\zqm-bootstrap.ps1
Local copy on Node-1: C:\Users\zqmco\zqm-bootstrap.ps1 (sha256 8dba6cbe…fe92b, 2024 bytes)
