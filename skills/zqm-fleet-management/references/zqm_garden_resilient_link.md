# ZQM Garden — Resilient Link Layer (verified live 2026-07-12)

Makes Node → Garden connections *unbreakable*: name-resolved + multi-IP fallback +
persistent self-healing SMB mounts + protocol-aware DSM/SMB/SSH failover.

## Topology (source of truth)
`C:\zqm\link\zqm-garden-topology.json` — canonical, verified map. Per-Garden fields:
`primary`, `members[]` (cluster IPs for fallback), `protocols[]` (dsm/smb/ssh), `ha`,
`share` (the SMB share NAME — NOT always `web`), `notes`.

## Scripts (on Node-1; replicate to Node-3/4 with their local garden DPAPI cred)
- `zqm-garden-link.ps1` — main link layer. Resolves each Garden by DNS name (.lan), falls
  back across `members[]` IPs, mounts ONE persistent drive letter per Garden (`/persistent:yes`),
  idempotent (skips already-correct mounts). `-DryRun` safe; `-Apply` mounts; `-InstallTask`
  registers the self-heal task.
- `zqm-garden-failover.ps1` — protocol-aware failover map: picks best management plane per
  Garden (DSM → SSH → SMB). `-DryRun` reports plan; `-Apply` delegates SMB persistence.
- `install_selfheal.ps1` — registers `ZQM-Garden-Link` scheduled task (SYSTEM principal,
  boot + 15-min repeat) that re-runs `zqm-garden-link.ps1 -Apply`. **Needs elevation.**
- `verify_final.ps1` / `verify_task_elevated.ps1` — post-deploy proof (mount + write/read +
  task presence from elevated context).

## KEY LESSONS (do not regress)
1. **By-design ≠ fragility.** Garden-04 is a TerraMaster (runs TOS), so it has NO DSM API
   (port 5000 closed) — that is correct, NOT a failure. Tooling must treat `dsm` as optional
   per topology and use SSH/SMB there. The user explicitly pushed back when DSM-absence was
   listed as a "breakable point." Protocol/device differences are FIRST-CLASS, never degraded.
2. **Per-device SMB share name differs.** Synology Gardens expose `web`; Garden-04 (TerraMaster)
   exposes `public`. DISCOVER the share via SSH (`cat /etc/samba/smb.conf`), never assume `web`.
   Assuming `web` on Garden-04 produced `System error 59` until corrected to `public`.
3. **One drive letter per Garden.** Mapping all gardens to `Z:` collides — assign Z/Y/X/W.
4. **Capture `net use` exit code correctly.** Piping `net use ... 2>&1 | Select-Object` hides
   `$LASTEXITCODE` → false-negative "MOUNT FAILED". Use `Start-Process -FilePath cmd.exe
   -ArgumentList "/c","net use ..." -Wait -PassThru` and read `.ExitCode`.
5. **Self-heal task must run as SYSTEM** to work with no user logged in (uses LocalMachine
   DPAPI + network). Non-elevated `Get-ScheduledTask` reports it MISSING — verify elevated.

## Deployment (per node)
1. Copy the 4 link files to `C:\zqm\link\` on the node.
2. Ensure that node's garden admin DPAPI cred exists at `C:\zqm\cred\zqm-cred-garden-admin.json`
   (machine-scope ProtectedData; same shape as Node-1's).
3. `powershell -ExecutionPolicy Bypass -File C:\zqm\link\zqm-garden-link.ps1 -Apply` (mounts).
4. ELEVATED: `powershell -ExecutionPolicy Bypass -File C:\zqm\link\install_selfheal.ps1` (task).
