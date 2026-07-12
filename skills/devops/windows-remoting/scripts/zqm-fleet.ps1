# zqm-fleet.ps1 — run on the CLIENT (Node-1) in Admin PowerShell.
# Health-checks / connects to all remote nodes in one loop using a single
# .\zqmlocal credential (requires each node to have been bootstrapped with
# templates/zqm-bootstrap.ps1 using the SAME username/password).

$nodes = @(
  @{Name="Node-2"; IP="192.168.1.21"},
  @{Name="Node-3"; IP="192.168.1.46"},
  @{Name="Node-4"; IP="192.168.1.215"}
)
# Pre-req on Node-1: Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force
$cred = Get-Credential   # User: .\zqmlocal | Pass: the local acct password

foreach ($n in $nodes) {
  try {
    $s = New-PSSession -ComputerName $n.IP -Port 5985 -Credential $cred -ErrorAction Stop
    $info = Invoke-Command -Session $s -ScriptBlock {
      [PSCustomObject]@{
        Host   = $env:COMPUTERNAME
        User   = "$env:USERDOMAIN\$env:USERNAME"
        IPs    = (Get-NetIPAddress -AddressFamily IPv4 | Where InterfaceAlias -notmatch Loopback).IPAddress -join ", "
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
