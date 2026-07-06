---
name: lan-management
description: "Use when discovering, auditing, diagnosing, or configuring devices and services on a local area network. Covers device inventory, subnet scanning, Windows workgroup deep inspection, WinRM remediation, cross-node GitHub runbook publishing, and log triage for LAN infrastructure—all local-first."
version: 1.2.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [lan, network, sysadmin, discovery, dhcp, dns, firewall, monitoring, windows, workgroup, wmi, github]
    related_skills: [hermes-agent, system-debugging, localhost-management, github-auth, github-repo-management]
---

# LAN Management

Local-first skill for discovering devices, auditing connectivity, controlling name/DHCP services, and triaging failures on a wired or wireless LAN. All recipes run against the local environment with no cloud dependencies.

## When to Use
- Adding or removing a device from the LAN and you want a fresh inventory
- A host is unreachable and you need a structured ping-traceroute-port chain
- DNS or DHCP misconfiguration after router, switch, or VM network change
- Windows workgroup nodes that need remote WMI/WinRM access or auth diagnostics
- Publishing or syncing LAN findings/reports to a private GitHub remote from Windows/Git-Bash
- Firewall rule drift between machines
- Bandwidth or uptime regression that needs a quick cross-device snapshot
- VLAN trunk changes on a managed switch

Don't use for: WAN/public-IP work, cloud VPCs, or ISP modem ISP-side diagnostics.

---

## Tooling assumptions

- Network probes: `python` socket probes, `Test-NetConnection`, `netsh`, `Get-NetTCPConnection`
- Remote management on Windows: `Get-WmiObject` / `Get-CimInstance`, `Invoke-Command`
- Git auth on Windows Git-Bash: `gh auth setup-git` plus explicit helper path when the bundled credential-manager is unavailable
- Raycasts / UIs are not required; keep all evidence in plain-text markdown under private repos

---

## Phase 1: LAN inventory

### Subnet sweep
Use raw Python TCP probes when bash `/dev/tcp` is unreliable. Cross-check with `netsh interface ipv4 show neighbors` and ARP.

Completion criterion: every .1-254 IP is labeled either alive or absent, with timestamp.

### Hostname and identity
Collect NBNS / LLMNR / mDNS names from WMI or `netsh interface ipv4 show dnsservers`. Resolve PTR when possible.

Completion criterion: one line per host with `IP`, `hostname`, `MAC`, `vendor-OUI if known`, `reachable T/F`.

### Layer-2 fingerprint
Read the local ARP/neighbor cache. For Windows:
```powershell
netsh interface ipv4 show neighbors
arp -a
```

Completion criterion: MAC vendor matches known makers; unknowns flagged for OUI lookup later.

---

## Phase 2: Connectivity diagnosis

Ordered chain for an unreachable host:

1. ICMP reachability
2. ARP resolution
3. TCP probes on expected service ports
4. SMB session probe: `net view \\host`, `net use \\host\IPC$`
5. Remote WMI/CIM with explicit credentials
6. RDP and WinRM listener check

### SMB auth semantics on Windows
- `net view \\host` returning `Access is denied` (error 5) means authenticated but lacks share-list rights. Do NOT conclude the password is wrong.
- `net use \\host\IPC$` returning `System error 67` means the admin share path is blocked or missing. It can occur even when the account is valid.
- If `net view` succeeds with no entries, the host is reachable and the credential is valid, but there are no exposed shares.

### WMI/CIM auth failure on Windows workgroup
Remote WMI/CIM with explicit credentials often returns `0x80070005` even with correct credentials. Typical cause chain:
1. Account is not in `Administrators` or `Remote Management Users` on the target.
2. Remote UAC filtering is enabled: `LocalAccountTokenFilterPolicy=0`.
3. WinRM is not enabled or the firewall rule `WINRM-HTTP-In-TCP` is disabled.
4. TrustedHosts on the client is empty in a workgroup.

Fixed sequence:
1. On the **target** admin console / RDP:
   ```powershell
   net localgroup Administrators <account> /add
   net localgroup "Remote Management Users" <account> /add
   Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord
   Enable-PSRemoting -Force
   Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -Profile Any -Enabled True
   Set-Item WSMan:\localhost\Service\AllowUnencrypted $true
   Set-Item WSMan:\localhost\Service\Auth\Basic $true
   ```
2. On the **client** (`192.168.1.21` in our environment), from an **elevated** PowerShell:
   ```powershell
   Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<target-ip>" -Force
   Set-Item WSMan:\localhost\Client\AllowUnencrypted $true
   ```
3. Re-test:
   ```powershell
   Test-WSMan -ComputerName <target-ip>
   Invoke-Command -ComputerName <target-ip> -ScriptBlock { hostname; $env:COMPUTERNAME }
   Get-WmiObject Win32_OperatingSystem -ComputerName <target-ip>
   ```

NOTE: Kerberos/SSPI will work without `-Credential` from the same machine when properly configured; explicit `-Credential` may require NTLM/Basic and works only after the above is in place.

---

## Phase 3: Cross-node management steps

Preflight:
- Run `Test-NetConnection -ComputerName <peer> -Port 445` to confirm SMB reachability.
- Run `net view \\<peer>` to confirm credential validity.
- Confirm WinRM is enabled on both nodes with `Test-WSMan -ComputerName localhost`.

Enumerating Node-2 from itself with explicit credentials:
```powershell
$p = [System.Net.NetworkCredential]::new('zqmcomputing', '<password>').SecurePassword
$c = New-Object PSCredential('zqmcomputing', $p)
Get-WmiObject Win32_ComputerSystem -ComputerName 192.168.1.21 -Credential $c
Get-WmiObject Win32_OperatingSystem -ComputerName 192.168.1.21 -Credential $c
Get-WmiObject Win32_Service -ComputerName 192.168.1.21 -Credential $c | Where-Object State -EQ 'Running'
Get-WmiObject Win32_UserAccount -ComputerName 192.168.1.21 -Credential $c -Filter "LocalAccount=True"
Get-WmiObject Win32_Group -ComputerName 192.168.1.21 -Credential $c -Filter "LocalAccount=True"
Get-WmiObject Win32_QuickFixEngineering -ComputerName 192.168.1.21 -Credential $c
```

Collect from each class:
- OS: `Caption`, `Version`, `BuildNumber`, `OSArchitecture`, `SerialNumber`, `InstallDate`, `LastBootUpTime`
- CS: `Name`, `Domain`, `Manufacturer`, `Model`, `TotalPhysicalMemory`, `NumberOfProcessors`, `NumberOfLogicalProcessors`, `UserName`
- PRODUCT: `Name`, `Vendor`, `Version`, `IdentifyingNumber`, `UUID`
- BIOS: `Manufacturer`, `SMBIOSBIOSVersion`, `SerialNumber`, `ReleaseDate`
- USERS: `Name`, `FullName`, `Disable`, `Lockout`
- GROUPS: `Name`, `Description`, `SID`

Completion criterion: all classes queried from both nodes and files written to the private runbook repo.

---

## Phase 4: Publishing findings to GitHub from Windows

### Repo topology

Private org `ZQM-Computing`:
- `zqm-localhost-findings` — cross-node findings, credential matrix, remediation
- `zqm-node-01-indexer` — Node-1 (`192.168.1.218`) runbook
- `zqm-node-02-indexer` — Node-2 (`192.168.1.21`) runbook

### Git HTTPS auth fix pattern

If `git push` over HTTPS fails with `credential-manager-core` / `git-askpass` errors in Git-Bash:
1. Run `gh auth status` to confirm `gh` is logged in.
2. Run `gh auth setup-git`.
3. Verify absolute helper:
   ```powershell
   git config --global credential.helper "'C:\\Program Files\\GitHub CLI\\gh.exe' auth git-credential"
   ```
4. Test without pushing: `git ls-remote https://github.com/<owner>/<repo>.git`
5. If it still prompts for username, do **not** loop-retry. Check `which gh` from Git-Bash; if missing, add `C:\Program Files\GitHub CLI` to PATH or use the absolute helper path above.

### Branch mismatch pattern

If `fatal: The upstream branch ... does not match the name of your current branch`:
```bash
git push origin HEAD:master
```

### Merge-conflict pattern on Windows

If `git pull` or `git merge origin/<branch>` leaves README conflict markers:
1. Prefer `git merge origin/<branch> --no-edit` over `git rebase` on Windows.
2. If conflict markers remain after `git checkout origin/<branch> -- <file>`, append local additions with `cat >> <file>` after cleanup.
3. Then `git add <file>` and `git commit -m "docs: merge README revisions"` before pushing.

Completion criterion: pushed commit appears on GitHub without `rejected` or `non-fast-forward` errors.

---

## Phase 5: Monitoring and log triage

Use WMI for remote snapshots. On the local host, prefer `Get-NetTCPConnection`, `netstat`, and `netsh advfirewall`; `Get-NetFirewallRule` may return empty on some Windows 10+/Git-Bash environments.

Completion criterion: every node has an inventory snapshot no older than the session timestamp.

---

## Phase 6: Common LAN scenarios

### NAS or host unreachable
- Check ARP, SMB ports 139/445, and `net view \\host`.
- If auth succeeds but share enumeration fails, credentials are valid but share-list permissions are restricted.

### Node indistinguishable from sibling
- If all external port/protocol fingerprints are identical, the auth boundary is the discriminator.
- Capture evidence of where the credential succeeds and where it fails; do not repeat wide scans.

### Router API unavailable
- If the router API (`192.168.1.1`) is unreachable, fall back to DHCP lease table read from the Windows side: `Get-DhcpServerv4Lease` requires the DHCP Server role and is typically unavailable on workstations.
- DHCP role unavailability is **not** a durable failure; the user can install the role or read from the router config.

---

## Repositories

Local canonical workflows, runbooks, and evidence for the ZQM LAN:

- `zqm-localhost-findings` — cross-node findings, credential matrix, broadcast summary
- `zqm-node-01-indexer` — Node-1 runbook
- `zqm-node-02-indexer` — Node-2 runbook

Private org: `ZQM-Computing`. Cloning requires GitHub auth; if `git push` over HTTPS fails with credential-manager/askpass errors, use GitHub CLI auth helper:

```powershell
gh auth setup-git
```

If that still fails, switch remote protocol to SSH.

---

## Common pitfalls

1. Running `arp-scan` without the correct interface. Always capture the gateway-facing interface first via `ip route show default`.
2. Blindly pinging /24 when the LAN is /16 or bundled subnets. Detect the mask with `ip -4 addr show` before sweeping.
3. Trusting mDNS only—IoT printers and old Windows hosts often drop mDNS. Complement with ARP + reverse-DNS.
4. Forgetting to stop monitoring after starting (leaves `watch`, `tcpdump`, or `iperf3` in background). Enforce a stop step or tmux session teardown.
5. Ignoring IPv6—modern LANs often run SLAAC. Detect with `ip -6 addr show scope global`.
6. SSH key sprawl—use a dedicated `~/.ssh/lan` config host block so blanket `BatchMode=yes` doesn't lock you out of a single misconfigured host.
7. Remote WMI/CIM enumeration often fails with `0x80070005` even with correct credentials. Typical causes: Remote UAC filtering, missing WinRM, or the account not being in `Administrators` / `Remote Management Users` on the target. Run the full remediation block above instead of retrying the same WMI query.
8. `net view \\host` returning `Access is denied` (error 5) means the account authenticated but lacks share-list rights. `net use \\host\IPC$` returning `System error 67` means the admin share path is blocked or missing. These are not definitive indicators of bad credentials.
9. `Get-NetFirewallRule` may return empty or exit 1 from Git-Bash on some Windows builds; prefer `netsh advfirewall`, `netstat`, or `Get-NetTCPConnection`.
10. When publishing findings, **do not store raw credentials**. Keep the credential matrix table with status only; rotate after disclosure.

---

## Verification Checklist

- [ ] Alive IP list collected and timestamped
- [ ] Hostname/MAC/identity table complete
- [ ] Connectivity chain executed for each unreachable host
- [ ] SMB auth semantics documented for each node
- [ ] WMI/CIM failure cause documented with remediation state
- [ ] WinRM state captured for both nodes
- [ ] Runbooks committed to private repos
- [ ] Git HTTPS auth verified working on Windows
- [ ] No raw passwords retained in any pushed markdown file

## Secret Hygiene Policy

Never store live credentials in committed files. If a secret was committed to history:
1. Rotate the exposed credential on every affected system.
2. Operate on a fresh clone.
3. Rewrite history with `git filter-repo` and push with `--force-with-lease`.
4. Retire or replace the old working tree so the polluted history is not reused.

See `zqm-github-management/references/history-purge.md` for the exact Windows runbook.

Completion criterion: `git log --all -S '<secret>'` returns empty, remote `HEAD` matches the rewritten clone, and the old working directory has been replaced.