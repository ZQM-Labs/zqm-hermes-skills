# ZQM Resilient Connectivity — Node ↔ Garden "unbreakable" link layer

Condensed, verified playbook for making ZQM Node→Garden and Node→Node connectivity
survive reboots, IP changes, and single-node failure. Derived from the 2026-07-12
"make connections unbreakable" build. All claims below were proven by live output.

## Topology facts (verified 2026-07-12 from Node-1 .218)
- Gardens resolve by DNS name (.lan) AND have 3–5 IPs each → name + multi-IP fallback is mandatory.
  - Garden-01 (Synology): .173 primary + .52/.53/.169 ; .52/.53 = HA active/passive pair (shared MAC 90:09:D0:4B:D1:6B).
  - GARDEN-02 (Synology): .40 + .39/.38/.32/.37.
  - GARDEN-03: .64.
  - GARDEN-04 (TerraMaster TOS): .144/.147 — NO DSM API (port 5000 closed); SSH/SMB only. SMB share is `public`, NOT `web`.
- Nodes: Node-1 .218 (mgmt, this host), Node-3 .46 + Node-4 .215 (WinRM 5985/5986 OPEN),
  Node-2 .21 (DEAD/offline — hardware bring-up, not config).
- Garden admin cred: C:\zqm\cred\zqm-cred-garden-admin.json (DPAPI LocalMachine blob, user=gardenadmin).
- Node remote-admin cred: C:\zqm\cred\zqm-cred-node-local.json (DPAPI LocalMachine blob, user=`zqmlocal`).

## CRITICAL GOTCHA — `zqmlocal` is NOT a local account on Node-1
Local accounts on Node-1: `AlexZ` (enabled, SID ...1001) and `zqmco` (enabled, SID ...1002).
`zqmlocal` is the REMOTE-node local-admin credential stored in the cred file. Registering a
scheduled task as `ZQM-NODE-1\zqmlocal` FAILS with "no mapping between account names and SIDs"
→ the task silently never runs (no error, no log). NEVER use `zqmlocal` as a local principal.
Use SYSTEM or AlexZ/zqmco for scheduled tasks.

## Door A — Garden links (persistent + self-healing) VERIFIED
Pattern (see C:\zqm\link\zqm-garden-link.ps1):
1. Per-garden drive letter (Z/Y/X/W), NOT one shared letter.
2. Resolve by name; on failure fall back across all member IPs (Test-NetConnection 445/22/5000).
3. `net use <drv>: \\<ip>\<share> /user:<user> <pw> /persistent:yes` — persistent survives reboot.
   Use `Start-Process cmd.exe -ArgumentList "/c","net use ..." -Wait` and read the process exit code
   (piping `net use | Select` hides $LASTEXITCODE → false negatives).
4. Self-heal: SYSTEM scheduled task, triggers AtStartup + Once/15-min repetition, runs the link
   script. SYSTEM works for SMB because net use embeds the cred (no network-logon identity needed).
5. Garden-04 TerraMaster: share=`public`; no DSM → protocol-aware (SSH/SMB only). Don't assume `web`.

## Door B — Node-fleet health/remoting (headless) VERIFIED via SSH plane
- WinRM on nodes offers ONLY Negotiate (Basic disabled by default). Enabling AllowBasic=1 on the
  service + restart does NOT make the server advertise Basic (still "Negotiate" only) — unreliable.
- Negotiate from a SYSTEM / scheduled principal to a WORKGROUP peer FAILS ("Access is denied").
  So WinRM cannot be the headless node plane.
- FIX: use SSH (OpenSSH :22) as the node plane. SSH is credential-based, needs NO network-logon
  identity → runs fine as SYSTEM. Decrypt the vaulted `zqmlocal` cred (DPAPI LocalMachine, works
  under SYSTEM) and connect via paramiko (or plink). Verified: Node-3 SSH OK headless; Node-4 SSH
  rejects the vaulted pw (its local `zqmlocal` has a DIFFERENT password → reconcile on Node-4).
- WinRM is still fine INTERACTIVELY as the mgmt user (Negotiate succeeds with a full logon token).
  Keep a WinRM+SSH interactive fabric (zqm-node-fleet.ps1) for on-demand use.

## PowerShell scheduled-task gotchas (costly, learned the hard way)
- `New-ScheduledTaskAction` parameter is `-Argument` (SINGULAR). Using `-Arguments` yields a NULL
  Action → "Cannot validate argument on parameter Action" at Register-ScheduledTask.
- `-Password` is INVALID on `New-ScheduledTaskPrincipal`. Pass `-User`/`-Password` to
  `Register-ScheduledTask` directly instead.
- SYSTEM principal CAN read DPAPI LocalMachine blobs (decrypt works). Good for headless cred use.

## Recovery procedures (documented, user-driven)
- Node-2 (.21) dead: power on / WOL; if WinRM closed, run bootstrap from \\<garden>\web\zqm-bootstrap.ps1
  as elevated, entering the FLEET password at the zqmlocal prompt. Node-1 TrustedHosts already lists .21.
- Node-4 (.215) zqmlocal mismatch: on Node-4 run `Set-LocalUser -Name zqmlocal -Password <fleet pw>`
  (or re-run bootstrap with fleet pw). Then Node-4 flips to OK on both WinRM and SSH.

## Cross-node replication (Node-1 → Node-3/4) — PUSH GOTCHAS (2026-07-12)
Pushing the link/monitor fabric to other nodes is NOT a file-copy. Learned the hard way:
- **DPAPI LocalMachine is MACHINE-SCOPED.** A cred blob encrypted on Node-1 will NOT decrypt on
  Node-3/4. Re-encrypt the credential ON the target with its own LocalMachine key. Before pushing
  Door A (garden links), confirm the target already has its own `zqm-cred-garden-admin.json`;
  if ABSENT (Node-3/4 are MISSING it), that node's garden self-heal is GATED until the garden
  password is re-entered there. Node-3 HAS node-local cred, MISSING garden cred.
  Node-1's garden user is `azelenski` (not `zqmlocal`).
- **Transfer via `scp.exe` (OpenSSH).** MSYS path translation mangles backslash dests
  (`C:\zqm\link\` → invalid "No such file or directory"). Use forward-slash POSIX dest `C:/zqm/link/`
  and `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no`. Verify with a follow-up `ssh` + `Test-Path`.
- **`Start-Process -Verb RunAs` from a headless SSH session SILENTLY NO-OPS** (no UAC surface to click).
  To register a scheduled task on a remote node, run `Register-ScheduledTask` DIRECTLY in the SSH
  session (works if the SSH login user is admin — `zqmlocal` is admin on Node-3). Do NOT wrap the
  installer in RunAs remotely.
- **Node-3 has NO python on PATH and no `py` launcher.** Scripts using paramiko/ssh_probe.py won't
  run there. A node does NOT need to host the fleet-health task (Node-1 is the manager); it only needs
  the Garden self-heal (Door A). Make python paths resolve dynamically (`Get-Command python/py` + venv
  search) so scripts survive on any host.
- **Prefer native `ssh.exe` for remote commands.** The paramiko python client intermittently throws
  "File is not open for reading" on these hosts (post-quantum key-exchange warning, harmless) while ssh.exe
  works fine.
- **Re-verify the pushed state LIVE** (task present, cred absent/gated, script present) — don't trust the scp exit banner.

## Deliverables produced (on Node-1, under C:\zqm\link)
- zqm-garden-topology.json (verified map) · zqm-garden-link.ps1 (Door A) · zqm-garden-failover.ps1
  (protocol-aware DSM→SSH→SMB) · zqm-node-fleet.ps1 (WinRM+SSH, interactive) ·
  zqm-node-fleet-ssh.ps1 (SSH plane, headless) · NODE4_RECONCILE.md · NODE2_RECOVERY.md
- Registered tasks: ZQM-Garden-Link (SYSTEM, boot+15m) on Node-1 AND Node-3.
  ZQM-Node-Fleet-Health (SYSTEM, boot+15m, SSH) on Node-1 ONLY (Node-3 has no python;
  Node-1 is the manager — do NOT re-register the health task on Node-3, it silently produces no log).

## ADVANCED DIAGNOSIS & RECOVERY (added 2026-07-12, live-proven)
### SMB mount per-session visibility (verification trap)
A mount created in one session (e.g. the SYSTEM self-heal task's session) is NOT visible to a
different token. A fresh elevated/admin `net use` shows "no entries", and writing to the UNC
without a cred fails. This is a SESSION artifact, not a broken link. To VERIFY a Garden is
reachable+writable: mount the UNC WITH the cred inside the SAME script, write+read a probe
file, then unmount. That is the authoritative test. (This is why a naive "drive Z: missing →
FAIL" claim is false — re-probe with cred.)

### Garden-side IP-allowlist diagnosis (Garden-01/.173 + Garden-03/.64 block recipe)
Symptom on Node-3 (.46): the SAME `azelenski`/password mounts Garden-02 (.40) + Garden-04
(.147) from Node-3, but Garden-01 (.173) + Garden-03 (.64) fail — yet the SAME cred mounts
.173/.64 fine from Node-1 (.218). Decisive diagnosis (run from the failing node):
  1. `Test-NetConnection -ComputerName <ip> -Port 445` → OPEN. Rules out firewall/network block.
  2. `New-SmbMapping -RemotePath \\<ip>\share -UserName azelenski -Password <pw>` →
     "A specified logon session does not exist" (1312). Try every format
     (bare, `WORKGROUP\azelenski`, `GARDEN-01\azelenski`, `GARDEN-03\azelenski`) → all 1312.
  3. Try user `admin` + same pw → "The specified network password is not correct" (1326).
     This proves the box does REAL auth and the password IS valid for `azelenski`.
  => Conclusion: those Synology boxes REJECT the failing node's SOURCE IP for the `azelenski`
     SMB logon (DSM SMB allowed-hosts / per-user IP allow that includes .218 but excludes .46).
     Fix lives on the DSM (.173/.64): add the node IP to allowed hosts, or issue a node-specific
     garden credential. NOT a Node config bug, NOT a credential error, NOT fixable from the node.
  (Do NOT confuse 1312 "logon session" with 67 "network name cannot be found" — 67 means the
  UNC/share name is wrong or got mangled by shell quoting; always quote the password in tests.)

### `$PSScriptRoot` is EMPTY when a script runs over SSH by absolute path
`powershell -File C:\zqm\link\foo.ps1` invoked via ssh.exe yields empty `$PSScriptRoot`, so a
default `-TopologyFile (Join-Path $PSScriptRoot 'x.json')` becomes empty → "Cannot bind argument…
empty string" → script aborts with no mounts. Resolve robustly:
  $scriptDir = if ($PSScriptRoot) { $PSScriptRoot }
               elseif ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path }
               else { 'C:\zqm\link' }

### Recovering a wedged sshd remotely
If an scp/ssh attempt wedges OpenSSH on a node (connection resets on connect), restart it via
WinRM CIM from a node that can auth (uses the vaulted node-local cred):
  $s = New-CimSession -ComputerName <ip> -Credential $cred -Authentication Negotiate
  $svc = Get-CimInstance -CimSession $s -ClassName Win32_Service -Filter "Name='sshd'"
  Invoke-CimMethod -CimSession $s -InputObject $svc -MethodName StopService  # then StartService
Confirm with `Get-Service sshd` via CIM; native `ssh.exe` then reconnects (paramiko may still
flap — use ssh.exe for the post-recovery check).
