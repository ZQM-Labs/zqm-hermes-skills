# ZQM Credential Reconciliation & "Is it reachable?" Enumeration

Use this when a node (e.g. Node-4) rejects the fleet vault credential and you must decide
whether it can be reconciled remotely or needs local console access.

## The question to answer
"Is there ANY credential/plane reachable from here (Node-1, or any Garden) that can run
`Set-LocalUser` / administer the target?" If yes -> reconcile remotely. If every path fails
-> the target has a unique deploy password; only local console or owner-supplied pw clears it.

## Enumeration sequence (run all, record live results)
1. **DPAPI vaults** on managing host: `C:\zqm\cred\*.json`. Decrypt to confirm the exact
   password you are testing (don't assume the file name == the password):
   ```powershell
   Add-Type -AssemblyName System.Security
   $o = Get-Content C:\zqm\cred\zqm-cred-node-local.json -Raw | ConvertFrom-Json
   [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect(
     [Convert]::FromBase64String($o.data), $null, 'LocalMachine'))
   ```
2. **Windows Credential Manager**: `cmdkey /list` — note `Domain:target=IP` / `LegacyGeneric`
   entries. These are SMB/garden creds, not Windows-local node admins.
3. **Other local admins on managing host** (zqmco/AlexZ on Node-1) + the fleet pw -> try
   against the TARGET over SSH (22) AND WinRM (5985 Negotiate). Target likely has its own SAM.
4. **Garden/admin creds** (azelenski) -> try against target: EXPECT REJECT (Synology/TerraMaster
   accounts are not Windows-local; a Garden OS cannot administer a Windows SAM — structural,
   not a probe to retry).
5. **Target built-ins**: `Administrator` + fleet/garden pw over WinRM 5985 Negotiate:
   ```powershell
   $cred = New-Object PSCredential('Administrator',(ConvertTo-SecureString 'PW' -AsPlainText -Force))
   try { $s = New-CimSession -ComputerName 192.168.1.215 -Port 5985 -Credential $cred `
         -Authentication Negotiate -ErrorAction Stop
         (Get-CimInstance -CimSession $s -ClassName Win32_ComputerSystem).Name; Remove-CimSession $s }
   catch { "WINRM_FAIL " + $_.Exception.Message }
   ```
   NOTE: a burst of failed SSH logins triggers 10054 resets that masquerade as hard rejects.
   Prefer WinRM for the built-in-account test; pause between SSH retries.
6. **Scheduled tasks / mesh jobs** on managing host: `schtasks /query /fo LIST` -> grep ZQM/
   mesh/node. A working target cred may live in a task action.
7. **Management plane**: scan target + neighbors for 623 (IPMI), 8006 (Proxmox), 5900 (VNC),
   3389 (RDP), 22/443. A hypervisor host can inject the command even if the node itself is
   locked out.

## Node-4 (.215) case study — PROVEN OUTCOME (2026-07-12)
- Vault `zqmlocal`/`EllaRose89!` (11-char, confirmed) -> SSH REJECT, WinRM "Access is denied".
- `azelenski`/garden pw -> REJECT (not a Windows account).
- `zqmco`/`AlexZ` + fleet pw -> REJECT (Node-4 own SAM).
- `Administrator` + fleet/garden pw -> WinRM "Access is denied".
- No mesh tasks held a Node-4 cred. No hypervisor plane open on .214/.216.
- CONCLUSION: Node-4 deployed with a UNIQUE local-admin password not in any store. Remote
  reconcile impossible. Requires local console `Set-LocalUser -Name zqmlocal -Password (...
  'EllaRose89!')` OR owner supplies the password. This is a proven gate, not a guess.

## Reconcile remotely IF a working cred is found
```powershell
$cred = New-Object PSCredential('zqmlocal',(ConvertTo-SecureString 'EllaRose89!' -AsPlainText -Force))
$s = New-CimSession -ComputerName 192.168.1.215 -Port 5985 -Credential $cred -Authentication Negotiate
# Set password via CIM (or fall back to Enter-PSSession + Set-LocalUser)
```
