# Non-elevated Windows workstation probes (NO Admin needed)

Run from the bash/MSYS2 terminal via a .ps1 file (bash mangles inline PS,
esp. `$_.X`, `$null`, em-dashes):
  powershell -NoProfile -ExecutionPolicy Bypass -File C:/tmp/x.ps1

## Secure Boot (registry — non-elev)
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled
  -> UEFISecureBootEnabled = 1  (ON). (Confirm-SecureBootUEFI cmdlet itself needs Admin.)

## TPM 2.0 health/spec/PCR7 (tpmtool CLI — full output, no Admin)
tpmtool getdeviceinformation
  -> TPM Present: True, TPM Version: 2.0, PCR7 Binding State: Bound (BitLocker active),
     TPM Has Vulnerable Firmware: False. (Get-Tpm cmdlet needs Admin; tpmtool does not.)

## TPM proof via UNPRIVILEGED EVENT LOG (the blindspot fill-in — use when tpmtool/CIM are denied)
If `Get-Tpm` returns blank and `CIM Win32_Tpm` throws CimException "Access denied"
(non-admin), do NOT stop at "TPM blocked." The TPM-WMI provider writes attestation
events to the System log that are READABLE unelevated:
  Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-TPM-WMI';Id=1041} -MaxEvents 5
    -> Event 1041 = TPM attestation/health. If present with HealthStatus=Attestable,
       TPM is PRESENT, initialized, and ATTESTING (proves the same fact Get-Tpm would).
  Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-TPM-WMI';Id=519} -MaxEvents 5
    -> Event 519 = TPM CLEAR. If present, characterize it (see below) — a clear is a
       notable security event and must be explained, not ignored.
  # Characterize a 519 (all unprivileged):
  $e = Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-TPM-WMI';Id=519} -MaxEvents 1
  "$($e.TimeCreated) | UserId=$($e.UserId) | $($e.Message)"
    -> UserId S-1-5-18 (LOCAL SYSTEM) + Reason "SRK Pub not present or empty" at a
       build/reinstall timestamp = benign auto-reprovision (NOT an incident).
       A clear by an interactive user, or paired with BitLocker-suspended + odd
       reboots, would be suspicious -> escalate.
  RECORDED ON ZQM-NODE-4 2026-07-11: Get-Tpm blank, CIM Win32_Tpm DENIED
  [CimException Access denied]; Event 1041 x5 HealthStatus=Attestable (07/10-07/11)
  -> TPM CONFIRMED present & attestable via unprivileged event. Event 519 x1 at
  07/09 07:19 S-1-5-18 "SRK Pub not present" = benign build-time clear. Finding [4] CLOSED.

## Exception-typing probe wrapper (distinguish BLOCKED vs FAILED vs WRONG)
Wrap every privileged check so the catch records the EXACT exception TYPE, not
just a message — this is what lets you truthfully label a claim BLOCKED(non-admin)
vs genuinely failing. Pattern (from the attestation-toolkit blindspot_diag.ps1):
  function Probe($name,$sb){
    try { $r=& $sb; "[$name] OK: $(($r|Out-String).Trim() -split "`n"|Select -First 2)" }
    catch { "[$name] EXCEPTION: $($_.Exception.GetType().Name): $($_.Exception.Message.Trim())" }
  }
  Probe "Get-Tpm" { Get-Tpm }
  Probe "CIM Win32_Tpm" { Get-CimInstance -Namespace root\cimv2\Security\MicrosoftTpm -ClassName Win32_Tpm }
Use this in every verification harness so the 2nd-path matrix can cite the real
denial class (e.g. "Win32_Tpm: CimException Access denied" = genuinely admin-gated).

## VBS / HVCI status (registry — non-elev)
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled
  -> Enabled = 1  (VBS is virtualizing the virtualization extensions -> VT-x IS on)
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name EnableVirtualizationBasedSecurity

## VT-x disambiguation (when VirtualizationFirmwareEnabled = False)
Get-CimInstance Win32_ComputerSystem | Select HypervisorPresent   # True => hypervisor running
If VBS Enabled = 1 AND HypervisorPresent = True -> VT-x is actually ON (masked by VBS).
Do NOT send the user into BIOS. Only enable VT-x in BIOS if BOTH are False AND
VirtualizationFirmwareEnabled = False. (See vbs-vtx-false-negative.md.)

## OS disk proof (no bcdedit needed — non-elev)
Get-Disk | ForEach-Object { $dk=$_; Get-Partition -DiskNumber $dk.Number | ForEach-Object {
  if ($_.IsBoot -or $_.IsSystem) { "Disk$($dk.Number) [$($dk.BusType)] IsBoot=$($_.IsBoot) Drive=$((($_|Get-Volume|?{$_.DriveLetter})|%{$_.DriveLetter+':'}) -join ',')" } } }
  -> IsBoot=True on a SATA disk while a fast NVMe is data-only = OS on the slow disk.
     Definitive; do not infer from Disk numbers alone.

## Open ports + owning process (non-elev)
Get-NetTCPConnection -State Listen | Sort-Object LocalPort -Unique | ForEach-Object {
  "$($_.LocalAddress):$($_.LocalPort) [$( (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name )]" }

## GPU / pending updates (non-elev)
Get-CimInstance Win32_VideoController | Select Name,DriverVersion,AdapterRAM
(New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0").Updates.Count

## Empirical exposure check (bash curl — stronger than a port listing)
# localhost proves the service answers; the LAN-IP hit proves it is REACHABLE
# OFF-BOX (bound to 0.0.0.0/:: AND the firewall permits it, not loopback-only).
# Use BOTH. The LAN-IP hit is the decisive "is it actually exposed" proof — a
# localhost-only check can miss a firewall/loopback mismatch.
curl -s http://127.0.0.1:11434/api/tags            # Ollama: model list if unauthenticated
curl -s http://192.168.1.215:11434/api/tags        # OLLAMA LAN-IP HIT: returned 45 models on ZQM-NODE-4
                                                    #   => truly LAN-exposed, no auth (localhost alone is weaker)
curl -s -i http://127.0.0.1:5985/wsman            # WinRM: 'HTTP/1.1 405' => live & reachable
curl -s -i http://192.168.1.215:5985/wsman        # WinRM LAN-IP hit: same 405 => reachable from LAN
# Decode: a 2xx/4xx (non-connection-reset) from the LAN IP = listener bound to
# 0.0.0.0/:: and firewall permits it. Connection-refused/timeout = loopback-only or blocked.

## SSH service health (non-elev) — boot-crash flag
Get-EventLog -LogName System -Source "Service Control Manager" -EntryType Error -Message "*OpenSSH*" -Newest 10
  -> "The OpenSSH SSH Server service terminated unexpectedly" repeated at boot = sshd
     crashing on start (bad/regenerated host key or config), then recovering.
     On ZQM-NODE-4: 3x crashes 10:15-10:17 then Running. Flag it; check host keys.

## STILL admin-gated (blank / Access-Denied without elevation)
manage-bde -status
Get-PhysicalDisk | Get-StorageReliabilityCounter   # SMART wear% / POH / temp
bcdedit /enum
Confirm-SecureBootUEFI ; Get-Tpm
