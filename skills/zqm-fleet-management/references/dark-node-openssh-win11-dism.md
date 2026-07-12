# Node-2 is WIN11 — OpenSSH MUST install (Dism PS module "Class not registered" fix)

## Correction (2026-07-10, this session)
The fleet skill previously asserted "Node-2 = Windows 10 Pro, OpenSSH capability
unavailable by edition, dual-WinRM 5985+5986 is the designed fallback." That is
WRONG. The user confirmed **Node-2 is Windows 11** — OpenSSH.Server is fully
installable there. The bootstrap OpenSSH abort was NOT an edition gap; it was the
**Dism PowerShell module's COM registration being broken** on that host:

    Get-WindowsCapability -Online  ->  "Class not registered" (REGDB_E_CLASSNOTREG)

This is a corrupt/absent Dism PS provider, not a missing capability. On a healthy
Win11 it works; on Node-2 it threw. The fix is to bypass the PS Dism module
entirely with the **native `dism.exe` binary**, which does NOT use that COM class.

## Local fix to run ON THE NODE (elevated)
Do NOT rely on `Add-WindowsCapability` / `Get-WindowsCapability` when the PS
provider is unhealthy — use `dism.exe`:

    cmd /c "dism /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 & sc config sshd start= auto & net start sshd & netsh advfirewall firewall add rule name=ZQM-OpenSSH-22 dir=in action=allow protocol=TCP localport=22 remoteip=192.168.1.0/24"

- `dism.exe /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0`
  installs the OpenSSH.Server capability (native binary, immune to the broken
  PS Dism COM registration).
- `sc config sshd start= auto` (NOTE the required space after `=`), `net start sshd`.
- Firewall rule scoped to the LAN only (192.168.1.0/24) — matches the 5985/5986 rules.

After this, Node-2 has the full 5985 + 5986 + 22 failover set (same as Node-3/4).

## Hardened bootstrap OpenSSH block (now in canonical zqm-bootstrap.ps1)
Order that survives a broken Dism PS module:

  1. Check for the `sshd` SERVICE first (no Dism dependency at all).
  2. Only if `sshd` is absent, try `Add-WindowsCapability` (PS Dism).
  3. On PS Dism failure, FALL BACK to native `dism.exe /online /Add-Capability`.
  4. Re-check `sshd`; if present, set auto-start + start + firewall; else skip.

```powershell
try {
  $svc = Get-Service sshd -ErrorAction SilentlyContinue
  if (-not $svc) {
    try {
      $cap = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -like 'OpenSSH.Server*' }
      if ($cap -and $cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null }
    } catch {
      Write-Host "Dism PS provider unavailable, trying native dism.exe"
      dism.exe /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 | Out-Null
    }
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
  }
  if ($svc) {
    Set-Service sshd -StartupType Automatic
    Start-Service sshd
    # ... firewall rule ...
    Write-Host "OpenSSH enabled"
  } else {
    Write-Host "OpenSSH unavailable (skipped)"
  }
} catch {
  Write-Host ("OpenSSH setup skipped: " + $_.Exception.Message)
}
```

## LESSON for the agent
- NEVER close a node bootstrap OpenSSH failure as "expected by-design edition gap"
  without VERIFYING the OS/build. The user knows his hardware; he corrected
  Node-2 = Win11. A "Class not registered" from Get/Add-WindowsCapability is a
  tooling/registration fault, not proof the capability is absent.
- When Dism PS cmdlets throw "Class not registered", reach for `dism.exe` — it is
  the same backend without the COM wrapper and almost always succeeds.
- "Can we do this locally?" -> yes. Hand the local `dism.exe` command above.

## Status after this session
All three nodes (2/3/4) bootstrapped with redundant WinRM (5985+5986); Node-3/4
have OpenSSH 22; Node-2's OpenSSH was pending the local `dism.exe` install above
(the 5985+5986 were already done). Full 3/3 failover once that runs.
