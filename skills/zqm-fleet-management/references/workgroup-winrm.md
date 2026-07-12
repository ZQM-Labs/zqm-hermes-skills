# Workgroup PowerShell Remoting (Windows Nodes 2/3/4)

## Server side (run ON the target node, Admin PowerShell)
```powershell
Enable-PSRemoting -Force                       # WinRM listeners + firewall
Set-NetConnectionProfile -NetworkCategory Private
# LOCAL account only — WinRM NTLM rejects Microsoft/email logons
net user zqmlocal "S0meStr0ngP@ss!" /add
net localgroup Administrators zqmlocal /add
net localgroup "Remote Management Users" zqmlocal /add
# optional: open indexer port to LAN subnet, Private profile only
New-NetFirewallRule -DisplayName "ZQM-Indexer-In-5000" -Direction Inbound -Protocol TCP -LocalPort 5000 -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue
```

## Client side (Node-1, to connect)
1. Start WinRM on Node-1: `winrm quickconfig -q` (also sets LocalAccountTokenFilterPolicy).
2. Add target to TrustedHosts (workgroup = no Kerberos, needs this):
   `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21" -Force`
   (run from ELEVATED PowerShell — non-elevated can't write WSMan:\localhost\Client).
3. Connect with a LOCAL account (not email):
```powershell
$cred=Get-Credential   # ZQM-Node-2\zqmlocal  (or .\zqmlocal)
$s=New-PSSession -ComputerName 192.168.1.21 -Port 5985 -Credential $cred
Invoke-Command -Session $s -ScriptBlock { "CONNECTED AS: $env:USERDOMAIN\$env:USERNAME on $env:COMPUTERNAME" }
```

## Failure decoder
- "destination must be added to TrustedHosts" -> step 2 missing.
- "A specified logon session does not exist" / Negotiate no-creds -> supply -Credential (local acct).
- "Access is denied" with an email/user cred -> Microsoft-account logon rejected by NTLM; use a local admin.
- "connecting to destination... cannot connect" on Set-Item WSMan:... -> local WinRM not running; run `winrm quickconfig -q` first.

## Verification from agent terminal
TCP probe: Python socket with timeout (NOT /dev/tcp — hangs on dead hosts). Treat OPEN 5985 as
"WinRM reachable"; a real New-PSSession proves auth. ICMP alone is insufficient (can be firewalled).
