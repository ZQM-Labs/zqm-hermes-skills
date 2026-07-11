<#
  boot-forensics.ps1 - ELEVATED, READ-ONLY boot-chain inspection.
  Proves which disk Windows boots from (SATA vs NVMe) and inventories ESP .efi.
#>
$ProgressPreference = 'SilentlyContinue'
Write-Host "=== DISK TOPOLOGY (bus type) ==="
Get-Disk | ForEach-Object {
    $d=$_; $parts=Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
    $parts | ForEach-Object {
        $lt = if ($_.DriveLetter) { $_.DriveLetter } else { '-' }
        Write-Host ("  Disk$($d.Number) [$($d.BusType)] part$($_.PartitionNumber) $([math]::Round($_.Size/1GB))GB type=$($_.GptType) letter=$lt IsBoot=$($d.IsBoot)")
    }
}
Write-Host "`n=== VOLUMES -> disk ==="
Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
    $part=Get-Partition -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue
    if ($part) { $disk=Get-Disk -Number $part.DiskNumber; Write-Host ("  $($_.DriveLetter): $($_.FileSystem) on Disk$($part.DiskNumber) ($($disk.BusType))") }
}
Write-Host "`n=== BCD BOOT DEVICE (definitive) ==="
bcdedit /enum '{current}' 2>&1 | Select-String -Pattern 'device|osdevice|path|description'
Write-Host "`n=== ESP .efi INVENTORY ==="
# Find the ESP by GPT type (do not assume Disk0/part1  and NEVER hardcode X:,
# because the ESP is often ALREADY mounted at X: on 24H2 boxes, which makes
# Set-Partition -NewDriveLetter X fail). Reuse the existing letter if present.
$esp = Get-Partition | Where-Object {
    $_.GptType -eq 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b' -or $_.Type -eq 'System'
} | Select-Object -First 1
if (-not $esp) { $esp = Get-Partition -DiskNumber 0 -PartitionNumber 1 -ErrorAction SilentlyContinue }
$drive = $null
if ($esp) {
    if ($esp.DriveLetter) {
        $drive = $esp.DriveLetter + ':'
        Write-Host "  ESP already mounted at $drive"
    } else {
        foreach ($c in @('Y:','Z:','W:')) {
            if (-not (Test-Path $c)) {
                try { $esp | Set-Partition -NewDriveLetter $c[0] -ErrorAction Stop; $drive = $c; Start-Sleep 1; break }
                catch { Write-Host ("  assign $c failed: " + $_.Exception.Message) }
            }
        }
    }
    if ($drive) {
        Get-ChildItem -Path ($drive + '\') -Recurse -Include '*.efi','BCD' -ErrorAction SilentlyContinue | Sort-Object Length -Descending | ForEach-Object { Write-Host ("  $($_.FullName) ($($_.Length) B)") }
        if (-not $esp.DriveLetter) { $esp | Set-Partition -RemoveDriveLetter -ErrorAction SilentlyContinue }
    } else { Write-Host "  could not obtain an ESP drive letter" }
} else { Write-Host "  no ESP partition found" }
Write-Host "`n=== VIRT / XMP RESULT (from CIM, not NVRAM) ==="
Write-Host ("  VT-x enabled (raw WMI): $((Get-CimInstance Win32_Processor|Select -First 1).VirtualizationFirmwareEnabled)")
$m=(Get-CimInstance Win32_PhysicalMemory|Select -First 1); Write-Host ("  RAM configured=$($m.ConfiguredClockSpeed) rated-in-partno=$($m.PartNumber)")
BOOT_FORENSICS_DONE
