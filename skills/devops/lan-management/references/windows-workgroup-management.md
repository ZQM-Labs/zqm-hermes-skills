# ZQM LAN — Windows workgroup investigation notes

Session: 2026-07-06
Nodes: 192.168.1.218 / 192.168.1.21
Workgroup: WORKGROUP

## Node-1/Node-2 evidence

- Broadcast protocols: mDNS 5353, LLMNR 5355, NetBIOS 137/138, WS-Discovery 3702, SSDP 1900, QWAVE 2177, Ethernet 51225.
- TCP surface: 135, 139, 445 on both nodes.
- QWAVE on both: PID 23064 / UDP 2177.
- Auth discriminator: `zqmcomputing` / shared password is accepted on Node-2 WMI/CIM/SMB; on Node-1 it is accepted at SMB layer but returns `0x80070005` for remote WMI/CIM until admin rights + Remote UAC filter + WinRM are fixed.

## Remote WMI failure pattern on Windows workgroup

Error: `0x80070005 E_ACCESSDENIED` from `Get-WmiObject` / `Get-CimInstance` with correct credentials.

Fix block (run on target via local console / RDP / local PS):
```powershell
net localgroup Administrators <account> /add
net localgroup "Remote Management Users" <account> /add
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord
Enable-PSRemoting -Force
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -Profile Any -Enabled True
Set-Item WSMan:\localhost\Service\AllowUnencrypted $true
Set-Item WSMan:\localhost\Service\Auth\Basic $true
```

Then on client:
```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<target-ip>" -Force
Set-Item WSMan:\localhost\Client\AllowUnencrypted $true
Test-WSMan -ComputerName <target-ip>
```

## SMB auth semantics

- `net view \\host` returning `Access is denied` (error 5) means authenticated but lacks share-list rights.
- `net use \\host\IPC$` returning `System error 67` means the admin share path is blocked or missing.
- These are NOT reliable indicators of a bad password.

## Node-2 full inventory

Hostname: `ZQM-NODE-2`
OS: Windows 11 Pro, build `26200`, 64-bit
Serial: `00342-55350-73144-AAOEM`, installed `2026-07-05`, last boot `2026-07-05 22:56`
Manufacturer/Model: LENOVO `82WS` Legion Pro 7 16ARX8H
UUID: `FF4C5CB1-62B6-47EC-B89A-FC5CEED02D9E`
BIOS: `LPCN65WW`, released `2026-03-25`
RAM: 64 GiB, CPU: 1 physical / 32 logical
User: `zqmco` (Alex Zelenski)
Wireless: `RZ616 Wi-Fi 6E`, IPv4 `192.168.1.21/24`, GW `192.168.1.1`
Hotfixes: KB5087051, KB5054156, KB5095189, KB5094126, KB5094135

## WinRM / PSRemoting status

Not configured on either node as of first enumeration. Client TrustedHosts empty on this host.

## Git HTTPS auth fix on Windows Git-Bash

If `git push` fails with `credential-manager-core` / `git-askpass` errors:
1. `gh auth setup-git`
2. Set explicit absolute helper path
3. Verify with `git ls-remote`
4. Test push.

Branch mismatch: use `git push origin HEAD:master`.
Prefer `git merge` over `git rebase` on Git-Bash/MSYS.