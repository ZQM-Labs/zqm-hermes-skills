# probe_lan_ports.ps1 — READ-ONLY LAN external-exposure sweep.
# Proves the REAL external surface by probing peer hosts (not just loopback).
# No elevation needed. Use after closing a service on one node to confirm the
# FLEET is actually closed (a single-host fix does NOT close peers — see P9).
#
# Edit the $peers + $ports arrays, then:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/probe_lan_ports.ps1
$out = "C:\Users\zqmco\swarm\2026-07-11_fleet_audit\probe_lan_ports.txt"
$peers = @(
    @{ip='192.168.1.21';  name='Node-2'},
    @{ip='192.168.1.46';  name='Node-3'},
    @{ip='192.168.1.215'; name='Node-4'},
    @{ip='192.168.1.218'; name='Self (Node-1)'}
)
$ports = @(22, 135, 139, 445, 3389, 5985, 5986, 11434)
function Probe($ip, $port) {
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar = $tcp.BeginConnect($ip, $port, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(2000)
        if ($ok -and $tcp.Connected) { return 'OPEN' } else { return 'closed' }
    } catch { return 'closed' }
    finally { if ($tcp) { $tcp.Close() } }
}
Add-Content -Path $out -Value ("=== LAN external-exposure sweep " + (Get-Date) + " ===")
foreach ($p in $peers) {
    Add-Content -Path $out -Value ("--- " + $p.name + " (" + $p.ip + ") ---")
    foreach ($port in $ports) {
        $r = Probe $p.ip $port
        Add-Content -Path $out -Value ("  {0,6} -> {1}" -f $port, $r)
    }
}
Add-Content -Path $out -Value "=== sweep done ==="
Write-Host "wrote $out"
