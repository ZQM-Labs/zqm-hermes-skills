# fleet.ps1 — run ON Node-1 (192.168.1.218), Admin PowerShell.
# Probes WinRM reachability and pulls host/IP/uptime from every ZQM node.
# Prompts once for `.\zqmlocal` (must match the account + password created by
# bootstrap.ps1 on each target, with the SAME password across nodes).

$nodes = @(
    @{Name="Node-2"; IP="192.168.1.21"},
    @{Name="Node-3"; IP="192.168.1.46"},
    @{Name="Node-4"; IP="192.168.1.215"}
)

# Ensure Node-1 itself trusts the targets (idempotent)
Set-Item WSMan:\localhost\Client\TrustedHosts `
    -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force -ErrorAction SilentlyContinue

$cred = Get-Credential   # User: .\zqmlocal | Pass: the local acct password

foreach ($n in $nodes) {
    # quick TCP pre-check so a dead host fails fast instead of hanging
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient($n.IP, 5985)
        $tcp.Close()
    } catch { $tcp = $null }

    if (-not $tcp) {
        Write-Host ("[{0}] UNREACHABLE (5985 closed) -> {1}" -f $n.Name, $n.IP)
        continue
    }
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
        Write-Host ("[{0}] OK -> {1}" -f $n.Name, ($info | Out-String).Trim())
        Remove-PSSession $s
    } catch {
        Write-Host ("[{0}] FAIL -> {1}" -f $n.Name, $_.Exception.Message)
    }
}
