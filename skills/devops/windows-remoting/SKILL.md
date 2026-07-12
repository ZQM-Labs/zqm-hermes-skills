---
name: windows-remoting
description: "Establish, verify, and troubleshoot PowerShell Remoting (WinRM) across NON-domain (workgroup) Windows hosts on a LAN. Use when connecting from one Windows box to another via New-PSSession/Enter-PSSession/Invoke-Command, and when diagnosing 'Access is denied', 'TrustedHosts', or 'WinRM service not running' errors. Covers the full failure-chain playbook plus how to park reusable scripts on a Synology NAS share for grab-and-run on remote nodes."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [windows, winrm, powershell-remoting, workgroup, lan, zqm, homelab, nas]
---

# Windows Remoting (Workgroup / Non-Domain LAN)

## When to use
- You need Node-A to run commands on Node-B over the network (New-PSSession / Invoke-Command / Enter-PSSession).
- A remote-session attempt failed with: "must be added to the TrustedHosts", "client cannot connect to the destination", "Access is denied", or a timeout on port 5985.
- You are distributing a bootstrap/setup script to several remote Windows workstations.

## Critical mental model
Workgroup (non-domain) WinRM does NOT use Kerberos. It uses NTLM, and NTLM over plaintext HTTP requires the TARGET to be in the CLIENT's TrustedHosts list. There are TWO machines in play, each with its own role:

- TARGET (server): must have WinRM listeners up + firewall open (Enable-PSRemoting).
- CLIENT (caller): must (a) have its own WinRM service running to write TrustedHosts, and (b) list the target in TrustedHosts.

A session has FOUR independent prerequisites. If any one is missing you get a different error. Verify in this order.

## Procedure

### On the TARGET (run once, Admin PowerShell)
    Enable-PSRemoting -Force
    Set-NetConnectionProfile -NetworkCategory Private   # Private-scoped rules need this
    # (optional) open the indexer/service port to the LAN subnet only
    New-NetFirewallRule -DisplayName "ZQM-Indexer-In-5000" -Direction Inbound `
      -Protocol TCP -LocalPort 5000 -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24

### On the CLIENT (run once, Admin PowerShell)
    winrm quickconfig -q          # starts CLIENT's own WinRM service; required before Set-Item TrustedHosts works
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force

### Establish the session (CLIENT)
    $cred = Get-Credential        # MUST be a LOCAL account on the target, e.g. .\zqmlocal  (NOT an email/Microsoft account)
    $s = New-PSSession -ComputerName 192.168.1.21 -Port 5985 -Credential $cred
    Invoke-Command -Session $s -ScriptBlock { $env:COMPUTERNAME }
    Remove-PSSession $s

## Failure-chain playbook (diagnose by the EXACT error)
| Error | Meaning | Fix |
|---|---|---|
| TCP 5985 closed on target | WinRM not listening / firewall | Run `Enable-PSRemoting -Force` on TARGET |
| "destination must be added to the TrustedHosts configuration" | Target not trusted by CLIENT | `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<ip>" -Force` on CLIENT |
| "client cannot connect to the destination... run winrm quickconfig" (when setting TrustedHosts) | CLIENT's own WinRM service is NOT running, so Set-Item can't reach local WSMan | Run `winrm quickconfig -q` on the CLIENT first, THEN re-run Set-Item |
| "A specified logon session does not exist" / Negotiate with no username | Session defaulted to Kerberos/Negotiate with no creds (workgroup can't do Kerberos) | Supply `-Credential` with a TARGET local account |
| "Access is denied" with an email/Microsoft account (e.g. zqmcomputing@gmail.com) | NTLM rejects Microsoft/email logons on workgroup | Create a LOCAL admin on the target (`net user zqmlocal ...` + add to Administrators + "Remote Management Users") and use `.\zqmlocal` |
| "Access is denied" with blank Get-Credential | No username entered at the prompt | Re-run and type `.\\zqmlocal` at the User name prompt |

## WinRM listener verification (no creds needed)
`Test-WSMan` is a credential-free handshake — use it to prove a target's listener is ALIVE from the
client BEFORE troubleshooting auth:
- `Test-WSMan -ComputerName <ip>` → valid `IdentifyResponse` (Microsoft WSMan Stack) = HTTP 5985 listener UP.
- `Test-WSMan -ComputerName <ip> -UseSSL` → a TLS error ("The server certificate is not trusted /
  CN mismatch / CA unknown") means the **TLS handshake SUCCEEDED** — the 5986 HTTPS listener is
  alive, Test-WSMan just won't trust the self-signed cert by default. Only a *connection-refused*
  (no TCP listener) means the port is truly down. A cert-error is a SUCCESS signal for reachability.
- Combine with a Python socket scan of 5985/5986/22 so you know exactly which failover paths answer
  (verified on ZQM Node-2: 5985+5986 answered, 22 closed → OpenSSH install had not landed a listener).

## Pitfalls (learned the hard way)
- The TrustedHosts error during `Set-Item` is a CLIENT-side problem, not the target. The CLIENT must have WinRM running (`winrm quickconfig -q`) or Set-Item fails with "client cannot connect to the destination".
- A Microsoft/email account (even the only user on a solo machine) CANNOT be used for WinRM NTLM. You must create a separate local admin account. This is non-negotiable on workgroup.
- `winrm quickconfig -q` also flips `LocalAccountTokenFilterPolicy`, which is what grants the local admin remote rights — do not skip it.
- Use `.\zqmlocal` (dot = "local to target") so the same credential string works against every node that shares the account name/password.
- Probe with a Python socket script (per-host timeout ~0.6s) rather than bash `/dev/tcp` — the latter HANGS on unresponsive hosts and will time out the whole command. ICMP (ping) alone is insufficient: a host can answer ping but have all ports filtered, or vice-versa. Always combine ICMP + a TCP port scan.
- Node DNS names (`.lan`) do NOT map to sequential IPs. Resolve them (`socket.gethostbyname`) before assuming addresses; e.g. in one ZQM deployment Node-3 resolved to .46 and Node-4 to .215, not .22/.23.
- DPAPI `LocalMachine` blobs are MACHINE-scoped — re-encrypt the secret ON the target node; never copy a Node-A-encrypted cred file to Node-B (it won't decrypt). See `references/headless-windows-automation.md`.
- `$PSScriptRoot` is EMPTY when a script is run over SSH by path (`ssh host "pwsh -File C:\x.ps1"`) — resolve the script dir via `$MyInvocation.MyCommand.Path` fallback, or every `Join-Path $PSScriptRoot` default breaks silently.
- Register scheduled tasks HEADLESS via `Register-ScheduledTask` DIRECTLY in the SSH session (admin user). `Start-Process -Verb RunAs` NO-OPS when no UAC surface exists. `New-ScheduledTaskAction` takes `-Argument` (singular).
- SYSTEM scheduled-task principal CANNOT WinRM/Negotiate to a workgroup peer (no network identity); use SSH as the headless node plane. Enabling `AllowBasic` does NOT make the server advertise Basic.
- Prefer native `ssh.exe`/`scp.exe` over the Python paramiko client (intermittently "File is not open for reading" on these hosts). `scp.exe` dest needs a forward-slash POSIX path (`C:/zqm/link/`).
- Garden SMB "System error 1312 / logon session does not exist" on SOME garden IPs but not others (same cred) = Garden-side IP allowlist (Synology DSM), fixed on the NAS not the node. Rule out firewall first by probing TCP 445.
- WinRM error disambiguation (workgroup): "in the TrustedHosts list might not be authenticated" = CLIENT-side TrustedHosts block — fix with `Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force` on the CLIENT (needs the client's own WinRM running: `winrm quickconfig -q`). After clearing that, `0x8009030e ... provided credentials are not valid on the target server` = GENUINE credential-invalid (wrong password), NOT policy. Do not re-clear TrustedHosts hoping it helps — the password is the problem.
- `LogonUser` (advapi32) error 1326 on the LOCAL machine is the most decisive "bad password" proof: no network, no TrustedHosts, no sshd. If 1326, the supplied password is wrong for that Windows account regardless of what works elsewhere (e.g. a Garden). Run this BEFORE touching sshd_config or MSA remote-sign-in settings.

## Script distribution pattern (grab-and-run from remote nodes)
For scripts meant to be run on multiple nodes, PARK them on a Synology NAS share (the "ZQM-Gardens") so any node can pull and run:
- Gardens expose SMB on 445; if Node-1 already holds an IPC$ session to a Garden, `cp` to `//<garden-ip>/web/` or `//<garden-ip>/UNASSIGNED-01/` succeeds without NAS creds.
- On the remote node: `net use \\<garden-ip>\web /user:<nasuser> <naspass>` then `powershell -ExecutionPolicy Bypass -File \\<garden-ip>\web\<script>.ps1`.
- Note: ZQM-Gardens are Synology NAS (not Windows) — they are file-drop points, never PowerShell-Remoting targets.

## Full enumeration rule (USER DIRECTIVE: "full enumeration, you should be able to do the same things I can do")
Before declaring a target node "unreachable" / "can't be administered" / "needs the owner", you MUST
enumerate and LIVE-TEST every access path the human themselves could use. A first REJECT is not
proof of unreachability — it is a hypothesis to exhaust. The user explicitly rebuked a premature
"can't reconcile Node-4" derived from a single failed probe. Enumerate in this order, testing each
against the target with BOTH SSH (22) and WinRM (5985):

1. LOCAL CREDENTIAL STORES on the managing node (Node-1): DPAPI vault JSON files in `C:\zqm\cred\*`
   (decrypt to read user + confirm pw length); `cmdkey /list` (note `Domain:` = SMB/garden creds,
   NOT Windows-local); `schtasks /query` action args (a task may embed a working cred); other secret
   files via `search_files` for `*.json`/`*.cred` under `C:\zqm`.
2. TRY EVERY stored credential over BOTH protocols — not just the obvious one. A vaulted `zqmlocal`
   may work on one node and not another (password drift); a garden cred won't work for Windows auth
   but test it to rule out confusion.
3. LATERAL from OTHER nodes: each node's local accounts (e.g. `zqmco`/`AlexZ` on Node-1) and vaults
   may share a password with the target. SSH/WinRM from Node-1 using those accounts.
4. GARDEN plane: can a Synology/TerraMaster Garden administer the Windows node? VERIFY, don't assume
   — but know the structural fact: DSM/TOS are storage OSes; they cannot run `Set-LocalUser` on a
   Windows SAM. A Garden can serve files but cannot reconcile a node's local account.
5. HYPERVISOR / IPMI / iDRAC plane: probe the target's NEIGHBORING IPs for mgmt ports (623 IPMI, 443,
   8006 Proxmox, 5900 VNC, 3389 RDP) via Python socket scan. If the node is a VM, the host console
   can inject the command.
6. UNKNOWN HOST (no topology entry, e.g. "Node 5"): SWEEP the subnet (ICMP ping + TCP 22/5985) for
   live Windows hosts BEFORE concluding the host doesn't exist. Absence from a stale topology file
   ≠ absence from the LAN.
7. ONLY after ALL of the above are probed live and rejected is "needs owner-supplied Windows password
   or local console" the PROVEN conclusion. Surface the gate honestly (show the evidence chain), do
   NOT loop the same failing call, but also do NOT stop at the first reject.

This is the remoting analogue of the "hash claims" recreation-tier discipline: recreate the negative
from live probes across every path, don't infer it from one failed attempt. See `references/msa-auth-diagnostic.md`
step 7 for the subnet-sweep recipe.

## Diagnostic: owner says "this account works" but remote auth is REJECTED
A common stall: the owner logs in daily with `someuser@domain.com` / a password and insists it
"works properly", but your SSH/WinRM probe returns `AuthenticationException` / "Access is denied".
Do NOT just accept the claim OR declare "can't" — run this diagnostic. Root causes observed on
ZQM Node-1:
- The account is a **Microsoft-account (MSA) principal**, not a local SAM account. Console/RDP
  login accepts the MSA, but headless SSH/WinRM often rejects it — or the password given is for
  a DIFFERENT system entirely.
- The password supplied is valid for ANOTHER system (e.g. a Synology/TerraMaster Garden admin
  `azelenski`), NOT the Windows login. Reusing it for SSH to a node fails even though it "works"
  against the Garden.

Steps (run on the machine the owner logs into, e.g. Node-1 — full script in
`references/msa-auth-diagnostic.md`):
1. Identify account type + local alias:
   `Get-LocalUser | Select-Object Name,Enabled,PrincipalSource,SID`
   - `PrincipalSource=MicrosoftAccount` + SID `S-1-5-21-…` = MSA represented by a LOCAL SAM alias
     (e.g. `zqmcomputing@gmail.com` → local name `zqmco`). Use the alias for SSH/WinRM, but the
     SAME password must match the WINDOWS login, not the Garden login.
   - `PrincipalSource=Local` = true local account.
2. Check sshd accepts the account:
   `Get-Content 'C:\ProgramData\ssh\sshd_config' | sls 'Match|AllowUsers|AuthenticationMethods|PasswordAuthentication'`
   (default `Match Group administrators` strips admin rights unless overridden)
3. Check WinRM actually listens — a Running service with NO listener still rejects:
   `Get-ChildItem WSMan:\localhost\Listener`   # expect an http/https entry; empty = no listener
4. Live-test the credential against the REAL target with BOTH forms (UPN `zqmcomputing@gmail.com`
   and local alias `zqmco` / `.\\zqmco`) using the exact password. If BOTH are REJECTED, the
   password does not match the Windows login — but a remote REJECT can be a TrustedHosts/policy
   artifact, so confirm with step 5.
5. DECISIVE local password test (no network, no policy) — run on the machine the owner logs
   into (e.g. Node-1). This separates "wrong password" from "remote-auth policy blocks it":
   ```powershell
   Add-Type @'
   using System; using System.Runtime.InteropServices;
   public class Auth { [DllImport("advapi32.dll",SetLastError=true)] public static extern bool LogonUser(string u,string d,string p,int t,int p2,out IntPtr h); [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h); }
   '@
   $h=[IntPtr]::Zero
   $ok=[Auth]::LogonUser('zqmco',$null,'<pw>',2,0,[ref]$h)   # 2 = LOGON32_LOGON_INTERACTIVE
   if($ok){'LOCAL LOGON OK: password valid locally'}else{'LOCAL LOGON FAIL: lastcode='+[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
   ```
   Error 1326 = "unknown user name or bad password" → the password is GENUINELY WRONG for that
   Windows account, proven locally with no TrustedHosts / sshd / MSA-remote-sign-in confounding.
   If 1326, STOP testing remote forms — the fix is the PASSWORD, not the protocol, and enabling
   "MSA remote sign-in" will NOT help because the password itself is wrong.
6. ONLY if LogonUser SUCCEEDS locally, live-test remote: SSH + WinRM 5985 to the REAL target with
   BOTH the UPN and the local alias. If LogonUser OK but remote REJECTED, the blocker is
   remote-auth policy (sshd_config `Match Group administrators`, or MSA not enabled for remote
   sign-in) — fixable by enabling MSA remote sign-in. Do NOT enable MSA remote sign-in when
   LogonUser already returned 1326; it cannot fix a wrong password.
7. Cross-system trap: if the same password works for a Garden (SMB/SSH to Synology/TerraMaster),
   that proves NOTHING about Windows-node auth — Garden accounts are not Windows-local. On ZQM,
   `344SW00DL4nd!` is the Garden admin `azelenski` password and does NOT authenticate the
   `zqmcomputing@gmail.com` MSA (proven: local LogonUser 1326 + WinRM 0x8009030e). Test the
   Windows login password SEPARATELY from any Garden password.
Only after the diagnostic shows the credential truly doesn't authenticate to any node (and no
other stored cred / neighbor hypervisor plane works — see the "Full enumeration rule" section
above) is "needs owner-supplied Windows password or local console" the proven conclusion.

Pitfalls specific to this diagnostic:
- An MSA UPN and its local SAM alias are the SAME login; if one is rejected with the right
  password, the other will be too. Don't waste cycles trying both as if independent — the fix is
  the PASSWORD (or enabling MSA remote auth), not the username form.
- "Works for me" almost always means console/RDP, which uses a different auth path than headless
  SSH/WinRM. Treat owner claims as hypotheses; recreate with a live probe before reporting.
- If the target node IP is UNKNOWN (e.g. "Node 5" with no topology entry), SWEEP the subnet
  (ICMP ping + TCP port scan on 22/5985) to discover live Windows hosts BEFORE assuming the host
  doesn't exist. Absence from a stale topology file is not proof of absence from the LAN.

## Support files
- `references/msa-auth-diagnostic.md` — runnable diagnostic (account-type detection, sshd_config
  check, WinRM listener check, live credential test) for the "account works but remote auth
  rejected" stall, with the ZQM Node-4 case study (garden password != Windows login).
- `scripts/enable_msa_remote_signin.ps1` — ELEVATED, idempotent enable of MSA remote sign-in
  (policy + WinRM listener + sshd PasswordAuthentication + admin group). RUN THIS ONLY AFTER
  `LogonUser` proves the password is valid locally (step 5 of the diagnostic) — it cannot fix a
  wrong password (1326).
- `templates/zqm-bootstrap.ps1` — copy-paste bootstrap to run on each remote Windows workstation (Enable-PSRemoting + Private profile + local admin + optional indexer port).
- `scripts/zqm-fleet.ps1` — run on the CLIENT (Node-1) to health-check/connect all nodes in one loop using a single `.\\zqmlocal` credential.
- `references/headless-windows-automation.md` — DPAPI machine-scope, `$PSScriptRoot`-empty-over-SSH, headless task registration, SYSTEM-vs-WinRM-Negotiate, paramiko→ssh.exe, Garden-SMB "1312" IP-allowlist.
