# LAN Node Remediation (bring dark nodes up / open remote mgmt)

When a node resolves via DNS but shows no open ports + no ICMP (DARK), it needs
firewall/service bring-up ON THAT HOST. The agent's PowerShell on Node-1 is NON-ELEVATED
(Elevated: False), so admin steps must be delivered as **copy-paste command blocks** for
the user to run in an Admin PowerShell on the target node. The agent CAN verify remotely
(port scan, PSRemoting session) but CANNOT write TrustedHosts/firewall rules from here.

## 1. Classify adapter as Private + open indexer port (run on Node-2/3/4, Admin PS)
```powershell
Set-NetConnectionProfile -NetworkCategory Private
# indexer port — change 5000 if the service listens elsewhere
New-NetFirewallRule -DisplayName "ZQM-Indexer-In-5000" -Direction Inbound `
  -Protocol TCP -LocalPort 5000 -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24
# allow ping from the subnet
Enable-NetFirewallRule -Name FPS-ICMP4-ERQ-In
Set-NetFirewallRule -Name FPS-ICMP4-ERQ-In -RemoteAddress 192.168.1.0/24
```
Verify before adding (Windows is default-deny inbound — an indexer won't be reachable
until a rule permits its port):
`Get-NetFirewallRule -Direction Inbound -Enabled True | ?{$_.LocalPorts -match '5000'}`
If a rule already exists, skip New-NetFirewallRule. If it exists with the same
-DisplayName, use a new name or `Remove-NetFirewallRule -DisplayName "..."` first.
netsh fallback if NetSecurity cmdlets misbehave:
`netsh advfirewall firewall add rule name="ZQM-Indexer-In-5000" dir=in action=allow protocol=TCP localport=5000 remoteip=192.168.1.0/24`

## 2. PowerShell Remoting (workgroup, no domain)
Target (run on Node-2/3/4): `Enable-PSRemoting -Force` opens TCP 5985.
CLIENT side (Node-1) MUST add the target to TrustedHosts or auth fails with:
"The WinRM client cannot process the request ... HTTPS transport must be used or the
destination machine must be added to the TrustedHosts configuration setting."

On Node-1, Admin PowerShell — FIRST start the LOCAL WinRM service on Node-1, THEN set
TrustedHosts:
```powershell
# Step 0 (REQUIRED): the local WinRM service must be running before Set-Item works.
# Without it, Set-Item WSMan:\localhost\Client\TrustedHosts fails with a MISLEADING
# "client cannot connect to the destination specified in the request" — that error is
# about THIS host's (Node-1's) WinRM service, NOT the remote node. Fix: start local
# WinRM first.
winrm quickconfig -q
# If quickconfig errors on network profile, also run:
#   Set-NetConnectionProfile -NetworkCategory Private
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force
```
Then test from Node-1 (agent can run non-elevated since the session is outbound):
```powershell
$s=New-PSSession -ComputerName 192.168.1.21 -Port 5985 `
   -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)
Invoke-Command -Session $s -ScriptBlock {$env:COMPUTERNAME}
Remove-PSSession $s
```
PITFALL (observed 2026-07-10): `Set-Item WSMan:\localhost\...` reads/writes the LOCAL
WinRM service. If that service is stopped, the error text ("client cannot connect to the
destination") reads like a remote-node problem but is purely local. `winrm quickconfig -q`
starts it (creates HTTP 5985 listener, sets auto-start) and the TrustedHosts write then
succeeds. Verify the local service is up first by probing `127.0.0.1:5985` and the
LAN-IP:5985 with the socket recipe in lan-node-probe.md.
PITFALL: port OPEN on target ≠ session works. The client-side TrustedHosts write is the
usual blocker and requires elevation the agent does not have. Deliver that step as a
copy-paste block; 5986 (HTTPS) stays closed unless a cert is configured — 5985 is enough.

## 3. Re-verify from Node-1
Re-run `references/lan-node-probe.md` after remediation. Expect Node-N to gain open ports
(5000 + ICMP) and a successful New-PSSession.
