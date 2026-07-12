# zqm-cred-cleanup.ps1
# Securely remove stored credential files when no longer needed.
param([string]$Name = "all")
$files = if ($Name -eq "all") {
    Get-ChildItem (Join-Path $env:USERPROFILE "zqm-cred-*.xml") -ErrorAction SilentlyContinue
} else {
    $p = Join-Path $env:USERPROFILE ("zqm-cred-{0}.xml" -f $Name)
    if (Test-Path $p) { Get-Item $p } else { @() }
}
foreach ($f in $files) {
    Remove-Item $f.FullName -Force
    Write-Host ("Removed: " + $f.FullName)
}
if (-not $files) { Write-Host "No credential files found to remove." }
