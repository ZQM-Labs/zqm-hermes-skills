# zqm-bootstrap-failover.ps1  -- ZQM node bootstrap WITH login failover
# Run LOCALLY on a node in Admin PowerShell.
# Enables: PSRemoting (5985), WinRM-HTTPS (5986), OpenSSH (22),
# creates local admin $AdminUser, and auto-stores its password to
# machine-scope DPAPI (C:\zqm\cred\*.json) so the agent can loop the fleet
# WITHOUT the password ever entering chat.
# Non-interactive: if the DPAPI cred file already exists, it is used instead
# of prompting. Otherwise you are prompted (typing hidden).
param(
  [string]$AdminUser = "zqmlocal",
  [string]$CredPath  = "C:\zqm\cred\zqm-cred-node-local.json",
  [string]$IndexPort = "5000",
  [string]$Lan       = "192.168.1.0/24",
  [switch]$NoSSH,
  [switch]$NoWinRMHTTPS
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Security | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $CredPath) | Out-Null

# 1. set LAN adapter to Private
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -and $_.InterfaceAlias -notmatch 'Loopback' } | Select-Object -First 1)
if ($ip) {
  $nic = Get-NetConnectionProfile -InterfaceIndex $ip.InterfaceIndex -ErrorAction SilentlyContinue
  if ($nic -and $nic.NetworkCategory -ne 'Private') {
    Set-NetConnectionProfile -InterfaceIndex $ip.InterfaceIndex -NetworkCategory Private
  }
}

# 2. WinRM baseline (HTTP 5985) + workgroup token filter
Enable-PSRemoting -Force | Out-Null
New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System `
  -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force | Out-Null

# 3. resolve password (non-interactive if DPAPI file exists, else prompt)
$pwPlain = $null
if (Test-Path $CredPath) {
  $o = Get-Content $CredPath -Raw | ConvertFrom-Json
  $enc = [Convert]::FromBase64String($o.data)
  $pwPlain = [System.Text.Encoding]::UTF8.GetString(
    [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, "LocalMachine"))
  $AdminUser = $o.user
  Write-Host "Using stored credential for: $AdminUser (password not printed)"
} else {
  $pwSec = Read-Host -Prompt "Enter password for local admin [$AdminUser]" -AsSecureString
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwSec)
  $pwPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}

# 4. create admin + groups
$pwSec2 = ConvertTo-SecureString $pwPlain -AsPlainText -Force
if (-not (Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue)) {
  New-LocalUser -Name $AdminUser -Password $pwSec2 -PasswordNeverExpires -AccountNeverExpires | Out-Null
  Write-Host "Created local user: $AdminUser"
}
Add-LocalGroupMember -Group "Administrators"          -Member $AdminUser -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Remote Management Users" -Member $AdminUser -ErrorAction SilentlyContinue

# 5. store to machine-scope DPAPI (agent consumption, no chat secret)
$b = [System.Text.Encoding]::UTF8.GetBytes($pwPlain)
$e = [System.Security.Cryptography.ProtectedData]::Protect($b, $null, "LocalMachine")
[pscustomobject]@{ user = $AdminUser; data = [Convert]::ToBase64String($e) } | ConvertTo-Json | Set-Content $CredPath -Force
Write-Host "Stored $AdminUser credential (DPAPI LocalMachine) -> $CredPath"

# 6. indexer / app port (LAN-scoped)
New-NetFirewallRule -DisplayName "ZQM-Index-$IndexPort" -Direction Inbound -LocalPort $IndexPort -Protocol TCP `
  -Action Allow -Profile Private -RemoteAddress $Lan -ErrorAction SilentlyContinue | Out-Null

# 7. FAILVOER A: WinRM HTTPS 5986 (self-signed cert + listener)
if (-not $NoWinRMHTTPS) {
  try {
    $cert = New-SelfSignedCertificate -Subject "CN=$env:COMPUTERNAME" `
      -DnsName $env:COMPUTERNAME, $ip.IPAddress -CertStoreLocation Cert:\LocalMachine\My
    $thumb = $cert.Thumbprint
    winrm delete winrm/config/Listener?Address=*+Transport=HTTPS 2>$null
    winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`";CertificateThumbprint=`"$thumb`"}" 2>$null
    New-NetFirewallRule -DisplayName "ZQM-WinRM-HTTPS-5986" -Direction Inbound -LocalPort 5986 -Protocol TCP `
      -Action Allow -Profile Private -RemoteAddress $Lan -ErrorAction SilentlyContinue | Out-Null
    Write-Host "WinRM HTTPS listener on 5986 (self-signed, thumb $thumb)"
  } catch { Write-Host ("WARN: WinRM-HTTPS setup failed: " + $_.Exception.Message) }
}

# 8. FAILVOER B: OpenSSH Server 22
if (-not $NoSSH) {
  $cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
  if ($cap -and $cap.State -ne 'Installed') {
    try { Add-WindowsCapability -Online -Name $cap.Name | Out-Null } catch { Write-Host "WARN: OpenSSH install failed" }
  }
  $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
  if ($svc) {
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd
    New-NetFirewallRule -DisplayName "ZQM-OpenSSH-22" -Direction Inbound -LocalPort 22 -Protocol TCP `
      -Action Allow -Profile Private -RemoteAddress $Lan -ErrorAction SilentlyContinue | Out-Null
    Write-Host "OpenSSH Server enabled on 22"
  } else {
    Write-Host "OpenSSH Server capability not available on this Windows edition (skipped)"
  }
}

Write-Host "Bootstrap complete on $env:COMPUTERNAME ($($ip.IPAddress))"
