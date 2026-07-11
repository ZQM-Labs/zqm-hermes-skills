<#
  enable-xmp.ps1  -  run from an ELEVATED PowerShell (Run as Administrator)
  Sets memory XMP/DOCP Profile 1 on a Dell machine using Dell Command | Configure (cctk),
  then (with your explicit Y) reboots ONCE to apply it.
  No change is made without a Y answer. A reboot is REQUIRED for XMP to take effect -
  there is no live/software-only way to change DRAM frequency; the memory controller
  retrains at POST.
#>
$ErrorActionPreference = 'SilentlyContinue'
$log = @()
function Log($s){ $log += $s; Write-Host $s }

function Find-Cctk {
    $known = @(
        'C:\Program Files (x86)\Dell\Command Configure\X86_64\cctk.exe',
        'C:\Program Files\Dell\Command Configure\X86_64\cctk.exe'
    )
    foreach ($p in $known) { if (Test-Path $p) { return $p } }
    $f = Get-ChildItem -Path 'C:\Program Files','C:\Program Files (x86)' -Recurse -Filter cctk.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

Log "=================================================================="
Log ("ENABLE XMP / DOCP  -  " + (Get-Date))
Log "=================================================================="

# Elevation check
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log ("Elevated session : " + $adm)
if (-not $adm) {
    Log "!! NOT running as Admin. Re-run from an elevated PowerShell. Nothing changed."
    $log | Set-Content C:\tmp\enable-xmp-report.txt -Encoding UTF8
    return
}

# Locate cctk (known paths, then recursive ProgramFiles search)
$cctk = Find-Cctk
if (-not $cctk) {
    Log "cctk (Dell Command | Configure) not found."
    $ans = Read-Host "Install Dell Command | Configure via scoop? (Y/N)"
    if ($ans -match '^[Yy]') {
        Log "Installing via scoop ..."
        scoop install dell-command-configure 2>&1 | ForEach-Object { Log $_ }
        $cctk = Find-Cctk
    }
}
if (-not $cctk) {
    Log "Could not locate cctk automatically. If you just installed it manually, re-run this"
    Log "script and it will auto-detect the install. Otherwise set XMP in BIOS:"
    Log "  reboot -> F2 -> Performance -> Memory -> XMP Profile 1 -> F10"
    Log "Dell download: https://www.dell.com/support/home/en-us/drivers/DriversDetails?driverId=YYDC5"
    $log | Set-Content C:\tmp\enable-xmp-report.txt -Encoding UTF8
    return
}
Log ("cctk : " + $cctk)

# Show current memory-related settings so we know the exact attribute name
Log ""
Log "--- Current memory / profile settings on this BIOS ---"
& $cctk --getconfig 2>&1 | Where-Object { $_ -match 'XMP|Memory|Profile|Overclock' } | ForEach-Object { Log $_ }

# Identify the attribute name (Dell varies it across BIOS revisions)
$attr = $null
$probe = & $cctk --getconfig 2>&1
foreach ($line in $probe) {
    if ($line -match 'PerformanceMemoryProfile|XMPMode|XMP|MemoryProfile|Overclock') {
        $name = ($line -split '=')[0].Trim()
        if ($name -match '\S') { $attr = $name; break }
    }
}
if (-not $attr) { $attr = 'PerformanceMemoryProfile' }
Log ("Target attribute : " + $attr)

# Ask before changing
Log ""
$ans = Read-Host ("Set $attr to XMP Profile 1 (XMP/DOCP on)? (Y/N)")
if ($ans -notmatch '^[Yy]') {
    Log "Skipped. No change made."
    $log | Set-Content C:\tmp\enable-xmp-report.txt -Encoding UTF8
    return
}

# Try the most common value spellings; XMP Profile 1 is usually "XMP 1"
$set = $false
foreach ($v in @('XMP 1','XMP1','1')) {
    $r = & $cctk ("--" + $attr + "=" + $v) 2>&1
    if ($LASTEXITCODE -eq 0) { Log ("Set $attr = $v  (exit 0)"); $set = $true; break }
    else { Log ("Attempt '$v' failed: " + ($r -join ' ')) }
}
if (-not $set) {
    Log "!! Could not set the profile automatically. Set it manually in BIOS (F2 -> Performance -> Memory -> XMP Profile 1)."
    $log | Set-Content C:\tmp\enable-xmp-report.txt -Encoding UTF8
    return
}

Log ""
Log "XMP Profile 1 configured. A REBOOT is required for it to take effect."
$ans = Read-Host "Reboot now to apply? (Y/N)"
if ($ans -match '^[Yy]') {
    Log "Rebooting ..."
    & shutdown /r /t 5 /c "Applying XMP Profile 1"
} else {
    Log "No reboot. Reboot later (Start -> Restart) to apply XMP."
}

Log ""
Log "Full log: C:\tmp\enable-xmp-report.txt"
$log | Set-Content C:\tmp\enable-xmp-report.txt -Encoding UTF8
