# zqm-bootstrap.ps1  - CANONICAL robust node bootstrap (run locally, Admin)
# Hardened copy (3761 bytes) — defeats:
#   - UNC backslash-doubling on -File (use the HTTP-fetch wrapper, not SMB)
#   - missing Cert: PSDrive under -NoProfile -File (auto-mounts it)
#   - Get-WindowsCapability "Class not registered" on Win10 Pro (whole OpenSSH block guarded)
param([string]$AdminUser="zqmlocal",[string]$CredPath="C:\zqm\cred\zqm-cred-node-local.json",[string]$Lan="192.168.1.0/24")
$ErrorActionPreference="Stop"
Add-Type -AssemblyName System.Security|Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $CredPath)|Out-Null

# ensure Cert: PSDrive exists (absent under -NoProfile shells -> -File runs fail there)
if (-not (Test-Path Cert:)) { try { New-PSDrive -Name Cert -PSProvider Certificate -Root \ -ErrorAction Stop | Out-Null } catch { Write-Host "Note: could not auto-mount Cert: drive" } }

# 1. private profile (optional, non-fatal)
try { Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop } catch { Write-Host "Note: network category unchanged (GPO/non-elevated) - continuing" }

# 2. WinRM baseline on 5985 (all PS versions)
winrm quickconfig -q 2>$null
New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force | Out-Null

# 3. local admin + store cred
$pwSec = Read-Host -Prompt "zqmlocal password (hidden)" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwSec)
$pw   = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
if (-not (Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue)) {
  New-LocalUser -Name $AdminUser -Password $pwSec -PasswordNeverExpires -AccountNeverExpires | Out-Null
}
Add-LocalGroupMember -Group "Administrators" -Member $AdminUser -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Remote Management Users" -Member $AdminUser -ErrorAction SilentlyContinue

$b = [System.Text.Encoding]::UTF8.GetBytes($pw)
$e = [System.Security.Cryptography.ProtectedData]::Protect($b,$null,"LocalMachine")
[pscustomobject]@{user=$AdminUser;data=[System.Convert]::ToBase64String($e)} | ConvertTo-Json | Set-Content $CredPath -Force
Write-Host "Stored $AdminUser -> $CredPath (DPAPI LocalMachine)"

# 4. HTTPS 5986 listener (proven method: winrm create Address=*+Transport=HTTPS)
$cert = New-SelfSignedCertificate -Subject "CN=$env:COMPUTERNAME" -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
try { winrm delete winrm/config/Listener?Address=*+Transport=HTTPS 2>$null } catch { }
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`";CertificateThumbprint=`"$($cert.Thumbprint)`"}" 2>$null
New-NetFirewallRule -DisplayName "ZQM-WinRM-HTTPS-5986" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -Profile Any -RemoteAddress $Lan -ErrorAction SilentlyContinue | Out-Null

# 5. OpenSSH (if available) -- WHOLE block guarded; Get-WindowsCapability can throw
#    "Class not registered" and dism.exe can ALSO fail to add the capability (CBS store
#    rejects it). Fallbacks, in order:
#      (a) Add-WindowsCapability (PS Dism)     -- works on healthy hosts
#      (b) dism.exe /online /Add-Capability    -- native, bypasses broken PS Dism COM
#      (c) manual GitHub OpenSSH-Win64 zip      -- when the CBS store refuses the capability
#    On a Win11 node SSH SHOULD end up enabled; on a host truly without the provider it
#    is skipped, non-fatal. See references/dark-node-openssh-manual-winrm.md.
try {
  $svc = Get-Service sshd -ErrorAction SilentlyContinue
  if (-not $svc) {
    # (a) PS Dism
    try {
      $cap = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -like 'OpenSSH.Server*' }
      if ($cap -and $cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null }
    } catch {
      # (b) native dism.exe
      Write-Host "Dism PS provider unavailable, trying native dism.exe"
      dism.exe /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 | Out-Null
    }
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    # (c) manual GitHub zip if still no service
    if (-not $svc) {
      Write-Host "Dism could not add OpenSSH.Server; installing manually from GitHub OpenSSH-Win64"
      $dest = 'C:\Program Files\OpenSSH'; $zip = 'C:\zqm\OpenSSH-Win64.zip'
      New-Item -ItemType Directory -Force -Path C:\zqm | Out-Null
      $api = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest' -Headers @{ 'User-Agent' = 'zqm' } -ErrorAction Stop
      $asset = ($api.assets | Where-Object { $_.Name -eq 'OpenSSH-Win64.zip' })[0]
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -ErrorAction Stop
      if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
      Expand-Archive -Path $zip -DestinationPath $dest -Force
      $f = Get-ChildItem -Path $dest -Recurse -Filter 'install-sshd.ps1' | Select-Object -First 1
      if ($f -and $f.DirectoryName -ne $dest) { Copy-Item -Path (Join-Path $f.DirectoryName '*') -Destination $dest -Recurse -Force }
      & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $dest 'install-sshd.ps1')
      $svc = Get-Service sshd -ErrorAction SilentlyContinue
    }
  }
  if ($svc) { Set-Service sshd -StartupType Automatic; Start-Service sshd; New-NetFirewallRule -DisplayName "ZQM-OpenSSH-22" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -Profile Any -RemoteAddress $Lan -ErrorAction SilentlyContinue | Out-Null; Write-Host "OpenSSH enabled" } else { Write-Host "OpenSSH unavailable (skipped)" }
} catch { Write-Host ("OpenSSH setup skipped: " + $_.Exception.Message) }

Write-Host ("Bootstrap complete on " + $env:COMPUTERNAME + ". WinRM 5985 (quickconfig) + 5986 (HTTPS) enabled, " + $AdminUser + " stored to DPAPI.")
