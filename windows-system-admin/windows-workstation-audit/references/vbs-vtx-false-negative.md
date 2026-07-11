# VT-x / VirtualizationFirmwareEnabled False Negative (Windows 11 24H2 + VBS/HVCI)

## Symptom
`Get-CimInstance Win32_Processor | Select VirtualizationFirmwareEnabled` returns
`False` on a box that is clearly virtualizing (Hyper-V/WSL2/Docker work, or VBS is
running). This misleads the agent into advising "reboot to F2 and enable VT-x" —
which is wrong and unnecessary.

## Root cause
Windows 11 24H2 enables VBS (Virtualization-based Security) + HVCI (Memory
Integrity / Core Isolation) by DEFAULT on fresh installs. VBS loads a hypervisor at
boot and consumes the VMX hardware bit, so the OS-level WMI flag reports `False`
even though VT-x is ON in firmware. The flag reflects "is the VMX bit available to
the OS right now," NOT "is VT-x enabled in BIOS."

## Proof VT-x is actually ON (run from elevated PowerShell)
```powershell
# 1) VBS running?  SecurityServicesRunning contains 2  => VBS running.
#    VBS CANNOT run without VT-x + SLAT. This alone proves VT-x is on.
(Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard `
    -ClassName Win32_DeviceGuard).SecurityServicesRunning

# 2) Memory Integrity (HVCI) on?  Enabled = 1 also requires VT-x.
(Get-ItemProperty `
    'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' `
    -Name Enabled).Enabled

# 3) systeminfo: "A hypervisor has been detected." confirms a hypervisor is loaded.
systeminfo | findstr /i "hypervisor"
```
Any one of these proves VT-x is on. Do NOT hand the user a BIOS-enable step.

## How eval-workstation.ps1 now guards against this
The virtualization block stores `VirtualizationFirmwareEnabled` and queries
`Win32_DeviceGuard`. If the flag is False BUT `SecurityServicesRunning` contains 2,
it auto-prints: "VirtualizationFirmwareEnabled=False is a FALSE NEGATIVE: VBS/HVCI
is running, which requires VT-x+SLAT ON in firmware. VT-x is actually ENABLED."

## Seen on
ZQM-NODE-4 (Dell XPS 8960, fresh Win11 24H2 build 26200, installed 2026-07-09):
`VirtualizationFirmwareEnabled=False` but `SecurityServicesRunning=2`, HVCI
`Enabled=1`. The naive eval would have told the user to enable VT-x in BIOS — wrong.
Corrected via this reference + eval truth-check + SKILL.md pitfall #9.
