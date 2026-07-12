# zqm-node-reachability.ps1 - "Can I touch this node remotely right now?"
# Run from Node-1 (agent zqmco session). Determines whether remote management
# of a target Windows node is actually possible WITHOUT needing the user's
# secret or admin. Catches the common false conclusion "it's unreachable"
# when in fact an admin session already exists.
# Usage:  powershell -ExecutionPolicy Bypass -File C:\temp\zqm-node-reachability.ps1 -Node 192.168.1.21
param([string]$Node="192.168.1.21")

$ErrorActionPreference = "Continue"
$tcp = {
  param($ip,$p)
  $s=[System.Net.Sockets.Socket]::new([System.Net.Sockets.AddressFamily]::InterNetwork,[System.Net.Sockets.SocketType]::Stream,[System.Net.Sockets.ProtocolType]::Tcp)
  $s.ReceiveTimeout=$s.SendTimeout=600
  try { $s.Connect($ip,$p); $true } catch { $false } finally { try{$s.Close()}catch{} }
}

Write-Host ("=== Reachability pre-check: $Node ===")
$ps = Get-PSSession -ErrorAction SilentlyContinue | Where-Object { $_.ComputerName -eq $Node }
Write-Host ("  Active PSSessions to $Node : " + $(if($ps){"YES ($($ps.Count))"}else{"none"}))

$maps = Get-SmbMapping -ErrorAction SilentlyContinue | Select-Object -ExpandProperty RemotePath
$hasMap = ($maps | Where-Object { $_ -match $Node }) -join ", "
Write-Host ("  SMB mappings to $Node    : " + $(if($hasMap){$hasMap}else{"none"}))

$cReach = Test-Path "\\$Node\C$" -ErrorAction SilentlyContinue
Write-Host ("  C$ admin share reachable : " + $(if($cReach){"YES (authed SMB session)"}else{"NO (no auth session)"}))

$win = & $tcp $Node 5985
$win6 = & $tcp $Node 5986
$ssh = & $tcp $Node 22
Write-Host ("  WinRM 5985 / 5986 / 22   : $win / $win6 / $ssh")

# verdict
if ($ps -or $cReach) {
  Write-Host "  VERDICT: remote action POSSIBLE now (existing session/cred). Agent can proceed."
} elseif ($win -or $win6 -or $ssh) {
  Write-Host "  VERDICT: port(s) open but NO auth session/cred. Needs zqmlocal password (user-only) to connect."
} else {
  Write-Host "  VERDICT: node dark / no listener. Must run bootstrap LOCALLY on the node."
}
