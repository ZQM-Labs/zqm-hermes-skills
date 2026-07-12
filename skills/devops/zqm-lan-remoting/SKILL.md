---
name: zqm-lan-remoting
description: "Configure and verify Windows workgroup PowerShell Remoting (WinRM) across the ZQM LAN from Node-1, and park reusable scripts on the Synology ZQM-Garden NAS shares. Use when bringing ZQM-Node-2/3/4 under remote management, troubleshooting 'Access is denied' / TrustedHosts / WinRM errors, or deploying bootstrap/fleet scripts."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [zqm, windows, homelab, winrm, psremoting, lan, synology]
---

# ZQM LAN PowerShell Remoting

## When to use
- Bringing ZQM-Node-2/3/4 under remote management from Node-1 (192.168.1.218).
- A remote PSSession fails with Access is denied / TrustedHosts / WinRM errors.
- You need a copy-paste bootstrap to run on a fresh workstation, or a fleet loop from Node-1.
- Parking a script on a ZQM-Garden NAS share so any node can pull it.
- Auditing whether a Garden `\\backups` / `\\web` SMB share is reachable (see below).

## Verified topology (2026-07)
Windows nodes (workgroup, NOT domain-joined):
| Node | IP | .lan | Notes |
|---|---|---|---|
| Node-1 | 192.168.1.218 | ZQM-Node-1.lan | This host (agent runs here, NON-elevated PS) |
| Node-2 | 192.168.1.21 | ZQM-Node-2.lan | Confirmed reachable via local `zqmlocal` acct |
| Node-3 | 192.168.1.46 | ZQM-Node-3.lan | bootstrap NOT yet run (5985 closed) |
| Node-4 | 192.168.1.215 | ZQM-Node-4.lan | bootstrap NOT yet run (5985 closed) |

Synology "ZQM-Gardens" NAS (SMB/445 open; use for script drop):
Garden-01 .173, Garden-02 .40, Garden-03 .64, Garden-04 .144/.147.
Node-1 keeps a live IPC$ to Garden-02 (.40) — `web` and `UNASSIGNED-01` shares are writable without re-auth.
Garden NAS resolve by IP or FQDN `<name>.lan` / `.local`; **NOT by bare hostname** `backups`/`web` (those are share names — see Garden SMB section).

## Working recipe (verified end-to-end for Node-2)
Client side (Node-1, Admin PowerShell):
    winrm quickconfig -q
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force
Target side (each node, Admin PowerShell):
    Enable-PSRemoting -Force
    Set-NetConnectionProfile -NetworkCategory Private
Test from Node-1:
    $cred = Get-Credential   # .\zqmlocal + local password
    $s = New-PSSession -ComputerName 192.168.1.21 -Port 5985 -Credential $cred
    Invoke-Command -Session $s -ScriptBlock { "$env:USERDOMAIN\$env:USERNAME on $env:COMPUTERNAME" }
    Remove-PSSession $s

## Garden NAS SMB share reachability (probe FROM a Windows node, e.g. Node-1)
When auditing whether a Garden `\\backups` / `\\web` share is "up", run this from
Node-1. Do NOT assume the LEAD `:445` TCP probe alone proves share availability,
and do NOT assume bare `\\backups` is a resolvable host.

- **`backups` / `web` are SHARE names, not hosts.** They do NOT resolve via DNS
  (`Resolve-DnsName backups` -> "DNS name does not exist") or NetBIOS
  (`nbtstat -a backups` -> "Host not found"). Reach the NAS by IP
  (`192.168.1.173`) or FQDN (`ZQM-Garden-01.lan`, resolved on the `.lan` suffix),
  then a share name: `\\192.168.1.173\backups` or `\\ZQM-Garden-01.lan\backups`.
- **Server-alive check:** TCP `:445` probe (Python `socket.connect` from Node-1)
  plus `nbtstat -A <ip>` — a registered `ZQM-GARDEN-01 <20>` line proves SMB
  file-service is up even when DNS/hostname resolution fails.
- **`net use` error-code interpretation (the key diagnostic):**
  - `1223` "operation canceled by user" = server REACHED + share PRESENTED; only
    the interactive auth prompt couldn't be satisfied (agent has no cred). NOT a
    name error. -> host/share alive.
  - `3024` "password is invalid" = server reached + share presented, but the
    stored/used credential was rejected (expired/wrong/locked on NAS).
  - `67` "network name cannot be found" = AMBIGUOUS: a genuinely bad
    share/host name OR the SMB redirector is wedged (see below). Corroborate with
    the TCP `:445` / `nbtstat` checks before concluding "name wrong".
  - `1702` "binding handle invalid" = SMB redirector (LanmanWorkstation) WEDGED;
    even `\\localhost\IPC$` and `net view \\127.0.0.1` fail. Transient Win10 state,
    NOT a target-host problem. Do not conclude the NAS is down from 1702.
- **Stored-credential mismatch:** `cmdkey /list` shows `Domain:target=ZQM-Garden-01`
  user `azelenski`, but that bare hostname does NOT resolve (only `.lan` FQDN/IP
  do), so the cred never auto-applies to `\\192.168.1.173\...`. Re-key the cmdkey
  target to `192.168.1.173` or `ZQM-Garden-01.lan`, or have a human run
  `net use \\ZQM-Garden-01.lan\backups /user:azelenski *` with the live NAS password.
- Full probe recipe + reusable `.ps1` skeleton: `references/garden-smb-probe.md`.

## Pitfalls (real, hit during setup)
- MS/email logons REJECTED: `zqmcomputing@gmail.com` fails with "Access is denied" over workgroup NTLM. WinRM NTLM will NOT accept a Microsoft/email account. Use a LOCAL admin (`.\zqmlocal`). This is a credential-TYPE block, not a wrong-password block.
- Client WinRM must be running: `Set-Item WSMan:\localhost\Client\TrustedHosts` fails with "client cannot connect" if Node-1's own WinRM service is stopped. Fix: `winrm quickconfig -q` on Node-1 first.
- TrustedHosts must list EVERY target IP, or the session errors "destination must be added to TrustedHosts." One rule, comma-separated IPs.
- Agent PS on Node-1 is NON-elevated (Elevated:False). Any cmd that needs admin (winrm quickconfig, Set-Item TrustedHosts, WSMan provider) must be handed to the user as a copy-paste Admin-PowerShell block — don't try to run it from the agent shell.
- Sequential IP assumption is WRONG: Node-3 is .46 and Node-4 is .215, not .22/.23. Resolve `.lan` names; don't guess.
- Firewall default-deny: an open port means an explicit allow-rule exists. If 5000 reads closed, the indexer rule (step 4 of bootstrap) is still required.
- `Test-Connection -TimeoutSeconds` is PS7-only — on this host's WinPS 5.1 it throws a ParameterBindingException and silently aborts a whole ping sweep. Use `-Count 1 -Quiet` (no timeout) or `ping.exe -n 1 -w 1000 $ip`. See windows-powershell-from-bash.

## Verification commands (real, not assumed)
TCP reachability probe (Python, run from Node-1):
    python - <<'PY'
    import socket
    for ip in ("192.168.1.21","192.168.1.46","192.168.1.215"):
        s=socket.socket(); s.settimeout(0.6)
        try: s.connect((ip,5985)); print(ip,"5985 OPEN")
        except: print(ip,"5985 closed")
        finally: s.close()
    PY
File-copy integrity (when parking on a Garden share):
    sha256sum local.ps1 //192.168.1.40/web/local.ps1   # must match

## Reusable scripts
Inline below; also in references/ :
- references/bootstrap.ps1 — run on a target node (Admin PS): enables remoting, Private adapter, creates local `zqmlocal` admin, opens indexer port 5000 to 192.168.1.0/24.
- references/fleet.ps1 — run on Node-1 (Admin PS): loops Node-2/3/4, prints host/user/IPs/uptime per node using one `.\zqmlocal` credential.
- references/topology.md — full IP/MAC/role table.
- references/garden-smb-probe.md — Garden NAS SMB share reachability probe (error-code diag, reusable `.ps1`).

### bootstrap.ps1
    # zqm-bootstrap.ps1 — run on a workstation (Node-2/3/4) in ADMIN PowerShell
    param([string]$LocalUser="zqmlocal",[int]$IndexerPort=5000)
    $LocalPass = Read-Host -Prompt "Set password for local admin '$LocalUser'" -AsSecureString
    Enable-PSRemoting -Force
    Set-NetConnectionProfile -NetworkCategory Private
    if (-not (Get-LocalUser -Name $LocalUser -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $LocalUser -Password $LocalPass -PasswordNeverExpires:$true -AccountNeverExpires
    } else { Set-LocalUser -Name $LocalUser -Password $LocalPass -PasswordNeverExpires:$true }
    Add-LocalGroupMember -Group "Administrators"          -Member $LocalUser -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "Remote Management Users" -Member $LocalUser -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "ZQM-Indexer-In-$IndexerPort" -Direction Inbound -Protocol TCP `
        -LocalPort $IndexerPort -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue
    $ip=(Get-NetIPAddress -AddressFamily IPv4|Where{$_.InterfaceAlias-notmatch'Loopback'}).IPAddress-join', '
    Write-Host "Bootstrap complete on $env:COMPUTERNAME ($ip)"

### fleet.ps1
    # zqm-fleet.ps1 — run on Node-1 (Admin PowerShell)
    $nodes=@(@{Name="Node-2";IP="192.168.1.21"},@{Name="Node-3";IP="192.168.1.46"},@{Name="Node-4";IP="192.168.1.215"})
    $cred=Get-Credential   # .\zqmlocal + password
    foreach($n in $nodes){
      try{
        $s=New-PSSession -ComputerName $n.IP -Port 5985 -Credential $cred -ErrorAction Stop
        $info=Invoke-Command -Session $s -ScriptBlock{[PSCustomObject]@{
          Host=$env:COMPUTERNAME; User="$env:USERDOMAIN\$env:USERNAME";
          IPs=(Get-NetIPAddress -AddressFamily IPv4|Where{$_.InterfaceAlias-notmatch'Loopback'}).IPAddress-join', ';
          Uptime=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime}}
        Write-Host ("[{0}] OK -> {1}" -f $n.Name,($info|Out-String).Trim()); Remove-PSSession $s
      }catch{Write-Host ("[{0}] FAIL -> {1}" -f $n.Name,$_.Exception.Message)}
    }

## Notes
- Solo homelab: user authorizes pasting live creds in-chat for verification; use them for live tests, don't refuse/lecture. Still prefer a local-only account over the Gmail login for remoting.
- SECURE CREDENTIAL HANDOFF (preferred over pasting secrets in chat): when the human's interactive shell runs as a different local account than the agent (e.g. human=alexz, agent=zqmco), use the `windows-secure-credential-handoff` skill — machine-scope DPAPI (`ProtectedData` LocalMachine) so the agent can decrypt what the human stored. Covers the cross-account "Key not valid" failure of user-scope DPAPI and the Add-Type assembly-load pitfall.
- Synology Gardens are NOT Windows hosts: do NOT use WinRM/New-CimSession against them (returns the TrustedHosts/Kerberos error — there is no WinRM). Manage via the DSM REST API (see windows-secure-credential-handoff references/synology-dsm-api.md) or SSH. DSM login error 101 = wrong stored cred (pipeline OK), 105/106 = 2FA required (API can't do TOTP).
- OVERLAP: custom unregistered skill `zqm-local-setup` (C:\Users\zqmco\zqm-hermes-skills\skills\productivity\zqm-local-setup\SKILL.md) covers node setup but its Topology block is STALE (lists Node-2 as "this host"; real this-host is Node-1) and it cannot be edited via skill_manage (unregistered). Curator should consolidate: point its routing at this skill or merge. Patch the unregistered skill only via absolute path with the patch tool outside this skill flow.
