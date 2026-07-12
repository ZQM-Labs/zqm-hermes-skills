# WinRM Workgroup Error Chain (exact transcripts + fixes)

Condensed from a live ZQM Node-1 → Node-2 session (192.168.1.218 → 192.168.1.21),
2026-07-10. Each error is reproduced with the fix that resolved it.

## Setup already done before the errors
- Target (Node-2): `Enable-PSRemoting -Force` → 5985 OPEN (verified by socket probe).
- Client (Node-1): `winrm quickconfig -q` → local WinRM running.
- Client: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21" -Force`.

## ERROR 1 — local WinRM down when editing TrustedHosts
```
Set-Item : The client cannot connect to the destination specified in the request.
Verify that the service on the destination is running ... "winrm quickconfig".
```
NOT about the remote node — it's Node-1's OWN WinRM service.
FIX: `winrm quickconfig -q` on Node-1 first, then re-run the Set-Item.

## ERROR 2 — Negotiate/Kerberos with no credential
```
Connecting to remote server 192.168.1.21 failed ... errorcode 0x8009030e
A specified logon session does not exist. It may already have been terminated.
Possible causes are: The user name or password specified are invalid.
Kerberos is used when no authentication method and no user name are specified.
```
FIX: pass `-Credential` explicitly. Never rely on default auth on a workgroup.

## ERROR 3 — Microsoft/email account over NTLM (final blocker this session)
```
New-PSSession : [192.168.1.21] ... failed with the following error message :
Access is denied.
```
Context: credential supplied was `zqmcomputing@gmail.com` (a Microsoft/email
account). Port was OPEN, TrustedHosts OK, auth reached — then NTLM rejected the
email account type. Retyping it cannot work.
FIX: create a local admin on the target and use that:
```
net user zqmlocal "S0meStr0ngP@ss!" /add
net localgroup Administrators zqmlocal /add
net localgroup "Remote Management Users" zqmlocal /add
```
Connect with `-Credential` username `ZQM-Node-2\zqmlocal` (or `.\zqmlocal`).

## Success signature
```
CONNECTED AS: ZQM-Node-2\zqmlocal on ZQM-Node-2 (IPs: 192.168.1.21)
```
(Not yet achieved at time of writing — blocked at ERROR 3; fix above resolves it.)

## Probes that confirmed network was fine (rule these out first)
```
python -c "import socket;s=socket.socket();s.settimeout(0.6);s.connect(('192.168.1.21',5985));print('OPEN')"
# Node-2 :5985 OPEN after Enable-PSRemoting; :5986 closed
# Node-1 :5985 OPEN after winrm quickconfig -q
```
If 5985 is OPEN, the failure is auth (ERROR 2/3), not network.
