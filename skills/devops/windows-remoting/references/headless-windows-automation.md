# Headless Windows Automation (workgroup nodes) — reusable patterns

Patterns extracted from a multi-node "unbreakable Garden links" deployment (ZQM Nodes 1–4,
Synology/TerraMaster Gardens). All bit in production; each has a deterministic fix.

## 1. DPAPI `ProtectedData` blobs are MACHINE-scoped
A credential encrypted with `ProtectedData::Protect(..., 'LocalMachine')` on Node-A will NOT
decrypt on Node-B. Re-encrypt the secret ON the target node with its own LocalMachine key.
Round-trip test before shipping:
```powershell
$pw='...'; Add-Type -AssemblyName System.Security
$b=[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($pw),$null,'LocalMachine'))
$back=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($b),$null,'LocalMachine'))
($back -eq $pw)  # ROUNDTRIP_OK
```
Never copy a Node-1-encrypted cred file to another node and expect it to decrypt.

## 2. `$PSScriptRoot` is EMPTY when invoked over SSH by path
`ssh user@host "powershell -File C:\path\script.ps1"` -> `$PSScriptRoot` resolves to '' inside the
script, so `Join-Path $PSScriptRoot 'x'` fails ("empty string") and the config default path
silently breaks. Resolve the dir robustly at the top of every script:
```powershell
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot }
             elseif ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path }
             else { 'C:\zqm\link' }
```

## 3. Registering scheduled tasks HEADLESS (no UAC surface)
`Start-Process -Verb RunAs` from a headless SSH / SYSTEM session SILENTLY NO-OPS (no UAC prompt
can render). Run `Register-ScheduledTask` DIRECTLY in the SSH session if the SSH login user is a
local admin. Idempotent pattern:
```powershell
$action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Apply"
$triggerB = New-ScheduledTaskTrigger -AtStartup
$triggerP = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'ZQM-Garden-Link' -Action $action -Trigger @($triggerB,$triggerP) -Principal $principal -Force
```
`New-ScheduledTaskAction` takes `-Argument` (SINGULAR). `-Arguments` (plural) => null Action =>
"Cannot validate argument on parameter Action".

## 4. SYSTEM principal CANNOT WinRM/Negotiate to a workgroup peer
A SYSTEM scheduled task has no delegatable network identity; WinRM Negotiate to a workgroup peer
fails ("Access is denied" / 0x8009030e). Enabling `AllowBasic` on the target does NOT make the
server advertise Basic (remains Negotiate-only). Use SSH (OpenSSH :22) as the headless node plane
- SYSTEM can SSH out fine (key/password), no network-logon identity required.

## 5. Paramiko client flaky on these hosts -> use `ssh.exe`
Python paramiko intermittently throws "File is not open for reading" (post-quantum key-exchange
warning, harmless) while native `ssh.exe` works perfectly. Prefer `ssh.exe` / `scp.exe` (OpenSSH)
for remote commands and file transfer on ZQM nodes. `scp.exe` dest must use forward-slash POSIX
path (`C:/zqm/link/`), not backslash (`C:\zqm\link\` -> mangled by MSYS). Use
`-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no` for unattended copies.

## 6. Garden SMB "System error 1312 / logon session does not exist"
`net use \\ip\share /user:azelenski <pw>` returns 1312 on SOME garden IPs while the SAME cred
works on OTHERS (and from a different node on the failing IP) => GARDEN-SIDE IP allowlist
(Synology DSM SMB allowed-hosts / per-user IP restriction) includes one node's IP but excludes
another. NOT a password/format issue: every username format (bare / WORKGROUP\ / GARDEN-0X\) fails
with 1312, while `admin`+same pw returns "password not correct" (confirms real auth). Fix lives on
the Synology DSM (allow the node's IP), not on the node. Rule out a plain network block first by
probing TCP 445 (OPEN here) - 1312 + OPEN port = IP-allowlist, not firewall.

## 7. Per-session mount visibility
Drive-letter mounts (`net use Z:`) created by a SYSTEM task live in the SYSTEM session; an
interactive/elevated session cannot see them without an explicit `net use \\unc /user:`. For
verification, probe the UNC path with explicit credentials, not the drive letter.
