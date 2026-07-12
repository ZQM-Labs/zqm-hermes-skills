# Inline PowerShell — Transport Hardening (for paste into user's console / chat)

## Problem (observed 2026-07-10)
When a long PowerShell one-liner is handed to the user to paste into their own
console (the only execution path for "dark" nodes with no remote reach), the
transport corrupted it:
- `$_`  →  `$`   (the underscore was dropped → `$.IPAddress` → CommandNotFound)
- `*`   →  (gone) in `Address=*+Transport=HTTPS` → became `Address=+Transport=HTTPS`
- backtick-escaped `"` inside a `winrm create ... "@{...}"` string got mangled

Both Node-3 and Node-4 failed identically with `The term '$.IPAddress' is not
recognized`. The SCRIPT LOGIC WAS FINE — only the bytes in transit broke.

## Rule: write inline PS so NO fragile character survives transport
1. **No `$_`.** Replace `Where-Object { $_.X ... }` with a piped cmdlet that
   takes a property name, e.g.:
   `Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private`
   (sets ALL profiles Private — fine for a single-homed workgroup node).
2. **No bare `*`.** Avoid wildcard literals that get stripped. For WSMan
   listener removal prefer a scoped removal or accept the empty-pipeline no-op.
3. **Avoid `winrm` CLI (shell-escaping nightmare).** Use native PS:
   ```powershell
   Get-ChildItem WSMan:\localhost\Listener | Where-Object Keys -like "*HTTPS*" | Remove-Item -Recurse -Force
   New-WSManInstance -ResourceURI winrm/config/Listener `
       -SelectorSet @{Address="*";Transport="HTTPS"} `
       -ValueSet @{Hostname=$env:COMPUTERNAME;CertificateThumbprint=$cert.Thumbprint}
   ```
   (When shipping as a single inline line, DROP the backtick continuations and
   write it space-separated on one line — backticks also get mangled.)
4. **No backtick escapes.** Write as one compact line; let `;` separate
   statements. Avoid `"` inside `"` — use concatenation with `+` if needed
   (e.g. `("CN="+$env:COMPUTERNAME)`).
5. **Prefer a file.** If the user's session can reach a LOCAL path, point them
   at `C:\Users\zqmco\zqm-bootstrap-inline.ps1` (native backslashes work in
   their PS) instead of a giant inline blob. Only the agent's `bash`/`cp` can
   use the `\\192.168.1.40\web` UNC — the user's `alexz` session cannot.

## Verified transport-hardened inline (Node bootstrap, single line)
Paste as ONE line into Admin PowerShell. Prompts for the `zqmlocal` password
(typing hidden). Uses NO `$_`, NO bare `*`, NO backticks.

```
$ErrorActionPreference="Stop"; Add-Type -AssemblyName System.Security|Out-Null; $AdminUser="zqmlocal"; $CredPath="C:\zqm\cred\zqm-cred-node-local.json"; New-Item -ItemType Directory -Force -Path (Split-Path $CredPath)|Out-Null; Get-NetConnectionProfile|Set-NetConnectionProfile -NetworkCategory Private; Enable-PSRemoting -Force|Out-Null; New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force|Out-Null; $pwSec=Read-Host -Prompt "zqmlocal password (hidden)" -AsSecureString; $bstr=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwSec); $pw=[System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr); if(-not(Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue)){ New-LocalUser -Name $AdminUser -Password $pwSec -PasswordNeverExpires -AccountNeverExpires|Out-Null }; Add-LocalGroupMember -Group "Administrators" -Member $AdminUser -ErrorAction SilentlyContinue; Add-LocalGroupMember -Group "Remote Management Users" -Member $AdminUser -ErrorAction SilentlyContinue; $b=[System.Text.Encoding]::UTF8.GetBytes($pw); $e=[System.Security.Cryptography.ProtectedData]::Protect($b,$null,"LocalMachine"); [pscustomobject]@{user=$AdminUser;data=[System.Convert]::ToBase64String($e)}|ConvertTo-Json|Set-Content $CredPath -Force; $cert=New-SelfSignedCertificate -Subject ("CN="+$env:COMPUTERNAME) -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My; Get-ChildItem WSMan:\localhost\Listener|Where-Object Keys -like "*HTTPS*"|Remove-Item -Recurse -Force; New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{Address="*";Transport="HTTPS"} -ValueSet @{Hostname=$env:COMPUTERNAME;CertificateThumbprint=$cert.Thumbprint}; New-NetFirewallRule -DisplayName "ZQM-WinRM-HTTPS-5986" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue|Out-Null; $cap=Get-WindowsCapability -Online|Where-Object Name -like "OpenSSH.Server*"; if($cap -and $cap.State -ne "Installed"){ try{ Add-WindowsCapability -Online -Name $cap.Name|Out-Null }catch{} }; $svc=Get-Service sshd -ErrorAction SilentlyContinue; if($svc){ Set-Service sshd -StartupType Automatic; Start-Service sshd; New-NetFirewallRule -DisplayName "ZQM-OpenSSH-22" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue|Out-Null; Write-Host "OpenSSH enabled" }else{ Write-Host "OpenSSH unavailable (skipped)" }; Write-Host ("Bootstrap complete on "+$env:COMPUTERNAME)
```

## Post-mortem check (before handing ANY inline PS to the user)
Run a quick scan on the string for the three fragile tokens and refuse to ship
if present: contains `$_` → rewrite; contains `winrm create` → use New-WSManInstance;
contains backtick `` ` `` → join to one line.
