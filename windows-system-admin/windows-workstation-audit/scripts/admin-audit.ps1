<#
  admin-audit.ps1  -  run from an ELEVATED PowerShell (Run as Administrator)
  Captures the items that were "Access denied" in the standard session:
    - Secure Boot state
    - TPM presence/readiness
    - NVMe/SSD SMART wear, temperature, power-on hours
    - BitLocker status (bonus)
    - Memory XMP/DOCP state (current vs rated speed)
  Output is printed AND saved to C:\tmp\admin-audit-report.txt
#>
$ErrorActionPreference = 'SilentlyContinue'
$out = @()
function Log($s){ $out += $s; Write-Host $s }

Log "=================================================================="
Log ("ZQM-NODE-4  ADMIN-PRIVILEGE AUDIT  -  " + (Get-Date))
Log "=================================================================="

# Elevation check
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log ("Elevated session : " + $adm)
if (-not $adm) { Log "!! NOT running as Admin - re-run from an elevated PowerShell."; $out | Set-Content C:\tmp\admin-audit-report.txt -Encoding UTF8; return }

# --- SECURE BOOT ---
Log ""
Log "--- SECURE BOOT ---"
try {
  $sb = Confirm-SecureBootUEFI
  Log ("SecureBoot enabled : " + $sb)
} catch {
  Log ("Confirm-SecureBootUEFI failed: " + $_)
}
$bm = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction SilentlyContinue).UEFISecureBootEnabled
Log ("UEFI SecureBoot reg: " + $bm)

# --- TPM ---
Log ""
Log "--- TPM ---"
try {
  $t = Get-Tpm
  Log ("TPM Present   : " + $t.TpmPresent)
  Log ("TPM Ready     : " + $t.TpmReady)
  Log ("TPM Enabled   : " + $t.TpmEnabled)
  Log ("TPM Activated : " + $t.TpmActivated)
  Log ("Spec Version  : " + $t.SpecVersion)
  Log ("Manufacturer  : " + $t.ManufacturerIdTxt)
} catch { Log ("Get-Tpm failed: " + $_) }

# --- BITLOCKER (bonus) ---
Log ""
Log "--- BITLOCKER ---"
try {
  Get-BitLockerVolume | ForEach-Object {
    Log ("{0}  Protection={1}  Encryption={2}  Method={3}" -f $_.MountPoint, $_.ProtectionStatus, $_.VolumeStatus, $_.EncryptionMethod)
  }
} catch { Log ("BitLocker module unavailable: " + $_) }

# --- MEMORY / XMP (DOCP) STATE ---
Log ""
Log "--- MEMORY / XMP (DOCP) STATE ---"
try {
  $mods = Get-CimInstance Win32_PhysicalMemory
  Log ("Module count       : " + $mods.Count)
  foreach ($m in $mods) {
    Log ("  Mfr={0} Part={1} Size={2}GB Configured={3}MT/s Rated(SPD)={4}MT/s" -f
      $m.Manufacturer, $m.PartNumber, [math]::Round($m.Capacity/1GB,0), $m.ConfiguredClockSpeed, $m.Speed)
  }
  $cfg   = ($mods | ForEach-Object { $_.ConfiguredClockSpeed } | Sort-Object -Unique) -join ','
  $rated = ($mods | ForEach-Object { $_.Speed } | Sort-Object -Unique) -join ','
  Log ("Configured speed   : " + $cfg + " MT/s")
  Log ("SPD rated speed    : " + $rated + " MT/s")
  $pn  = ($mods | Select-Object -First 1).PartNumber
  if ($pn -match '(\d{4})') {
    $pnr = [int]$Matches[1]
    Log ("Part-number rated : " + $pnr + " MT/s (" + $pn + ")")
    if ([int]($cfg -split ',')[0] -lt $pnr) {
      Log "  >> XMP/DOCP is OFF - running below rated. Enable XMP Profile 1 in BIOS to reach " + $pnr + " MT/s."
    } else {
      Log "  >> XMP/DOCP appears ENABLED (at or above part-rated speed)."
    }
  }
} catch { Log ("Memory query failed: " + $_) }

# --- SMART / STORAGE RELIABILITY ---
Log ""
Log "--- STORAGE RELIABILITY (SMART wear / temp / power-on) ---"
try {
  $disks = Get-PhysicalDisk
  foreach ($d in $disks) {
    Log ("Drive: {0}  [{1} / {2}]  {3}GB" -f $d.DeviceID, $d.BusType, $d.MediaType, [math]::Round($d.Size/1GB,0))
    try {
      $r = $d | Get-StorageReliabilityCounter -ErrorAction Stop
      Log ("   Temperature     : " + $r.Temperature + " C")
      Log ("   Wear (life used): " + $r.Wear + " %")
      Log ("   PowerOnHours    : " + $r.PowerOnHours)
      Log ("   ReadErrorsTotal : " + $r.ReadErrorsTotal)
      Log ("   WriteErrorsTotal: " + $r.WriteErrorsTotal)
      Log ("   TempMax         : " + $r.TemperatureMax + " C")
    } catch {
      Log ("   (reliability counters unavailable: " + $_.Exception.Message + ")")
    }
  }
} catch { Log ("Get-PhysicalDisk failed: " + $_) }

# --- SUMMARY ---
Log ""
Log "=================================================================="
Log "END. Report also saved to C:\tmp\admin-audit-report.txt"
Log "=================================================================="

$out | Set-Content C:\tmp\admin-audit-report.txt -Encoding UTF8
