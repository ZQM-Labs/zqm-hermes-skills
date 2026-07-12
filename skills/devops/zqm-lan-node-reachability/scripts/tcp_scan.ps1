# tcp_scan.ps1 — curated TCP port scanner (PowerShell .NET TcpClient).
# Reusable port-discovery for LAN nodes when nmap is absent.
# Run from MSYS bash:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:/path/tcp_scan.ps1' <IP> [timeoutMs]
# NOTE: MSYS strips backslashes — ALWAYS use forward slashes in the -File path.
# NOTE: never name the target variable $host (reserved/read-only in PowerShell); use $target.

$target = if ($args.Count -ge 1) { $args[0] } else { "192.168.1.46" }
$timeoutMs = if ($args.Count -ge 2) { [int]$args[1] } else { 300 }

# Curated common + service-specific ports (not a full 1-65535 sweep).
$ports = @(
    20,21,22,23,25,53,80,88,110,111,135,137,139,143,389,443,445,465,514,587,
    631,636,873,993,995,1025,1026,1027,1028,1029,1080,1099,1158,1352,1433,1521,
    1723,2049,2121,3128,3306,3389,3690,4000,4040,4500,5000,5432,5500,5555,5631,
    5900,5985,5986,6000,6001,6379,7001,7002,7070,8000,8001,8008,8009,8080,8081,
    8082,8083,8088,8089,8090,8100,8443,8888,9000,9001,9042,9090,9092,9200,9300,
    9999,10000,11211,11434,11500,11601,12701,14000,15672,18080,18701,19000,20000,
    27017,27018,27019,28015,28695,30000,31001,32001,33848,40000,45000,49152,50000,
    50060,50070,50075,50470,50500,50501,51000,51413,52000,54321,55000,55432,58000,
    60000,61000,62078,63790,64000
)

$open = @()
foreach ($p in $ports) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect($target, $p, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($timeoutMs, $false)
        if ($ok -and $tcp.Connected) {
            $open += $p
            Write-Host "OPEN  $p"
        }
    } catch {}
    finally {
        try { $tcp.Close() } catch {}
    }
}
Write-Host "=== SCAN COMPLETE ==="
Write-Host "OPEN_PORTS: $($open -join ',')"
