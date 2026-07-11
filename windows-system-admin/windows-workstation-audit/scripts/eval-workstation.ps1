<#
  eval-workstation.ps1  -  run from an ELEVATED PowerShell (Run as Administrator)
  READ-ONLY full evaluation of ZQM-NODE-4 using only PowerShell/WMI/CIM + bcdedit.
  No install required (cctk optional). Makes NO changes.
  Covers: BIOS identity, boot config, Secure Boot, TPM, virtualization, RAM XMP gap,
  disks + SMART, BitLocker, power plan, network/remote services, Windows features, OS.
  Output printed AND saved to C:\tmp\eval-workstation.txt
#>
$ErrorActionPreference = 'SilentlyContinue'
$out = @()
function Log($s){ $out += $s; Write-Host $s }

Log "=================================================================="
Log ("WORKSTATION EVALUATION (WMI/CIM)  -  " + (Get-Date))
Log "=================================================================="

# Elevation check
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log ("Elevated session : " + $adm)
if (-not $adm) {
    Log "!! NOT running as Admin. Re-run from an elevated PowerShell. Partial data only."
}

# --- BIOS / SYSTEM IDENTITY ---
Log ""
Log "--- BIOS / SYSTEM IDENTITY ---"
$bios = Get-CimInstance Win32_Bios
$cs   = Get-CimInstance Win32_ComputerSystem
Log ("Manufacturer : " + $cs.Manufacturer)
Log ("Model        : " + $cs.Model)
Log ("Serial/Tag   : " + $bios.SerialNumber)
Log ("BIOS Version : " + $bios.Version)
Log ("BIOS Name    : " + $bios.Name)
Log ("BIOS Release : " + $bios.ReleaseDate)
Log ("Hypervisor   : " + $cs.HypervisorPresent)
Log ("Total RAM    : " + [math]::Round($cs.TotalPhysicalMemory/1GB) + " GB")

# --- BOOT CONFIG (firmware entries + boot order) ---
Log ""
Log "--- BOOT CONFIGURATION (bcdedit /enum firmware) ---"
$fw = bcdedit /enum firmware 2>&1
$fw | ForEach-Object { Log $_ }
$bootmgr = bcdedit /enum '{bootmgr}' 2>&1
Log "--- BOOTMGR (boot order) ---"
$bootmgr | ForEach-Object { Log $_ }

# --- SECURE BOOT / TPM ---
Log ""
Log "--- SECURE BOOT / TPM ---"
try { Log ("SecureBootUEFI : " + (Confirm-SecureBootUEFI)) } catch { Log "SecureBootUEFI : denied (run elevated)" }
try {
    $sbp = Get-SecureBootPolicy -ErrorAction Stop
    Log ("SecureBootPolicy: PolicyPublisherId=$($sbp.PolicyPublisherId)")
} catch { Log "SecureBootPolicy : N/A" }
try {
    $t = Get-Tpm
    Log ("TPM : Present=$($t.TpmPresent) Ready=$($t.TpmReady) Enabled=$($t.TpmEnabled) Activated=$($t.TpmActivated) Spec=$($t.SpecVersion) Mfr=$($t.ManufacturerIdTxt)")
} catch { Log "TPM : denied (run elevated)" }

# --- VIRTUALIZATION (firmware assist) ---
Log ""
Log "--- VIRTUALIZATION / FIRMWARE FEATURES ---"
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Log ("VirtualizationFirmwareEnabled : " + $cpu.VirtualizationFirmwareEnabled)
Log ("SecondLevelAddressTranslation : " + $cpu.SecondLevelAddressTranslationExtensions)
Log ("VMMonitorModeExtensions       : " + $cpu.VMMonitorModeExtensions)
# VBS/HVCI truth-check: if the flag above reads False, it may be a FALSE NEGATIVE
# (VBS loads a hypervisor at boot and consumes the VMX bit). Confirm via DeviceGuard.
$vbsRunning = $false
try {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
    $vbsRunning = ($dg.SecurityServicesRunning -contains 2) -or ($dg.SecurityServicesConfigured -contains 2)
    Log ("DeviceGuard: Configured=$($dg.SecurityServicesConfigured -join ',') Running=$($dg.SecurityServicesRunning -join ',')")
} catch { Log "DeviceGuard: N/A" }
if ($cpu.VirtualizationFirmwareEnabled -eq $false -and $vbsRunning) {
    Log "  -> VirtualizationFirmwareEnabled=False is a FALSE NEGATIVE: VBS/HVCI is running, which requires VT-x+SLAT ON in firmware. VT-x is actually ENABLED."
} elseif ($cpu.VirtualizationFirmwareEnabled -eq $false) {
    Log "  -> VT-x appears OFF. Enable Intel VT-x (+VT-d) in BIOS (F2 -> Performance/Virtualization -> F10)."
} else {
    Log "  -> VT-x ENABLED in firmware."
}

# --- RAM (XMP gap) ---
Log ""
Log "--- RAM / XMP (DOCP) GAP ---"
Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    Log ("  Mfr=$(if($_.Manufacturer){$_.Manufacturer}else{'?'}), $([math]::Round($_.Capacity/1GB))GB, Configured=$($_.ConfiguredClockSpeed)MT/s Rated(SPD)=$($_.Speed)MT/s, Part=$($_.PartNumber)")
}
$mods = Get-CimInstance Win32_PhysicalMemory
$cfg = ($mods | ForEach-Object { $_.ConfiguredClockSpeed } | Sort-Object -Unique) -join ','
# SPD Speed field reflects the DIMM's BASE jedec profile, NOT its XMP rating.
# The real rated speed comes from the part number (e.g. F5-5200 -> 5200 MT/s).
$partRated = $null
foreach ($m in $mods) {
    if ($m.PartNumber -match '(\d{4})') { $cand = [int]$Matches[1]; if ($cand -ge 4000) { $partRated = $cand } }
}
if (-not $partRated) { $partRated = ($mods | ForEach-Object { $_.Speed } | Sort-Object -Unique) -join ',' }
Log ("  Configured=$cfg MT/s  Rated(part-no)=$partRated MT/s")
if (($cfg -split ',')[0] -lt [string]$partRated) {
    Log ("  -> XMP/DOCP OFF: running $cfg vs rated $partRated MT/s. Enable XMP Profile 1 in BIOS (~8% bandwidth).")
} elseif ($cfg -eq [string]$partRated) {
    Log ("  -> XMP/DOCP APPEARS ENABLED (at or above part-rated $partRated MT/s).")
} else {
    Log ("  -> Configured ABOVE part-rated ($partRated) - XMP likely enabled.")
}

# --- DISKS + SMART ---
Log ""
Log "--- DISKS / SMART ---"
Get-PhysicalDisk | ForEach-Object {
    $d = $_
    $line = "  $($d.DeviceID) $($d.MediaType)/$($d.BusType) $([math]::Round($d.Size/1GB))GB Health=$($d.HealthStatus)"
    try {
        $r = $d | Get-StorageReliabilityCounter -ErrorAction Stop
        $line += " T=$($r.Temperature)C Wear=$($r.Wear)% POH=$($r.PowerOnHours) ReadErr=$($r.ReadErrorsTotal)"
    } catch { $line += " (reliability counters N/A via this interface)" }
    Log $line
}
Log "--- VOLUMES ---"
Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { Log ("  $($_.DriveLetter): $($_.FileSystem) $([math]::Round($_.Size/1GB))GB free=$([math]::Round($_.SizeRemaining/1GB))GB") }

# --- BITLOCKER ---
Log ""
Log "--- BITLOCKER ---"
try {
    Get-BitLockerVolume | ForEach-Object { Log ("  $($_.MountPoint) Protection=$($_.ProtectionStatus) Enc=$($_.VolumeStatus) Method=$($_.EncryptionMethod)") }
} catch {
    manage-bde -status 2>&1 | ForEach-Object { Log $_ }
}

# --- POWER ---
Log ""
Log "--- POWER PLAN ---"
$p = Get-CimInstance Win32_PowerPlan -Namespace root\cimv2\power -Filter "IsActive='true'" -ErrorAction SilentlyContinue
if ($p) { Log ("  Active: " + $p.ElementName + "  (" + $p.InstanceID + ")") }
Log "  Processor throttle (AC):"
powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>&1 | Select-String -Pattern "Power Setting Index" | ForEach-Object { Log ("    " + $_.Line.Trim()) }

# --- NETWORK / REMOTE SERVICES ---
Log ""
Log "--- NETWORK / REMOTE SERVICES ---"
Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { Log ("  NIC: $($_.Name) [$($_ | Get-NetAdapter -IncludeHidden:$false | Select -ExpandProperty LinkSpeed)] Status=$($_.Status)") }
foreach ($svc in @('sshd','WinRM')) {
    try {
        $s = Get-Service -Name $svc -ErrorAction Stop
        Log ("  $svc : Status=$($s.Status) StartType=$($s.StartType)")
    } catch { Log ("  $svc : not installed") }
}

# --- WINDOWS FEATURES (selected) ---
# NOTE: Get-WindowsOptionalFeature can silently return $null (DISM servicing quirk);
# a bare `catch {}` would then drop the whole section. Surface errors instead of swallowing.
Log ""
Log "--- WINDOWS FEATURES (selected) ---"
foreach ($f in @('Microsoft-Hyper-V-All','VirtualMachinePlatform','HypervisorPlatform','Containers-DisposableClientVM','Microsoft-Windows-Subsystem-Linux','TelnetClient','TFTP')) {
    try {
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop
        if ($feat -and $feat.State) { Log ("  $f : " + $feat.State) }
        else { Log ("  $f : N/A (no state returned)") }
    } catch {
        Log ("  $f : ERROR " + $_.Exception.Message)
    }
}

# --- OS ---
Log ""
Log "--- OS ---"
$os = Get-CimInstance Win32_OperatingSystem
Log ("  Caption   : " + $os.Caption)
Log ("  Version   : " + $os.Version + "  Build " + $os.BuildNumber)
Log ("  Install   : " + $os.InstallDate)
Log ("  LastBoot  : " + $os.LastBootUpTime)
Log ("  Free RAM  : " + [math]::Round($os.FreePhysicalMemory/1MB) + " GB / " + [math]::Round($os.TotalVisibleMemorySize/1MB) + " GB")

Log ""
Log "Full report saved to C:\tmp\eval-workstation.txt"
$out | Set-Content C:\tmp\eval-workstation.txt -Encoding UTF8
