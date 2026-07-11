<#
  TEMPLATE: prompt-gated, elevated, read-mostly admin script.
  Copy this for any Windows audit/remediation script you hand the user.
  Rules baked in:
    - Elevation self-check; exits clean if not Admin.
    - Read-only by default; every mutation is behind a Y/N Read-Host.
    - Writes a transcript to C:\tmp\<name>-report.txt.
    - ASCII only (no em-dashes) to survive transit.
#>
$ErrorActionPreference = 'SilentlyContinue'
$log = @()
function Log($s){ $log += $s; Write-Host $s }

Log "=================================================================="
Log ("<TITLE>  -  " + (Get-Date))
Log "=================================================================="

# 1) Elevation check
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log ("Elevated session : " + $adm)
if (-not $adm) {
    Log "!! NOT running as Admin. Re-run from an elevated PowerShell. No changes made."
    $log | Set-Content C:\tmp\<name>-report.txt -Encoding UTF8
    return
}

# 2) Read-only discovery (example)
Log ""
Log "--- Current state ---"
$val = (Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1).ConfiguredClockSpeed
Log ("  ConfiguredClockSpeed : " + $val)

# 3) Mutation, gated behind Y/N
Log ""
$ans = Read-Host "Apply change? (Y/N)"
if ($ans -notmatch '^[Yy]') {
    Log "Skipped. No change made."
    $log | Set-Content C:\tmp\<name>-report.txt -Encoding UTF8
    return
}

# <do the mutation here>

Log ""
Log "Full log: C:\tmp\<name>-report.txt"
$log | Set-Content C:\tmp\<name>-report.txt -Encoding UTF8
