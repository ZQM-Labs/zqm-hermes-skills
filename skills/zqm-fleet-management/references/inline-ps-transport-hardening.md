# Transport-safe inline PowerShell (for paste delivery into hostile terminals)

## The problem
When you hand a user a long PowerShell one-liner to paste into THEIR console (or route
through a chat/transport that mangles special chars), these characters commonly get
stripped/corrupted:
  - `$_`  ->  `$`        (the `$_` automatic variable loses its underscore -> `$.Foo` -> parse error)
  - `*`   (bare, e.g. inside a `winrm` string `Address=*+Transport=HTTPS`) -> dropped
  - backtick escapes inside a double-quoted string (e.g. `` `" `` ) -> mangled

Symptom the user sees: `Where-Object : The term '$.IPAddress' is not recognized` or
`Address=+Transport=HTTPS` (missing `*`).

This happened on the ZQM Node-3/Node-4 bootstrap: the inline `zqm-bootstrap-inline.ps1`
used `Where-Object { $_.IPAddress -like '192.168.*' ... }` and
`winrm create ... Address=*+Transport=HTTPS` - both broke on paste.

## The fix - write inline PS with NO `$_`, NO bare `*`, NO backticks
1. Avoid `$_` entirely. Replace `Get-X | Where-Object { $_.Prop ... }` with either:
   - scriptblock-free `Where-Object` syntax:  `Get-X | Where-Object Prop -like "value*"`
   - or avoid the pipeline: `Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private`
     (passes objects straight through - no `$_` needed at all).
2. Avoid `winrm create/delete ... Address=*+Transport=HTTPS`. Use the native PowerShell
   cmdlet `New-WSManInstance` instead - no shell-escaping, no bare `*`:
   ```powershell
   Get-ChildItem WSMan:\localhost\Listener | Where-Object Keys -like "*HTTPS*" | Remove-Item -Recurse -Force
   New-WSManInstance -ResourceURI winrm/config/Listener `
     -SelectorSet @{Address="*"; Transport="HTTPS"} `
     -ValueSet @{Hostname=$env:COMPUTERNAME; CertificateThumbprint=$cert.Thumbprint}
   ```
3. Avoid backtick-escaped quotes. Build strings with `+` and `$env:` instead:
   `-Subject ("CN="+$env:COMPUTERNAME)` instead of `` -Subject "CN=`"$env:COMPUTERNAME`"" ``.
4. Prefer scriptblock-free `Where-Object Name -like "OpenSSH.Server*"` over
   `Where-Object { $_.Name -like ... }`.

## Verified hardened inline bootstrap (ZQM node, single paste)
Paste as ONE line into Admin PowerShell on a dark node (no file, no share needed):

```
$ErrorActionPreference="Stop"; Add-Type -AssemblyName System.Security|Out-Null; $AdminUser="zqmlocal"; $CredPath="C:\zqm\cred\zqm-cred-node-local.json"; New-Item -ItemType Directory -Force -Path (Split-Path $CredPath)|Out-Null; Get-NetConnectionProfile|Set-NetConnectionProfile -NetworkCategory Private; Enable-PSRemoting -Force|Out-Null; New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force|Out-Null; $pwSec=Read-Host -Prompt "zqmlocal password (hidden)" -AsSecureString; $bstr=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwSec); $pw=[System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr); if(-not(Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue)){ New-LocalUser -Name $AdminUser -Password $pwSec -PasswordNeverExpires -AccountNeverExpires|Out-Null }; Add-LocalGroupMember -Group "Administrators" -Member $AdminUser -ErrorAction SilentlyContinue; Add-LocalGroupMember -Group "Remote Management Users" -Member $AdminUser -ErrorAction SilentlyContinue; $b=[System.Text.Encoding]::UTF8.GetBytes($pw); $e=[System.Security.Cryptography.ProtectedData]::Protect($b,$null,"LocalMachine"); [pscustomobject]@{user=$AdminUser;data=[System.Convert]::ToBase64String($e)}|ConvertTo-Json|Set-Content $CredPath -Force; $cert=New-SelfSignedCertificate -Subject ("CN="+$env:COMPUTERNAME) -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My; Get-ChildItem WSMan:\localhost\Listener|Where-Object Keys -like "*HTTPS*"|Remove-Item -Recurse -Force; New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{Address="*";Transport="HTTPS"} -ValueSet @{Hostname=$env:COMPUTERNAME;CertificateThumbprint=$cert.Thumbprint}; New-NetFirewallRule -DisplayName "ZQM-WinRM-HTTPS-5986" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue|Out-Null; $cap=Get-WindowsCapability -Online|Where-Object Name -like "OpenSSH.Server*"; if($cap -and $cap.State -ne "Installed"){ try{ Add-WindowsCapability -Online -Name $cap.Name|Out-Null }catch{} }; $svc=Get-Service sshd -ErrorAction SilentlyContinue; if($svc){ Set-Service sshd -StartupType Automatic; Start-Service sshd; New-NetFirewallRule -DisplayName "ZQM-OpenSSH-22" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue|Out-Null; Write-Host "OpenSSH enabled" }else{ Write-Host "OpenSSH unavailable (skipped)" }; Write-Host ("Bootstrap complete on "+$env:COMPUTERNAME)
```

## Pre-delivery check (agent runs this before sending ANY inline PS)
```powershell
$c = (Get-Content <inlinefile> -Raw)
if ($c.Contains("$_"))              { "WARN contains `$_" }
if ($c.Contains("winrm create"))    { "WARN uses winrm create (bare * risk)" }
if ($c.Contains("*+Transport"))     { "WARN bare *+Transport" }
$null = [System.Management.Automation.PSParser]::Tokenize($c, [ref]$null)  # throws on syntax error
```
If any WARN fires, rewrite before handing over. A staged `.ps1` file is always safer than
inline - only use inline when the user's session can't reach the share (dark node) AND no
local copy is present.
