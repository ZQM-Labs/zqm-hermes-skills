# WinRM / PowerShell Remoting on the ZQM Workgroup LAN

Goal: let Node-1 manage Node-2/3/4 (and verify) via `New-PSSession`. All boxes are
WORKGROUP (not domain-joined) — this changes the auth path completely vs a domain.

## End-to-end playbook (verified 2026-07-10, real session that reached Node-2)

### On the TARGET node (e.g. Node-2), Admin PowerShell:
```
Enable-PSRemoting -Force
Set-NetConnectionProfile -NetworkCategory Private
# Create a LOCAL admin — do NOT use a Microsoft/email account (see Pitfall 1)
net user zqmlocal "<new-pass>" /add
net localgroup Administrators zqmlocal /add
net localgroup "Remote Management Users" zqmlocal /add
# Optional: open the indexer port to the LAN subnet only
New-NetFirewallRule -DisplayName "ZQM-Indexer-In-5000" -Direction Inbound `
  -Protocol TCP -LocalPort 5000 -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24
```

### On the CLIENT node (Node-1), Admin PowerShell:
```
# Node-1's OWN WinRM must be running or Set-Item TrustedHosts fails (Pitfall 2)
winrm quickconfig -q
Set-Item WSMan:\localhost\Client\TrustedHosts `
  -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force
```

### Test the session (from Node-1):
```
$cred = Get-Credential   # User: .\zqmlocal  | Pass: the local password
$s = New-PSSession -ComputerName 192.168.1.21 -Port 5985 -Credential $cred
Invoke-Command -Session $s -ScriptBlock { "$env:USERDOMAIN\$env:USERNAME on $env:COMPUTERNAME" }
Remove-PSSession $s
# Expect: CONNECTED AS: ZQM-Node-2\zqmlocal on ZQM-NODE-2
```

## Pitfalls (each caused a real failure this session — in order encountered)
1. **Microsoft/email account rejected.** `zqmcomputing@gmail.com` over NTLM → "Access is denied".
   WinRM NTLM will NOT accept Microsoft-account email logons on a workgroup box.
   Fix: use a local account (`.\zqmlocal`).
2. **Node-1's own WinRM not running.** `Set-Item WSMan:\localhost\Client\TrustedHosts`
   needs the local WinRM service up; otherwise "client cannot connect to the destination …
   run winrm quickconfig". Fix: `winrm quickconfig -q` on Node-1 FIRST.
3. **TrustedHosts required for workgroup.** Without it: "destination must be added to the
   TrustedHosts configuration setting". Fix: Set-Item as above (comma-list all target IPs).
4. **Adapter must be Private.** If the LAN adapter is Public, Private-scoped firewall rules
   won't apply. Fix: `Set-NetConnectionProfile -NetworkCategory Private` on the target.
5. **Negotiate/Kerberos defaults fail with no creds.** Passing explicit `-Credential` (local
   account) forces NTLM, which is what workgroup remoting uses.

## Error → cause → fix quick map
- "must be added to the TrustedHosts" → add target IP to Node-1 TrustedHosts.
- "A specified logon session does not exist" / Negotiate error → supply `-Credential` with a LOCAL account.
- "Access is denied" with an email cred → switch to a local account.
- "client cannot connect to the destination" on Set-Item → start Node-1 WinRM (`winrm quickconfig -q`).

## Non-cred / port-only reachability check (from Node-1)
Do NOT use bash `/dev/tcp` — it HANGS on unresponsive hosts (cost a 180s timeout this session).
Use Python with a socket timeout (`scripts/probe_lan.py`), or `Test-NetConnection -Port`.
Ports to check: 22, 80, 139, 443, 445, 5000, 5001, 5985, 8080.

## Storing scripts for grab-and-run on remote nodes
Garden-02 (`192.168.1.40`) is the only Garden with a cached SMB credential from Node-1, so
file writes to `\\192.168.1.40\web` and `\UNASSIGNED-01` succeed without re-auth. Drop
`zqm-bootstrap.ps1` / `zqm-fleet.ps1` there; remote nodes can `net use \\192.168.1.40\web /user:…`
and run them. Verify copies with `sha256sum` (all three of local + both shares matched this session).
