# zqm-fleet.ps1 — manage Node-2/3/4 from Node-1
# Run on Node-1 (Admin PowerShell). Uses one local `.\zqmlocal` credential for
# all three nodes (set the SAME password on each via zqm-bootstrap.ps1).
# Prereq: Node-1 TrustedHosts must include all three IPs:
#   Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force

$nodes = @(
  @{Name="Node-2"; IP="192.168.1.21"},
  @{Name="Node-3"; IP="192.168.1.46"},
  @{Name="Node-4"; IP="192.168.1.215"}
)
$cred = Get-Credential   # User: .\zqmlocal  | Pass: the local acct password
foreach ($n in $nodes) {
  try {
    $s = New-PSSession -ComputerName $n.IP -Port 5985 -Credential $cred -ErrorAction Stop
    $info = Invoke-Command -Session $s -ScriptBlock {
      [PSCustomObject]@{
        Host = $env:COMPUTERNAME
        User = "$env:USERDOMAIN\$env:USERNAME"
        IPs  = (Get-NetIPAddress -AddressFamily IPv4 | Where InterfaceAlias -notmatch Loopback).IPAddress -join ", "
        Uptime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
      }
    }
    Write-Host ("[{0}] OK  -> {1}" -f $n.Name, ($info | Out-String).Trim())
    Remove-PSSession $s
  }
  catch {
    Write-Host ("[{0}] FAIL -> {1}" -f $n.Name, $_.Exception.Message)
  }
}
