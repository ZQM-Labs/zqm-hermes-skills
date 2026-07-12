# zqm-fleet.ps1 — manage Node-2/3/4 from Node-1
# Run on Node-1 in ADMIN PowerShell. Uses one `.\zqmlocal` credential for all
# three nodes (set the SAME local account + password on each target via bootstrap.ps1).

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
        IPs  = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch 'Loopback'}).IPAddress -join ", "
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
