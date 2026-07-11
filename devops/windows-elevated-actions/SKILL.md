---
name: windows-elevated-actions
description: Run PRIVILEGED Windows PowerShell actions (mount disks, firewall rules, service changes, anything needing admin) safely from a NON-elevated agent shell. Covers the UAC-denial trap where Start-Process -Verb RunAs -Wait reports success even when the prompt was dismissed, how to make scripts self-log to disk, and the mandatory re-verify-after-elevation step. Use whenever a PowerShell action fails with "Access is denied" or "CIM resource not available" and needs elevation — e.g. Set-Partition/Add-PartitionAccessPath (disk mount), New-NetFirewallRule, Set-Service, anything touching admin-only CIM.
---

# Windows Elevated Actions (from a non-elevated agent shell)

The agent terminal runs NON-elevated. Many real ops need admin: mounting a disk
(`Set-Partition -NewDriveLetter`), firewall rules (`New-NetFirewallRule`), service
config, etc. They throw `Access denied` / `Access to a CIM resource was not available`
when run non-elevated. This skill is the SAFE pattern to get them done.

## THE TRAP (cost me 3 failed attempts once)
`Start-Process powershell -Verb RunAs -Wait -ArgumentList "..."` does NOT report a
UAC denial as an error. If the user dismisses the UAC prompt (or it's silently
filtered because the parent shell isn't elevated), the process "returns" with
exit 0 and your script silently did NOTHING. You then verify and find the change
was never applied. Never trust "process returned."

## THE RELIABLE PATTERN
1. **Write the privileged script to a .ps1 file** (never inline PS — MSYS mangles `$`).
   Inside the script, wrap the action in try/catch and **write the outcome to a .log
   file on disk** (NOT just stdout — stdout from an elevated child may not reach you):
   ```
   $log = 'C:\Users\zqmco\thing_result.log'
   try {
       <the admin action, with -ErrorAction Stop>
       "OK: <what changed>" | Set-Content $log
   } catch {
       ("FAILED: " + $_.Exception.Message) | Set-Content $log
   }
   ```
2. **Launch elevated** from the non-elevated shell:
   `Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"<path>`""`
   This pops a UAC prompt on the user's desktop. They click yes.
3. **RE-VERIFY against live system state** — read the .log, THEN independently confirm
   the change took (Get-NetFirewallRule / Get-Volume -DriveLetter D / Get-Partition).
   The log is a hint; the live state is truth.
   For a *visual* second opinion (e.g. confirm the UAC prompt appeared, or the new
   drive letter shows in File Explorer), the `computer-use` skill's `capture` tool is
   the right cross-check — drive the desktop, don't re-shell it.

## Why self-logging matters
When you launch elevated with `-Wait` and no redirect, you get zero output if UAC was
denied. The script writing its own .log means the result is on disk regardless of
whether the elevated stdout reached you. Read the .log with read_file after the launch.

## Diagnose permission need WITHOUT elevation
To confirm an action truly needs admin (vs a script bug), run it non-elevated via -File:
if it throws "Access is denied." → elevation is required and the UAC path is the only way.
If it throws something else → it's a logic bug; fix the script, don't escalate.

## Common admin-only ops (verify-after list)
- Mount disk: `Set-Partition -InputObject $p -NewDriveLetter D` → verify `Get-Volume -DriveLetter D`.
  NOTE: `Get-Partition.DriveLetter` is `[char]`; unmounted returns `'\\0'`, NOT $null.
  Test with `[string]::IsNullOrWhiteSpace($p.DriveLetter.ToString())` before assuming mounted.
- Firewall: `New-NetFirewallRule -DisplayName X -Direction Inbound -LocalPort 11434 -Protocol TCP -RemoteAddress 192.168.1.0/24 -Action Allow` → verify `Get-NetFirewallRule -DisplayName X | Get-NetFirewallAddressFilter`.
- Service: `Set-Service` / `Start-Service` → verify `Get-Service -Name X`.
- Anything touching Windows Defender / WinRM listener config → admin.

## Safety / consent
- NEVER auto-elevate silently. The UAC prompt is the user's explicit grant; surfacing the
  elevated command and letting them click yes IS the consent flow. Do not attempt to bypass
  UAC (no scheduled-task-trickery, no credential embedding).
- NEVER put a password/credential in the script. For remote (WinRM) actions, prompt the
  user via `Read-Host -AsSecureString` inside the script, or use a session option that
  references a stored credential the user provided out-of-band.
- If a `clarify` times out, take the non-destructive path: write the script + hand the user
  the elevated command; do not guess at elevation.
- **Swarm tie-in:** inside a fleet-council-audit swarm, an elevated change's result must land
  in BOTH the self-log AND the swarm's `swarm_log`/`open_questions` (see fleet-council-audit →
  PERSIST FINDINGS TO SQLITE) so the coordination trail is honest. A privileged action that
  silently applied (or silently failed) is exactly the fact the blackboard/DB must record, not
  leave implicit. Cross-reference: fleet-council-audit owns the swarm shape; this skill owns
  the elevation mechanics.

## Remote execution via WinRM (fleet peers, from the non-elevated shell)
To run a privileged command ON A DIFFERENT node (e.g. probe Node-3 from the control
plane), use `Invoke-Command` over WinRM. The node creds live in `inventory.ini`
(Administrator, basic auth, cert validation ignored). Pattern:
- NEVER embed the password in the script or any file. Prompt at runtime with
  `Read-Host -AsSecureString` so the secret never enters the agent's context.
- `New-PSSession -ComputerName <ip> -Credential $cred -Authentication Basic
   -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck)`.
- Inside the remote `ScriptBlock`, gather facts and RETURN them (don't rely on a
  remote file write you can't read back). Re-verify the returned facts make sense.
- Test reachability first with `Test-WSMan -ComputerName <ip>` (no creds needed) —
  if that fails, the session will fail too; report the connectivity gap instead.
See `scripts/probe_remote_winrm.ps1` for the verified Node-3 Ollama probe used in
the 2026-07-10 swarm (self-documents the secure-credential + localhost-11434 check).

## Pitfalls
- `-Wait` + `-RedirectStandardOutput` are mutually exclusive parameter sets in Start-Process
  → pick `-Wait` (no redirect) and make the script self-log instead.
- Inline `-Command "..."` with `$_` breaks under MSYS bash → always `-File`.
- UAC dismissal = silent no-op, not an error. Always re-verify.
- A non-elevated `-ErrorAction SilentlyContinue` on Set-Partition returns no exception but the
  letter still won't apply → use `-ErrorAction Stop` + re-read the partition after.
