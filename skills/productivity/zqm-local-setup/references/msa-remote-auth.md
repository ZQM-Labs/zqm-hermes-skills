# Microsoft-Account remote auth failure on ZQM Windows nodes

## Symptom
User insists `<email> / <pw>` logs in fine (console / RDP / Windows Hello) but the agent's
SSH or WinRM test returns REJECTED / "Access is denied" / `0x8009030e`. The user may say
"that account works properly" — do NOT just accept either side; run the full diagnostic below
and differentiate a *method artifact* from a *real wrong password*.

## Root cause
On ZQM nodes the interactive login identity is a `PrincipalSource=MicrosoftAccount` (e.g.
`zqmcomputing@gmail.com` shown locally as `zqmco`). Interactive console login accepts the MSA,
but **remote SSH/WinRM auth with an MSA UPN often fails** unless explicitly enabled. Three
DIFFERENT failures look identical at first glance — must tell them apart:

1. **TrustedHosts client-side block (NOT a password failure).**
   WinRM error: *"The WinRM client cannot process the request. ... in the TrustedHosts list
   might not be authenticated."*
   Fix: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force` (elevated), re-test.
   If the error then becomes `0x8009030e`, the password really is wrong.

2. **Real invalid credential (`0x8009030e`).**
   WinRM error: *"A specified logon session does not exist ... provided credentials are not
   valid on the target server"* → password does not match the account.
   SSH `AuthenticationException` → same conclusion. This is the genuine "wrong password" signal.

3. **sshd_config key-only restriction.**
   Windows sshd default `Match Group administrators` block can force admin accounts to key auth
   only, so password-SSH is rejected even with the right password. Check
   `C:\ProgramData\ssh\sshd_config` for `Match Group administrators` / `AuthenticationMethods`.

## Diagnostic chain (run on the node you CAN reach, e.g. Node-1)
```powershell
Get-LocalUser | Select-Object Name,Enabled,PrincipalSource,SID
# PrincipalSource=MicrosoftAccount => MSA; the local SAM name is the Name column (e.g. zqmco)
whoami                                   # shows the local SAM name the MSA maps to
(Get-Service WinRM).Status
Get-ChildItem WSMan:\localhost\Listener   # is a listener present?
Get-Content 'C:\ProgramData\ssh\sshd_config' | Select-String 'Match|AuthenticationMethods|PasswordAuthentication'
```

## KEY PITFALL: garden password != Windows password
`344SW00DL4nd!` is the **Garden admin** (`azelenski`, Synology/TerraMaster). It authenticates
Gardens over DSM / SSH / SMB but does **NOT** authenticate Windows-node SSH/WinRM. Do not assume
a password that works on a Garden also works for Windows-node login — verify each surface
separately. (A user may conflate them because the same string was reused.)

## Verify a Windows login password WITHOUT trusting the user's claim
Test WinRM to the node as the SAM name (`zqmco`) with the candidate password. `0x8009030e` =
wrong. Remember: the user's "it works" usually means console / Hello / PIN — that does NOT prove
the account password authenticates a remote (SSH/WinRM) session.

## Reusable tool
`scripts/zqm-cred-sweep.py` — TCP port probe + paramiko SSH auth sweep across candidate
(user,password) pairs against a target host. Use it to enumerate which credential (if any) opens
a node before concluding "no credential works".
