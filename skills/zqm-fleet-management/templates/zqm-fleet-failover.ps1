# zqm-fleet-failover.ps1 -- loop the ZQM Windows node fleet with login failover
# Run from the management host (Node-1). Uses the machine-scope DPAPI
# credential zqm-cred-node-local.json so no password is ever printed.
# For each node: tries WinRM HTTP 5985, falls back to WinRM HTTPS 5986.
param(
  [string[]]$Nodes = @("192.168.1.21","192.168.1.46","192.168.1.215"),
  [string]$CredPath = "C:\zqm\cred\zqm-cred-node-local.json"
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Security | Out-Null

if (-not (Test-Path $CredPath)) { Write-Host "NO NODE CRED FILE at $CredPath"; exit 1 }
$o = Get-Content $CredPath -Raw | ConvertFrom-Json
$enc = [Convert]::FromBase64String($o.data)
$pw = [System.Text.Encoding]::UTF8.GetString(
  [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, "LocalMachine"))
$user = $o.user
$sec = ConvertTo-SecureString $pw -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($user, $sec)
Write-Host ("Loaded node credential: " + $user + " (password not printed)")

function Try-Session($ip, $port, $cred) {
  try {
    $opt = New-PSSessionOption -UseSSL:($port -eq 5986) -SkipCACheck -SkipCNCheck
    $s = New-PSSession -ComputerName $ip -Port $port -Credential $cred -SessionOption $opt -ErrorAction Stop
    return $s
  } catch { return $null }
}

foreach ($ip in $Nodes) {
  $s = $null
  foreach ($port in @(5985, 5986)) {
    $s = Try-Session $ip $port $cred
    if ($s) { Write-Host ("$ip : CONNECTED via $port (session $($s.Id))"); break }
    else    { Write-Host ("$ip : $port failed") }
  }
  if (-not $s) { Write-Host ("$ip : ALL CHANNELS FAILED"); continue }

  $info = Invoke-Command -Session $s -ScriptBlock {
    [pscustomobject]@{
      Host = $env:COMPUTERNAME
      IP   = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' } | Select-Object -First 1).IPAddress
      WinVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
      Uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
      SSHD   = (Get-Service sshd -ErrorAction SilentlyContinue).Status
      WinRMHTTPS = (Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -like '*HTTPS*' }) -ne $null
    }
  }
  Write-Host ("   -> Host=$($info.Host)  Ver=$($info.WinVer)  Up=$($info.Uptime.ToString('dd\.hh\:mm'))  SSH=$($info.SSHD)  WinRM-HTTPS=$($info.WinRMHTTPS)")
  Remove-PSSession $s
}
