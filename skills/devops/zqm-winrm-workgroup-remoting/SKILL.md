---
name: zqm-winrm-workgroup-remoting
description: "Open firewall + enable PowerShell Remoting so Node-1 (192.168.1.218) can manage ZQM workgroup nodes Node-2/3/4 remotely. Covers the real gotchas debugged in-session: local WinRM must be up before editing TrustedHosts, and workgroup requires explicit -Credential (not Kerberos)."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [zqm, windows, homelab, winrm, remoting, firewall, workgroup, powershell]
    related_skills: [zqm-local-setup]
---

# ZQM WinRM / PowerShell Remoting Across Workgroup Nodes

Let Node-1 (192.168.1.218, control plane) open a remote PS session to Node-2/3/4.
These boxes are WORKGROUP, not domain-joined — this drives the auth model and
is the source of every gotcha below.

## Topology (trust DNS `.lan`; addresses are NOT sequential — do not guess)
- Node-1 = 192.168.1.218  (this host, control plane)
- Node-2 = 192.168.1.21
- Node-3 = 192.168.1.46
- Node-4 = 192.168.1.215
- WinRM: HTTP 5985 opens after Enable-PSRemoting; HTTPS 5986 closed by default.

## Procedure (run on the named host)
1. TARGET (e.g. Node-2), Admin PS:
   `Enable-PSRemoting -Force`   # opens 5985, auto-start, firewall exception

2. CLIENT (Node-1) — local WinRM MUST be running BEFORE editing TrustedHosts:
   `winrm quickconfig -q`
   GOTCHA: `Set-Item WSMan:\localhost\Client\TrustedHosts ...` fails with
   "The client cannot connect to the destination specified in the request" when
   the LOCAL WinRM service is down. That error is about the client's own service,
   NOT the target. Run `winrm quickconfig -q` first, then retry the Set-Item.

3. CLIENT, Admin PS — add target(s) to TrustedHosts:
   `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force`

4. CLIENT test session — MUST pass explicit local creds (workgroup = no Kerberos):
   ```powershell
   $cred = Get-Credential   # Node-2 LOCAL admin, e.g. ZQM-Node-2\zqmco  (LOCAL, not domain)
   $s = New-PSSession -ComputerName 192.168.1.21 -Port 5985 -Credential $cred
   Invoke-Command -Session $s -ScriptBlock { $env:COMPUTERNAME; (Get-NetIPAddress -AddressFamily IPv4 | Where InterfaceAlias -notmatch Loopback).IPAddress }
   Remove-PSSession $s

   HTTPS variant (port 5986, self-signed cert): the `-UseSSL` switch goes on
   `New-PSSession`, NOT on `New-PSSessionOption` (the latter has NO such parameter —
   putting it there throws `A parameter cannot be found that matches parameter name
   'UseSSL'` and aborts before contacting the host). Correct form:
   ```powershell
   $opt = New-PSSessionOption -SkipCACheck -SkipCNCheck
   $s = New-PSSession -ComputerName 192.168.1.21 -Port 5986 -UseSSL -Credential $cred -SessionOption $opt
   ```
   Capture the real error with `$_.Exception.InnerException.Message` — a bare
   `try/catch { return $null }` hides parameter errors as "connection failed" and
   will send you chasing the wrong root cause.
   ```
   Do NOT omit -Credential: defaults to Negotiate/Kerberos, fails with
   `0x8009030e A specified logon session does not exist`.

## Reachability probe from Node-1 (Python — never /dev/tcp, it hangs on dead hosts)
```python
import socket
def up(ip,p,t=0.6):
    s=socket.socket(); s.settimeout(t)
    try: s.connect((ip,p)); return True
    except: return False
print(up("192.168.1.21",5985))   # or 5000 for the indexer
```
Also `ping -n 2 -w 1000 <ip>`. NO-ICMP + no open ports = host off-net or fully
firewalled. Open 5985 confirms Enable-PSRemoting; open 139/445/5000 on Node-1
confirms its indexer is alive.

## Firewall rule for the indexer (TCP 5000) on a target?
On target: `Get-NetFirewallRule -Direction Inbound -Enabled True | Where LocalPorts -match 5000`
Returns nothing => add:
`New-NetFirewallRule -DisplayName ZQM-Indexer-In-5000 -Direction Inbound -Protocol TCP -LocalPort 5000 -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24`
netsh fallback if stubborn:
`netsh advfirewall firewall add rule name="ZQM-Indexer-In-5000" dir=in action=allow protocol=TCP localport=5000 remoteip=192.168.1.0/24`
Windows is default-deny inbound; "permissive enough" is almost never true —
the indexer port stays closed until you add the rule.

## Verification checklist (from Node-1)
- [ ] Target 5985 OPEN (socket probe)
- [ ] Node-1 local WinRM running (winrm quickconfig -q)
- [ ] Node-1 TrustedHosts contains target IP
- [ ] New-PSSession with -Credential succeeds, returns target hostname/IP

## Microsoft / email accounts CANNOT authenticate over WinRM (the #1 auth failure)
WinRM NTLM on a workgroup box REJECTS Microsoft/email logons (e.g.
`zqmcomputing@gmail.com`). It reaches the auth stage (port open, TrustedHosts OK)
and then fails with a bare **"Access is denied"** — NOT "cannot connect", NOT a
password-wrong prompt. This is an account-TYPE rejection, so retyping the same
credential will never work. Observed end-to-end: user supplied the real Gmail
credential inline, session reached auth, got "Access is denied". Proved it is the
account type, not the password or network.

FIX — create a pure LOCAL admin on the TARGET and use that for remoting:
```powershell
# on the TARGET (e.g. Node-2), Admin PS
net user zqmlocal "S0meStr0ngP@ss!" /add
net localgroup Administrators zqmlocal /add
net localgroup "Remote Management Users" zqmlocal /add
```
Then on Node-1: `$cred = Get-Credential` -> User name `ZQM-Node-2\zqmlocal`
(or `.\zqmlocal`), Password = the local one you set. Do NOT reuse the
Microsoft-account password for the local account.

- Username format that WORKS for local: `MACHINENAME\user`, `.\user`, or bare
  `user` (with caution). Do NOT prefix with a domain.
- If you ever must use the email account, it requires Entra/domain join — out of
  scope for LAN workgroup remoting.

## Error progression chain (what each failure means — fix in order)
1. **"destination must be added to the TrustedHosts configuration setting"**
   -> Workgroup, no Kerberos. Add target IP to Node-1 TrustedHosts (step 3).
2. **"0x8009030e A specified logon session does not exist" / Negotiate with no
   username** -> Session defaulted to Kerberos with no creds. Add `-Credential`
   (step 4).
3. **"Access is denied"** (after creds supplied) -> Microsoft/email account over
   NTLM, or wrong password, or account not local-Admin. If the username is an
   email, apply the Microsoft-account fix above. See
   `references/winrm-error-chain.md` for exact transcripts.

If you sail past all three, the session returns the target hostname/IP.

## Credential hygiene (chat / transcript)
- If the user pastes a live password into chat, do NOT store it, write it to a
  file, or echo it back. Use it inline for the one verification if authorized,
  then recommend rotation. Flag the exposure. (Observed: a real Gmail password was
  pasted mid-session; it was used once for verification and not persisted.)
- Prefer a dedicated local-only `zqmlocal` account so LAN remoting never carries
  the user's primary identity in plaintext script/config.

## Verified outcome (2026-07-10)
End-to-end remoting to **Node-2** was brought up successfully in-session:
`Enable-PSRemoting -Force` on Node-2 + `winrm quickconfig -q` + TrustedHosts on
Node-1 + a LOCAL `zqmlocal` account (NOT the Microsoft/email account) produced a
working `New-PSSession` returning `CONNECTED AS: ZQM-Node-2\zqmlocal on ZQM-NODE-2`.
The email-account "Access is denied" failure was reproduced and confirmed to be an
account-TYPE rejection, not a network/password problem — switching to the local
account resolved it immediately. This validates the whole procedure below.

## One-credential fleet pattern
If you set the SAME `zqmlocal` username + password on Node-2/3/4 via
`scripts/bootstrap.ps1`, the `scripts/fleet.ps1` loop on Node-1 can connect to all
three with a single `.\zqmlocal` `Get-Credential` prompt (the `.` means "local to
the target"). No per-node password juggling.

## Ready-to-run scripts (in this skill's `scripts/`)
- `scripts/bootstrap.ps1` — run ON each target node (Node-2/3/4, Admin PS). Does
  Enable-PSRemoting + Private profile + creates the `zqmlocal` admin + opens the
  indexer port to 192.168.1.0/24. One shot per box.
- `scripts/fleet.ps1` — run ON Node-1 (Admin PS). TrustedHosts pre-set, then a
  TCP pre-check + `New-PSSession` loop over all three nodes, reporting host/IP/
  uptime or UNREACHABLE/FAIL per node.
Copy these to C:\Users\zqmco\ on the relevant host and run in an elevated shell.

## Notes
- The canonical zqm-local-setup SKILL.md is at
  C:\Users\zqmco\zqm-hermes-skills\skills\productivity\zqm-local-setup\SKILL.md
  (custom/unregistered; its Topology block wrongly listed Node-2 as "this host").
- Overlap: `zqm-lan-node-reachability` owns the DNS-resolve + Python TCP probe
  recipe; this skill owns the WinRM enablement + remediation. The python probe
  snippet is duplicated in both by design (each is self-contained).
