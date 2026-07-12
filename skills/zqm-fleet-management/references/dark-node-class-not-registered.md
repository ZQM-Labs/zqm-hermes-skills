# Pitfall #19 — `Get-WindowsCapability -Online` "Class not registered" (Win10 Pro)

## Symptom
A node bootstrap run completes 5985 (winrm quickconfig) + zqmlocal DPAPI-store +
the 5986 HTTPS listener (`ResourceCreated`), then ABORTS with:

    Get-WindowsCapability: C:\zqm\bootstrap.ps1:41
    Line | 41 |  $cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like ' …'
         |         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
         | Class not registered

Under `$ErrorActionPreference="Stop"` the abort skips the rest of the script
(OpenSSH enable + the "Bootstrap complete" line).

## Cause
The node's Windows edition has NO OpenSSH capability provider registered in the
component store. Observed on **Node-2 = Windows 10 Pro**. This is an edition
boundary, not a script bug and not a credential/network problem.

## Is it fatal to failover?  NO.
The node already has **5985 + 5986** (the designed dual-WinRM redundancy for
that edition). Only SSH (22) is unavailable — which is the expected fallback on
Win10 Pro/Home. Contrast with pitfall #17 ("Cert: does not exist"), which DOES
block 5986 and must be fixed.

## Fix (in the canonical `zqm-bootstrap.ps1`, hardened 3761-byte copy)
Previously only `Add-WindowsCapability` was guarded. The bare
`Get-WindowsCapability -Online` call itself throws. Wrap the WHOLE OpenSSH block
in one try/catch:

```powershell
try {
  $cap = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -like 'OpenSSH.Server*' }
  if ($cap -and $cap.State -ne 'Installed') { try { Add-WindowsCapability -Online -Name $cap.Name | Out-Null } catch {} }
  $svc = Get-Service sshd -ErrorAction SilentlyContinue
  if ($svc) { Set-Service sshd -StartupType Automatic; Start-Service sshd; New-NetFirewallRule -DisplayName "ZQM-OpenSSH-22" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -Profile Any -RemoteAddress $Lan -ErrorAction SilentlyContinue | Out-Null; Write-Host "OpenSSH enabled" } else { Write-Host "OpenSSH unavailable (skipped)" }
} catch { Write-Host "OpenSSH capability provider unavailable (skipped)" }
```

Re-run then prints "OpenSSH capability provider unavailable (skipped)" and exits 0
with "Bootstrap complete on ZQM-NODE-2". The 5985+5986 failover is complete.

## Do NOT
- Treat "Class not registered" as a blocker or a symptom of a bad script.
- Switch the user to `-command` for the whole script to "fix" it (that reloads
  the scoop/starship profile and risks corruption — pitfall #10/#9).
- Assume SSH is unavailable fleet-wide: Node-3/4 DID enable OpenSSH. The
  capability provider is NODE-SPECIFIC.
