<#
  fix-audit.ps1  -  run from an ELEVATED PowerShell (Run as Administrator)
  Safe, prompt-gated remediation helper for ZQM-NODE-4 findings:
    1. Back up ALL BitLocker recovery keys to a file (safe, read-only)
    2. Resume BitLocker protection on data drives F: and D: (Y/N per drive)
    3. XMP / OS migration: informational only (BIOS-level, cannot be done here)
    4. Optionally disable sshd / WinRM (Y/N each)
  NOTHING changes without an explicit Y answer at its prompt.
  Uses manage-bde.exe (always present) for maximum robustness.
#>
$ErrorActionPreference = 'SilentlyContinue'
$log = @()
function Log($s){ $log += $s; Write-Host $s }

Log "=================================================================="
Log ("ZQM-NODE-4  REMEDIATION HELPER  -  " + (Get-Date))
Log "=================================================================="

# Elevation check
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log ("Elevated session : " + $adm)
if (-not $adm) { Log "!! NOT running as Admin. Re-run from an elevated PowerShell. No changes made."; $log | Set-Content C:\tmp\fix-audit-report.txt -Encoding UTF8; return }

# 1) BACK UP ALL BITLOCKER RECOVERY KEYS (safe)
Log ""
Log "--- STEP 1: BACK UP BITLOCKER RECOVERY KEYS ---"
$keyDir = "C:\tmp\bitlocker-keys"
New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
$vols = manage-bde -status 2>$null
Log "Backing up recovery keys to $keyDir ..."
foreach ($d in @('C:','D:','F:','E:')) {
  $info = manage-bde -protectors -get $d -path "$keyDir\$($d[0])-recoverykey.txt" 2>&1
  if ($LASTEXITCODE -eq 0) { Log ("  $d : recovery key saved -> $keyDir\$($d[0])-recoverykey.txt") }
  else { Log ("  $d : no BitLocker protector / not applicable") }
}
Log "!! Store these key files somewhere safe (e.g. a USB stick or password manager)."
Log "!! They contain the keys that can unlock your encrypted drives."

# 2) RESUME BITLOCKER ON DATA DRIVES
Log ""
Log "--- STEP 2: RESUME BITLOCKER PROTECTION ON DATA DRIVES ---"
# Current protection status via manage-bde -status parse
function Get-BLStatus($drv){
  $s = manage-bde -status $drv 2>$null
  $line = ($s | Select-String -Pattern 'Protection Status').Line
  if ($line -match 'Protection On') { return 'On' }
  if ($line -match 'Protection Off') { return 'Off' }
  return 'N/A'
}
foreach ($drv in @('F:','D:')) {
  $st = Get-BLStatus $drv
  Log ("  $drv protection status: $st")
  if ($st -eq 'Off') {
    $ans = Read-Host ("  Resume BitLocker protection on $drv ? (Y/N)")
    if ($ans -match '^[Yy]') {
      manage-bde -protectors -enable $drv | Out-Null
      Start-Sleep -Seconds 2
      $new = Get-BLStatus $drv
      Log ("  $drv after action: $new")
    } else {
      Log ("  Skipped $drv (no change).")
    }
  }
}

# 3) XMP / OS MIGRATION - informational only
Log ""
Log "--- STEP 3: XMP / OS MIGRATION (BIOS-LEVEL, NOT AUTOMATED) ---"
Log "  RAM currently runs at 4800 MT/s; rated 5200 MT/s (XMP off)."
Log "  To enable: reboot -> Dell BIOS (F2) -> Performance -> Memory ->"
Log "  enable XMP Profile 1 -> save & exit. Then re-run admin-audit.ps1 to confirm 5200."
Log "  OS migration (C: 870 QVO -> F: 9100 PRO NVMe) requires imaging/cloning"
Log "  software (Macrium/Clonezilla) - cannot be done from this script."

# 4) OPTIONAL: disable sshd / WinRM
Log ""
Log "--- STEP 4: OPTIONAL REMOTE-ACCESS LOCKDOWN ---"
foreach ($svc in @('sshd','WinRM')) {
  try {
    $s = Get-Service -Name $svc -ErrorAction Stop
    Log ("  $svc : Status=$($s.Status), StartType=$($s.StartType)")
    if ($s.Status -eq 'Running' -or $s.StartType -ne 'Disabled') {
      $ans = Read-Host ("  Stop & disable $svc ? (Y/N)")
      if ($ans -match '^[Yy]') {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        $s2 = Get-Service -Name $svc -ErrorAction SilentlyContinue
        Log ("  $svc now: Status=$($s2.Status), StartType=$($s2.StartType)")
        Log ("  NOTE: if SSH/WinRM were how you reached this box, you may lose remote access.")
      } else { Log ("  Skipped $svc (no change).") }
    }
  } catch { Log ("  $svc : not installed / not found.") }
}

Log ""
Log "=================================================================="
Log "DONE. No actions were taken without your Y confirmation."
Log ("Recovery keys saved under: $keyDir")
Log "Full log: C:\tmp\fix-audit-report.txt"
Log "=================================================================="

$log | Set-Content C:\tmp\fix-audit-report.txt -Encoding UTF8
