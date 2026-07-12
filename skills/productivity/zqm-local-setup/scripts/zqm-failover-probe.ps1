# zqm-failover-probe.ps1
# Assess LOGIN FAILOVER coverage across the ZQM fleet.
#   - Nodes: scan alternate login ports (WinRM-HTTP 5985, WinRM-HTTPS 5986,
#            OpenSSH 22, RDP 3389, WMI/RPC 135, SMB 445) to see which redundant
#            paths exist. If ONLY 135/445 are open, the node has NO remote login
#            failover -> a WinRM failure means physical console access.
#   - Synology Gardens: check DSM API (5001) AND SSH (22) so we know if DSM
#            outage still leaves SSH management.
# Pure TCP reachability -- no credentials, no writes. Reusable for "is this
# mesh redundant?" questions.
param(
  [hashtable]$Nodes = @{
    "Node-1(218)"="192.168.1.218"; "Node-2(21)"="192.168.1.21";
    "Node-3(46)" ="192.168.1.46";  "Node-4(215)"="192.168.1.215" },
  [hashtable]$Syno = @{
    "GARDEN-02(40)"="192.168.1.40"; "GARDEN-03(64)"="192.168.1.64";
    "Garden-01(173)"="192.168.1.173"; "G02-3772(32)"="192.168.1.32";
    "G02-3774(38)"="192.168.1.38"; "G02-3775(39)"="192.168.1.39";
    "G02-3778(37)"="192.168.1.37"; "G01-3767(53)"="192.168.1.53";
    "G01-3769(52)"="192.168.1.52"; "G01-3771(169)"="192.168.1.169" }
)
function Tcp($ip,$p){
  $s=New-Object System.Net.Sockets.TcpClient
  $s.Client.ReceiveTimeout=600; $s.Client.SendTimeout=600
  try { $r=$s.BeginConnect($ip,$p,$null,$null)
        if(-not $r.AsyncWaitHandle.WaitOne(600)){return $false}
        $s.EndConnect($r); $s.Close(); return $true }
  catch { return $false }
}
$nodePorts = @{ "5985 WinRM-HTTP"=5985; "5986 WinRM-HTTPS"=5986;
                "22 OpenSSH"=22; "3389 RDP"=3389; "135 WMI/RPC"=135; "445 SMB"=445 }
Write-Host "=== NODE ALTERNATE LOGIN PORTS ==="
foreach ($n in $Nodes.Keys) {
  $ip=$Nodes[$n]; $line=$n.PadRight(13)+" "+$ip.PadRight(16)
  foreach ($k in $nodePorts.Keys) { $line += ("$($nodePorts[$k]):"+(Tcp $ip $nodePorts[$k])).PadLeft(20) }
  Write-Host $line
}
Write-Host "=== SYNOLOGY DSM(5001) vs SSH(22) FAILVOER ==="
foreach ($g in $Syno.Keys) {
  $ip=$Syno[$g]
  Write-Host ("  "+$g.PadRight(16)+" "+$ip.PadRight(16)+" 5001(DSM)="+(Tcp $ip 5001)+"  22(SSH)="+(Tcp $ip 22))
}
Write-Host "=== TERRASTER GARDEN-04 (SSH-native; no DSM) ==="
foreach ($ip in @("192.168.1.144","192.168.1.147")) {
  Write-Host ("  GARDEN-04 $ip  22(SSH)="+(Tcp $ip 22)+"  5443(TOS-web)="+(Tcp $ip 5443))
}
