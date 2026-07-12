# read_defender_exclusions.ps1 — ELEVATED read of Windows Defender exclusion config.
# Non-elevated Get-MpPreference / registry returns EMPTY (not an error) - easy to misread as "no exclusions".
# Self-logs to disk so the result survives the UAC boundary. Run via Start-Process -Verb RunAs.
$log = "C:\Users\zqmco\swarm\2026-07-11_fleet_audit\defender_exclusions.log"
function out($s){ Add-Content -Path $log -Value $s }
out ("=== defender exclusions read " + (Get-Date))
try {
  $key = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions"
  if (Test-Path $key) {
    out "  Exclusions key exists."
    $paths = (Get-ItemProperty "$key\Paths" -ErrorAction SilentlyContinue)
    if ($paths) {
      $paths.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(P|Child|Drive|Provider)' } | ForEach-Object { out ("  PATH: " + $_.Name + " = " + $_.Value) }
    } else { out "  (no Paths subkey)" }
    $procs = (Get-ItemProperty "$key\Processes" -ErrorAction SilentlyContinue)
    if ($procs) {
      $procs.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(P|Child|Drive|Provider)' } | ForEach-Object { out ("  PROCESS: " + $_.Name + " = " + $_.Value) }
    } else { out "  (no Processes subkey)" }
    @("Extensions","Services","IpAddrs") | ForEach-Object {
      $sk = (Get-ItemProperty "$key\$_" -ErrorAction SilentlyContinue)
      if ($sk) { $sk.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(P|Child|Drive|Provider)' } | ForEach-Object { out ("  $_`: " + $_.Name + " = " + $_.Value) } }
    }
  } else { out "  Exclusions key NOT present (Defender may use different store / Controlled Folder Access)" }
  $dyn = Get-MpPreference -ErrorAction SilentlyContinue
  if ($dyn) {
    out ("  ExclusionPath: " + ($dyn.ExclusionPath -join ', '))
    out ("  ExclusionProcess: " + ($dyn.ExclusionProcess -join ', '))
    out ("  ExclusionExtension: " + ($dyn.ExclusionExtension -join ', '))
    out ("  ControlledFolderAccessEnabled: " + $dyn.EnableControlledFolderAccess)
  }
} catch { out ("  FAILED: " + $_.Exception.Message) }
out ("=== done " + (Get-Date))
