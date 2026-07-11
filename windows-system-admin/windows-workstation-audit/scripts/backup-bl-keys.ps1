<#
  backup-bl-keys.ps1  -  ELEVATED PowerShell
  Ensures each encrypted volume HAS a recovery-password protector, then
  backs the 48-digit key to C:\tmp\bitlocker-keys\<drive>.txt and screen.
  Nothing is generated without an explicit Y at the prompt.
#>
$ErrorActionPreference = 'SilentlyContinue'
$out = @()
function Log($s){ $out += $s; Write-Host $s }

Log "=================================================================="
Log ("BITLOCKER RECOVERY KEY BACKUP  -  " + (Get-Date))
Log "=================================================================="

$keyDir = "C:\tmp\bitlocker-keys"
New-Item -ItemType Directory -Force -Path $keyDir | Out-Null

$mgmt = Get-CimInstance -Namespace root\cimv2\Security\MicrosoftVolumeEncryption -ClassName Win32_EncryptableVolume
foreach ($v in $mgmt) {
  $drv = if ($v.DriveLetter) { $v.DriveLetter } else { $v.DeviceID }
  Log ("--- Volume $drv ---")

  # Does a recovery-password protector (type 3) already exist?
  $haveKey = $false
  try {
    $ids = $v.GetKeyProtectors(3).VolumeKeyProtectorID
    if ($ids) {
      foreach ($id in $ids) {
        $pw = $v.GetKeyProtectorNumericalPassword($id).NumericalPassword
        if ($pw) { $haveKey = $true; Log ("  Existing recovery key: $pw"); Add-Content -Path "$keyDir\$(([string]$drv)[0])-recoverykey.txt" -Value ("RECOVERY KEY for $drv : $pw") -Encoding UTF8 }
      }
    }
  } catch {}

  if (-not $haveKey) {
    Log ("  No recovery-password protector on $drv.")
    $ans = Read-Host ("  Generate a recovery password for $drv now? (Y/N)")
    if ($ans -match '^[Yy]') {
      # Add a recovery password protector
      $res = $v.ProtectKeyWithNumericalPassword($null)
      Start-Sleep -Seconds 1
      # Re-enumerate to capture it
      $ids2 = $v.GetKeyProtectors(3).VolumeKeyProtectorID
      $got = $false
      if ($ids2) {
        foreach ($id in $ids2) {
          $pw = $v.GetKeyProtectorNumericalPassword($id).NumericalPassword
          if ($pw) { $got = $true; Log ("  NEW recovery key: $pw"); Add-Content -Path "$keyDir\$(([string]$drv)[0])-recoverykey.txt" -Value ("RECOVERY KEY for $drv : $pw") -Encoding UTF8 }
        }
      }
      if (-not $got) { Log ("  !! Could not read back the new key. Run: manage-bde -protectors -get $drv -type recoverypassword") }
    } else {
      Log ("  Skipped $drv - NO recovery key backed up. Risk remains.")
    }
  }
}

Log ""
Log "Key files written to $keyDir"
Log "STORE THESE SOMEWHERE SAFE (password manager / USB off this machine)."
$out | Set-Content C:\tmp\bitlocker-keys\backup-summary.txt -Encoding UTF8
