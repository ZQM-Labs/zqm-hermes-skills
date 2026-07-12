# Verify claims — empirical fleet verification discipline (pitfall #20, NEW 2026-07-10)

When the user says "verify claims" (or any status summary is delivered), BACK IT WITH
LIVE TOOL OUTPUT before calling it done. Never assert "all 3 nodes work" from prior
logs alone — re-probe.

## The proven verification stack (all run from Node-1; no creds for 1 & 2)

1) PORT REACHABILITY (bash, use Python socket with timeout — NOT /dev/tcp, it hangs):
   import socket
   def open(ip,p,t=0.6):
       s=socket.socket(); s.settimeout(t)
       try: s.connect((ip,p)); s.close(); return True
       except: return False
   For each node test 22, 5985, 5986. OPEN/CLOSED is ground truth.

2) WINRM 5985 HANDSHAKE (no creds):
   Test-WSMan -ComputerName <ip>
   Valid IdentifyResponse (ProductVersion "OS: 0.0.0 SP: 0.0 Stack: 3.0") = listener alive.
   Test-WSMan -UseSSL :5986 returning "SSL cert unknown / CN mismatch" is SUCCESS — TLS
   completed; it just won't trust the self-signed cert by default.

3) OpenSSH SERVICE STATE (needs zqmlocal cred, via WinRM Invoke-Command):
   Get-Service sshd | Select Status,StartType ; Get-NetTCPConnection -LocalPort 22
   "Status=Running / StartType=Automatic / listening=True" = installed + up.

4) AUTHENTICATED SSH LOGIN (the hard one — see quirk below):
   Generate ed25519 key, push pubkey, ssh -i. On Windows OpenSSH this is BLOCKED by the
   admin-key ACL (see quirk). A successful password/key login is the gold standard but
   often not automatable from the agent; "Permission denied (publickey,...)" from sshd is
   itself proof the server is ALIVE and authenticating (not a connection failure).

## Windows OpenSSH admin-key ACL quirk (why automated key login fails)
Members of the Administrators group are FORCED to use
C:\ProgramData\ssh\administrators_authorized_keys (NOT the per-user
C:\Users\<admin>\.ssh\authorized_keys). That file requires strict owner=Administrators +
ACL (SYSTEM:R, Administrators:R, nothing else). A remote WinRM session (even as an admin)
gets "Access is denied" writing it via Set-Content, and the documented icacls/takeown
dance from a remote token still denied writes this session across 9 attempts.
=> For a definitive automated login proof, use a NON-ADMIN test user (per-user
   authorized_keys follows the normal path, no admin-key restriction), then remove the user.
   Or just hand the user the 10-second manual check:  ssh zqmlocal@<node-ip>
Do NOT report SSH as "unverified/broken" because automated key injection failed — the
port scan + handshake + "Permission denied" already prove the service works.

## Self-correction trap (caught this session)
A status summary claimed the SMB-share bootstrap was hardened (4146 B, dism fallback +
Cert mount). Live read-back showed the share still held the ORIGINAL 3554-B version
(pitfall #18: HTTP-served copy is decoupled from the SMB `web` share; the agent's
PowerShell Copy-Item reported "copied" but the served copy is frozen). ALWAYS read back
the actual artifact (share file + node response.txt) when verifying a prior claim — don't
trust your own earlier "I wrote X" statement.

## Deliverable format for "verify claims"
- Lead with the live probe results (ports/handshake/service), not prose.
- Separate PROVEN vs NOT-PROVEN explicitly.
- Call out any self-correction ("my earlier summary was wrong about X").
- Give the user a 10-second manual confirmation command for the not-automated sliver.
