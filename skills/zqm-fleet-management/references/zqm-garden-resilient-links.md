# ZQM Garden Resilient Links — verified fabric + pitfalls

Condensed from the 2026-07-12 "unbreakable connections" session. The goal was to make
Node→Garden connections survive reboot, IP loss, and protocol differences.

## USER CORRECTION (load-bearing)
A Garden lacking DSM (e.g. TerraMaster GARDEN-04) is NOT a "breakable point" — it is a
by-design protocol difference. Do NOT frame absent-DSM / absent-feature as fragility.
The link layer must be PROTOCOL-AWARE per Garden (topology declares which protocols each
Garden supports), and failover should treat a non-DSM Garden's SSH/SMB plane as its PRIMARY
plane, not a degraded state. "A+B" (resilient link + failover) is fully possible even for
non-Synology Gardens because the design is per-Garden, not one-size-fits-all.

## Verified topology (live from Node-1, 2026-07-12)
Gardens are CLUSTERS (not single boxes); each has 3-5 IPs for fallback:
- ZQM-Garden-01 (.173 primary + .52/.53/.169) — Synology, dsm+smb+ssh. .52/.53 share MAC = HA pair.
- ZQM-GARDEN-02 (.40 primary + .39/.38/.32/.37) — Synology, dsm+smb+ssh.
- ZQM-GARDEN-03 (.64) — Synology, dsm+smb+ssh.
- ZQM-GARDEN-04 (.144 + .147) — TerraMaster TOS, smb+ssh ONLY (no DSM/5000). SMB share is `public` (NOT `web`).

Nodes: Node-1 .218 (mgmt, this host), Node-2 .21 (DEAD/offline), Node-3 .46 (WinRM open),
Node-4 .215 (WinRM open; its zqmlocal password is a KNOWN MISMATCH vs the fleet cred).

## Design that delivered resilience (Door A + B, Garden-side)
1. Persistent SMB mounts via `net use ... /persistent:yes` -> survive reboot. One drive
   letter PER Garden (Z:/Y:/X:/W) — not one shared letter.
2. Name resolution + multi-IP FALLBACK: resolve Garden by DNS `.lan` name first; if it
   fails, fall back across all cluster member IPs (probed live for :445/:22/:5000).
3. Protocol-aware failover (Door B): pick best management plane DSM -> SSH -> SMB. For
   Garden-04 the correct answer is SSH@.147 (no DSM by design).
4. Self-heal scheduled task: boot + every 15 min, idempotent (skips already-correct mounts).

## Reusable module (lives at C:\zqm\link\ on Node-1; replicate to Node-3/4 with their garden cred)
- zqm-garden-topology.json  — canonical map (per-Garden share name + protocols + HA flag)
- zqm-garden-link.ps1       — persistent multi-IP SMB link layer (+ -DryRun safe mode)
- zqm-garden-failover.ps1   — protocol-aware DSM/SSH/SMB failover map
- install_selfheal.ps1      — boot + 15-min self-heal scheduled task (needs ADMIN to register)

## POWERSHELL PITFALLS debugged this session (all cost real failures)
- PS 5.1 has NO ternary operator (`cond ? a : b` is a syntax error). Use `if/else`.
- Drive-letter var in a string: `$dl:` parses wrong -> use `${dl}:` or quote it `"${dl}:"`.
- `net use ... 2>&1 | Select-Object -First 2` DISCARDS `$LASTEXITCODE` -> FALSE NEGATIVES
  (script reported MOUNT-FAIL while the mount actually succeeded). Capture exit code via
  `Start-Process -FilePath cmd.exe -ArgumentList "/c","net use ..." -Wait -PassThru` and read
  `$proc.ExitCode`. This is the correct pattern for any net-use/cmd success check.
- `Register-ScheduledTask` with `New-ScheduledTaskPrincipal -UserId SYSTEM` requires ELEVATION
  ("Access is denied" from a non-elevated shell). Do NOT self-elevate (user rule) — emit the
  exact admin command and let the user run it. Also: a non-elevated agent CAN still run the
  `net use` mounts themselves (those succeed under the current user); only the SYSTEM task reg
  is gated.
- `-RepetitionInterval` requires a base `-Once` (or `-AtStartup`) trigger; and
  `-RepetitionDuration ([TimeSpan]::MaxValue)` OVERFLOWS the scheduler (max ~248 days) ->
  "task XML contains a value which is incorrectly formatted". Just omit -RepetitionDuration.
- Per-vendor SMB share names differ: Synology = `web`; TerraMaster = `public`. Do NOT assume
  one share name across all Gardens — discover via SSH (`cat /etc/samba/smb.conf`) when unsure.

## Password-without-chat pattern (reuse from windows-secure-credential-handoff)
Decrypt garden DPAPI cred (machine-scope ProtectedData) in PS, then pipe the password into a
Python process over stdin (BaseStream.Write) so it never hits the terminal/transcript. Proven
for paramiko SSH to TerraMaster Garden-04.

## Gate remaining after this session (for the full fleet A+B)
- Node-1 -> Node-3/4 WinRM remoting + SSH fallback: needs zqmlocal cred vaulted; Node-4's
  zqmlocal must be reconciled to the fleet password (or re-run bootstrap with EllaRose89!).
- Node-2 (.21) is DEAD (powered off) — hardware bring-up, not config. Recovery = documented
  procedure + WOL/manual power-on, then bootstrap.
