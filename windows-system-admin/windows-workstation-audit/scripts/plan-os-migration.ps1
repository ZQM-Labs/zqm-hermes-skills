<#
  plan-os-migration.ps1 - ELEVATED, READ-ONLY assessment for moving OS from SATA
  (C:) to NVMe (9100 PRO). Does NOT clone or change anything. Prints safe steps.
#>
$ProgressPreference='SilentlyContinue'
$elevated=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) { Write-Host "RUN AS ADMINISTRATOR" -ForegroundColor Red; exit 1 }
Write-Host "=== PRE-FLIGHT (read-only) ===" -ForegroundColor Cyan
$src=Get-Disk | Where-Object { (Get-Partition -DiskNumber $_.Number | Where-Object { $_.DriveLetter -eq 'C' }) }
$dst=Get-Disk | Where-Object { $_.FriendlyName -match '9100 PRO' }
Write-Host ("  SOURCE (C:): Disk $($src.Number) | $($src.BusType) | $([math]::Round($src.Size/1GB)) GB")
if ($dst) { Write-Host ("  DEST (9100 PRO): Disk $($dst.Number) | $($dst.BusType) | $([math]::Round($dst.Size/1GB)) GB") } else { Write-Host "  DEST (9100 PRO) NOT FOUND" }
Write-Host "`n=== RECOMMENDED PROCEDURE (do manually, not scripted) ===" -ForegroundColor Yellow
Write-Host "  1. BACKUP C: before any disk op."
Write-Host "  2. Free space on 9100 PRO (it holds F: data) - shrink/remove F: after moving data, or clone only ESP+MSR+C: to unallocated."
Write-Host "  3. Clone Disk0 (ESP+MSR+C:) -> 9100 PRO with a BOOTABLE tool: Macrium Reflect Free / Hasleo / AOMEI."
Write-Host "     (robocopy alone is NOT bootable - need a sector/UEFI clone.)"
Write-Host "  4. After clone: set 9100 PRO as boot disk in the tool, or disconnect SATA and boot once from NVMe."
Write-Host "  5. Verify BIOS boot order: Windows Boot Manager on the NVMe."
Write-Host "  6. Once confirmed booting from NVMe, repurpose old SATA disk as data."
Write-Host "`n  RISK: cloning a live boot disk can leave you unbootable if interrupted."
Write-Host "  Recommend: do this from a bootable USB clone tool, not inside Windows."
Write-Host "  This script intentionally does NOT perform the clone."
MIGRATION_PLAN_DONE
