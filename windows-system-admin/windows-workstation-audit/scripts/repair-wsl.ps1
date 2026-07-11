<#
  repair-wsl.ps1 - ELEVATED, PROMPT-GATED WSL repair (REGDB_E_CLASSNOTREG).
  Diagnoses, then offers to re-register the MSI COM class. Nothing changes w/o Y.
#>
$ProgressPreference='SilentlyContinue'
$elevated=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) { Write-Host "RUN AS ADMINISTRATOR" -ForegroundColor Red; exit 1 }
Write-Host "=== WSL DIAGNOSIS ===" -ForegroundColor Cyan
wsl --status 2>&1 | ForEach-Object { "  $_" }
Write-Host "`nSTEP1: Re-register MSI COM class (fixes REGDB_E_CLASSNOTREG)." -ForegroundColor Yellow
Write-Host "  Runs: regsvr32 /s msi.dll"
$ans=Read-Host "  Run regsvr32 msi.dll now? [y/N]"
if ($ans -match '^[yY]') { regsvr32 /s msi.dll; Write-Host "  Done. Re-test: wsl --status  (and wsl -l -v)" } else { Write-Host "  SKIPPED" }
Write-Host "`nSTEP2 (if STEP1 insufficient): enable WSL feature + reinstall." -ForegroundColor Yellow
Write-Host "  dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart"
$ans=Read-Host "  Run DISM enable-feature now? [y/N]"
if ($ans -match '^[yY]') { dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>&1 | ForEach-Object { "  $_" }; Write-Host "  DISM done. Reboot may be required." } else { Write-Host "  SKIPPED" }
Write-Host "`nVerify: wsl -l -v   (should list distros without REGDB error)"
WSL_REPAIR_DONE
