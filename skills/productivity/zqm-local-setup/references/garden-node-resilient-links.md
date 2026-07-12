# Resilient Garden & Node Links (self-healing fabric) — ZQM 2026-07-12

Pattern proven live this session: make ZQM Garden connections UNBREAKABLE on reboot and
across individual Garden-IP failures, and make Node monitoring honest about workgroup auth limits.

## A. GARDEN LINK LAYER (persistent, self-healing, name-resolved)

Goal: every Node holds persistent SMB mounts to every Garden, re-established on boot + on a
timer, with automatic fallback across the Garden cluster's member IPs if one drops.

Verified topology (DNS name → cluster, live 2026-07-12 from Node-1 .218):
- Garden-01 `.173` (+`.52/.53/.169`) share `web`, protocols dsm/smb/ssh
- GARDEN-02 `.40` (+`.32/.37/.38/.39`) share `web`, protocols dsm/smb/ssh
- GARDEN-03 `.64` share `web`, protocols dsm/smb/ssh
- GARDEN-04 `.144/.147` (TerraMaster) share `public` (NOT `web`!), protocols smb/ssh ONLY — no DSM

Artifacts built this session (on Node-1 at `C:\zqm\link\`):
- `zqm-garden-topology.json` — canonical map: per-Garden `members[]`, `protocols[]`, `share`, `ha`.
- `zqm-garden-link.ps1` — resolves Garden by `<name>.lan`, falls back across `members[]` by SMB:445
  reachability, mounts ONE persistent drive letter PER Garden (`/persistent:yes`), registers a
  SYSTEM self-heal task (boot + every 15 min, idempotent — skips already-correct mounts).
- `zqm-garden-failover.ps1` — protocol-aware DSM→SSH→SMB best-plane selector (verified: Garden-04
  correctly resolves to SSH because it declares no DSM).
- `install_selfheal.ps1` — registers the `ZQM-Garden-Link` scheduled task as SYSTEM.

Why SYSTEM works for SMB mounts: SMB `net use /user:<cred>` presents the cred explicitly, so it
does NOT need a network logon identity — SYSTEM is fine. (See Node section for why WinRM differs.)

### KEY PITFALLS HIT + FIXED (PowerShell 5.1 on Node-1)
- **One drive letter for all gardens** → each Garden needs its own letter (Z/Y/X/W) or later mounts
  clobber earlier ones.
- **`net use ... | Select-Object -First 2` masks `$LASTEXITCODE`** → false-negative "MOUNT FAIL" when
  the mount actually succeeded. FIX: run `net use` via `Start-Process cmd.exe -ArgumentList "/c",...`
  and read `$proc.ExitCode` + redirected stdout/stderr files.
- **`$dl:` unquoted in a string** → parser error "invalid variable reference". FIX: use `${dl}:`.
- **TerraMaster share name ≠ Synology** → Garden-04 is `public`, not `web`. Discovered by SSHing the
  box and reading `/etc/samba/smb.conf` (`[public]` path `/Volume1/public`), NOT by guessing.
  GENERAL RULE: verify a remote share name via SSH/`net conf list` before assuming it matches another
  vendor's convention.
- **Scheduled task registration needs elevation** → `Register-ScheduledTask` with a SYSTEM principal
  returns "Access is denied" from a non-elevated session. The agent MAY self-elevate when the user
  approves: `Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy
  Bypass -File <script>'`. Non-elevated sessions cannot even READ a SYSTEM-owned task (it shows
  "MISSING" via `Get-ScheduledTask`); verify SYSTEM tasks from an elevated context.
- **`-RepetitionInterval` without `-Once`** errors ("missing -Once"). And `-RepetitionDuration
  ([TimeSpan]::MaxValue)` overflows (max 248 days) → drop the duration cap.

## B. NODE FLEET REMOTING (the hard gate: WORKGROUP + Negotiate)

`zqm-node-fleet.ps1` (Node-1) probes every Node via WinRM (Negotiate) with SSH(paramiko) fallback,
using the vaulted `zqm-cred-node-local.json` (LocalMachine DPAPI). Verified live behavior 2026-07-12:
- Node-1: local OK. Node-2 `.21`: UNREACHABLE (dead/powered off).
- Node-3 `.46`: WinRM OK (vaulted `zqmlocal` authenticates).
- Node-4 `.215`: CRED-MISMATCH — WinRM "Access is denied" AND SSH "Authentication failed" with the
  SAME vaulted cred → Node-4's local `zqmlocal` has a DIFFERENT password. PROVEN by two protocols,
  not assumed. Fix: set Node-4's local `zqmlocal` to the fleet password (re-run bootstrap typing the
  shared password, or `Set-LocalUser -Name zqmlocal -Password $sec` on Node-4).

### CRITICAL WORKGROUP FINDING (cost many cycles — capture it)
A **scheduled task** (SYSTEM principal OR `zqmlocal` run as batch/service logon) CANNOT authenticate
to a remote WORKGROUP Windows node over WinRM. Root cause: the nodes only offer `Negotiate`
(Basic auth is disabled — server reports "Possible authentication mechanisms: Negotiate"), and
Negotiate from a non-interactive scheduled principal to a workgroup peer fails (no domain, no
delegatable network identity) → "Access is denied". The exact same code run INTERACTIVELY as the
logged-in management user succeeds.

Consequences / options to make node-health monitoring headless (pick one, surface to user — do NOT
guess passwords or silently enable security-downgrade features):
1. **Run the health task as the logged-in management user** (needs that user's password →
   `Register-ScheduledTask -User '<host>\alexz' -Password <pw>`). Cleanest, no security tradeoff.
   NOTE: `Register-ScheduledTask` takes `-User`/`-Password` directly — `New-ScheduledTaskPrincipal
   -Password` does NOT exist (ParameterBindingException). Use the task cmdlet's own params.
2. **Enable CredSSP** (client on Node-1, server on Node-3/4) so a SYSTEM task can delegate → then
   SYSTEM principal works. REAL attack-surface tradeoff; require explicit user approval before applying.
3. **Leave node-health interactive/ondemand** (`zqm-node-fleet.ps1 -Health` run on demand). The
   Garden links remain fully self-healing regardless — that part needs no network-logon identity.

### PowerShell 5.1 traps specific to CIM/WinRM probing
- `New-CimSession` has NO `-UseSsl` param. SSL is selected by `Port 5986` + `New-CimSessionOption
  -UseSsl`. (`-UseSsl` does NOT go on `New-CimSession`.)
- `New-CimSessionOption` (not `New-PSSessionOption`) is the correct option type for CIM; passing a
  PSSessionOption yields "Cannot convert ... to type CimSessionOptions".
- `Test-WsMan -Authentication Default` with no cached logon returns `0x8009030e` ("specified logon
  session does not exist") — that is a CREDENTIAL-SESSION gap, not a connectivity failure. Supply an
  explicit `PSCredential`.
- Inline `python -c "...$pw..."` for SSH embeds the password in single quotes → breaks if the
  password contains a single quote. FIX: write the python to a temp `.py` file and pass cred via
  argv/stdin (see `scripts/zqm-dpapi-ssh.ps1` pattern). The session's `ssh_probe.py` + runner is the
  working template.

## C. REPLICATING THE FABRIC TO OTHER NODES
The 4 Garden-link files + `zqm-node-fleet.ps1` are portable. On Node-3/4: copy the files locally,
ensure `C:\\zqm\\cred\\zqm-cred-garden-admin.json` (LocalMachine DPAPI) exists on that node, then run
`zqm-garden-link.ps1 -Apply -InstallTask` (elevated) and `zqm-node-fleet.ps1 -Health`. Node-local
WinRM monitoring headless still subject to the section-B gate.

## D. CROSS-NODE PROVISIONING (proven push Node-1 -> Node-3, 2026-07-12)
Node-3/4 are WORKGROUP peers reachable by SSH (`zqmlocal` + fleet pw) but NOT by `-Verb RunAs`
headless. Pattern that worked:

1. **Transfer** the portable files with `scp.exe` (OpenSSH, not the bash `scp` alias which mangles
   paths): `scp.exe -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
   "C:/zqm/link/zqm-garden-link.ps1" "zqmlocal@192.168.1.46:C:/zqm/link/zqm-garden-link.ps1"`.
   Use FORWARD-slash POSIX dest (`C:/zqm/link/`), never backslash (MSYS mangles `C:\...` -> invalid).
2. **Provision the Garden cred ON THE TARGET** (DPAPI LocalMachine is machine-scoped — a Node-1-
   encrypted blob will NOT decrypt on Node-3). Sequence that leaves no plaintext on disk:
   (a) write the garden pw to `C:\zqm\link\pw.tmp` on Node-1; (b) `scp` it to the target;
   (c) run a remote `.ps1` that reads `pw.tmp`, encrypts via `ProtectedData::Protect(...,LocalMachine)`,
   writes `C:\zqm\cred\zqm-cred-garden-admin.json`, then `Remove-Item pw.tmp`; (d) delete `pw.tmp` on
   Node-1 too. VERIFIED `ROUNDTRIP_OK` for the re-encryption logic.
3. **Register the self-heal task**: from the SSH session run `Register-ScheduledTask` DIRECTLY
   (the SSH login user `zqmlocal` is admin on Node-3). Do NOT wrap in `Start-Process -Verb RunAs` —
   over a headless SSH session RunAs SILENTLY NO-OPS (no UAC surface) and the task never registers.
4. **`$PSScriptRoot` is EMPTY when a script is invoked over SSH by path** (`ssh ... "powershell -File
   C:\path\x.ps1"`). Scripts that default `$TopologyFile = Join-Path $PSScriptRoot ...` then throw
   "Cannot bind argument ... empty string". FIX: resolve script dir robustly:
   `$here = if($PSScriptRoot){$PSScriptRoot} elseif($MyInvocation.MyCommand.Path){Split-Path
   $MyInvocation.MyCommand.Path} else {'C:\zqm\link'}`. Apply to every script you push to a node.
5. **Make python paths dynamic** in any pushed script (Node-3 has NO python on PATH, no `py` launcher).
   Resolve via `Get-Command python/py` + venv search; fall back to `'python'`.

### PROVEN NODE-3 OUTCOME (2026-07-12)
After provisioning: `ZQM-Garden-Link` task registered (SYSTEM, boot+15min). `zqm-garden-link.ps1
-Apply` live result: Garden-02 (`Y:` -> .40\web) MOUNTED, Garden-04 (`W:` -> .147\public) MOUNTED,
**Garden-01 (.173\web) and Garden-03 (.64\web) BLOCKED** with "A specified logon session does not
exist" on `New-SmbMapping` — for `azelenski` AND `WORKGROUP\azelenski`/`GARDEN-01\azelenski` AND even
`admin` (which returned "password not correct", proving real auth). TCP:445 to .173/.64 is OPEN from
Node-3, and the SAME `azelenski`/pw mounts .173/.64 FINE from Node-1 (.218). => **Garden-01/03 reject
Node-3's SOURCE IP (.46) at the Garden (DSM SMB allowed-hosts / per-user IP allow). This is a
Garden-side ACL, NOT a Node config or credential bug.** Fix: on .173/.64 DSM, allow .46 (and .215 for
Node-4) — or issue a Node-specific garden credential. Do not loop on Node-side auth retries.

### NODE-4 GATE (2026-07-12) — build a self-bootstrap package
Node-4 (.215) is reachable (ping UP, 22/445/5985/5986 OPEN) BUT its local `zqmlocal` pw MISMATCHES
the vault (`EllaRose89!` rejected on SSH+WinRM). You CANNOT authenticate to Node-4 remotely until the
local pw is reconciled — and that reconcile requires a LOCAL action on Node-4 (console/RDP/WinRM-as-
local-admin), which the agent cannot perform. Per the "stop + surface the gate" rule, do NOT re-loop
auth attempts. Instead: build a self-contained package (`C:\zqm\node4-bootstrap\` with
`NODE4_BOOTSTRAP.ps1` + the 4 Garden files + `install_selfheal.ps1` + `NODE4_RECONCILE.md`) that runs
ON Node-4 after the user does the one local step:
   # local on Node-4 (elevated):  $sec = ConvertTo-SecureString 'EllaRose89!' -AsPlainText -Force; Set-LocalUser -Name zqmlocal -Password $sec
   # then (Option A) tell the agent "Node-4 reconciled" to SCP+run headless, or (Option B) on Node-4:
   .\NODE4_BOOTSTRAP.ps1 -GardenPassword '344SW00DL4nd!'
`NODE4_BOOTSTRAP.ps1` re-encrypts the garden pw with Node-4's LocalMachine key, registers the self-heal
task, and applies mounts — pure PowerShell, no python. Make `install_selfheal.ps1` path-relative (see
step 4) so the package runs from any drop location.
