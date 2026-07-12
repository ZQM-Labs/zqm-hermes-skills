# ZQM Garden Fabric — Verified Topology, Protocol Matrix & Resilient Link

VERIFIED 2026-07-12 from Node-1 (192.168.1.218). Re-verify before acting; topology drifts.

## Garden plane (NAS clusters)
- Garden-01: .173 primary + .52/.53/.169. Synology DSM. .52/.53 share MAC = Synology HA pair. Protocols: DSM+SMB+SSH.
- GARDEN-02: .40 primary + .39/.38/.32/.37. Synology DSM. Protocols: DSM+SMB+SSH.
- GARDEN-03: .64. Synology DSM. Protocols: DSM+SMB+SSH.
- GARDEN-04: .144/.147. TERRASTER TOS — SMB+SSH ONLY, NO DSM. By-design, NOT a defect. Treat as first-class Garden. Protocols: SMB+SSH.

## Node plane (Windows WinRM)
- Node-1 .218 = management host (this host normally).
- Node-2 .21 = DEAD/offline (hardware/power recovery, not config).
- Node-3 .46 = WinRM OPEN.
- Node-4 .215 = WinRM OPEN; zqmlocal password is a KNOWN MISMATCH vs fleet (user set a different pw at bootstrap).

## Naming
"Gardens" = ZQM rebrand of CVG "Hives". A Garden = a NAS cluster (Synology DSM or TerraMaster TOS). A Node = a Windows host.

## CRITICAL CORRECTION (2026-07-12, user-flagged)
Do NOT frame a Garden's missing DSM as a "breakable point". TerraMaster runs TOS, not DSM — absence of DSM is by-design. The resilient link layer MUST be PROTOCOL-AWARE per Garden (encode `protocols` in the topology), and every Garden is a first-class member via its available protocols. The user expects FULL fabric resilience (Gardens + Nodes), not reduced scope. Don't offer a reduced-scope "door" as if a missing DSM were a limitation.

## Resilient link technique (proven this session)
- `C:\zqm\link\zqm-garden-link.ps1` + `C:\zqm\link\zqm-garden-topology.json`: name-resolve (.lan) -> multi-IP fallback across cluster members -> PERSISTENT SMB mount (`net use ... /persistent:yes`) -> self-heal scheduled task (boot + every 15 min) -> DryRun-safe (no mounts, no cred use).
- DryRun proves fallback chains for all clusters WITHOUT touching mounts or credentials.
- Garden-04 SSH failover proven via paramiko + DPAPI: decrypt cred with `System.Security.Cryptography.ProtectedData]::Unprotect($raw, $null, 'LocalMachine')`, then pipe the password into the python process over STDIN (NEVER echo to terminal). Both .144/.147 returned `ZQM-GARDEN-04`, ~16d uptime.
- WinRM from Node-1 to nodes needs an explicit zqmlocal cred (error 0x8009030e = no cached logon session, NOT a connectivity failure).

## Re-verify checklist (run before claiming state)
- `Resolve-DnsName` for every Garden(.lan) + node resolves.
- SMB 445 + (DSM 5000 for Synology | SSH 22) open per the topology `protocols` list.
- Garden-04: assert NO DSM port, but SSH path live.
- WinRM port 5985/5986 open on the target node before attempting remoting.
