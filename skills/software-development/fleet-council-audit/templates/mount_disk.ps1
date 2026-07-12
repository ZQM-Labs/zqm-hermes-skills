# Mount a disk partition as a drive letter.
# MUST be run ELEVATED (admin PowerShell). Assigning a drive letter requires admin CIM access;
# non-elevated throws "Access denied" / "CIM resource not available".
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File mount_disk.ps1
param(
    [int]   $DiskNumber = 1,
    [int]   $PartitionNumber = 3,
    [char]  $Letter = 'D'
)
$ErrorActionPreference = 'Stop'
try {
    $part = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber
    # DriveLetter is [char]; unmounted == '\0' (null char). Do NOT use IsNullOrEmpty (mis-fires).
    if ($part.DriveLetter -eq [char]0) {
        Set-Partition -InputObject $part -NewDriveLetter $Letter
        Start-Sleep -Seconds 1
        $vol = Get-Volume -DriveLetter $Letter
        Write-Host ("MOUNTED: $Letter`: $($vol.FileSystem) | $([math]::Round($vol.Size/1GB,1)) GB total | $([math]::Round($vol.SizeRemaining/1GB,1)) GB free")
    } else {
        Write-Host ("Already mounted as $($part.DriveLetter):")
    }
} catch {
    Write-Host ("FAILED: $($_.Exception.Message)")
    exit 1
}
