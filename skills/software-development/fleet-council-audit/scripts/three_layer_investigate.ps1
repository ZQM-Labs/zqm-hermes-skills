# three_layer_investigate.ps1 - LEAD-only process/service/security sweep for a co-located stack.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File three_layer_investigate.ps1 2>&1
# Edit $pids for the target service PIDs. Emits JSON-per-PID + scheduled-task + parent chain
# + C2 egress test (scoped peers) + listeners. Covers the 2026-07-11 ZBit-stack three-layer pass.
$ErrorActionPreference = "SilentlyContinue"
$pids = @(1908, 19120)   # <-- set to the target PIDs

# Elevation-token reader (TokenElevation class 18) via runtime C# P/Invoke
$code = @'
using System; using System.Runtime.InteropServices;
public class Tkn {
  [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(int a, bool i, int pid);
  [DllImport("advapi32.dll")] public static extern bool OpenProcessToken(IntPtr h, int a, out IntPtr t);
  [DllImport("advapi32.dll")] public static extern bool GetTokenInformation(IntPtr t, int ti, IntPtr b, int cb, out int rb);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  public static int Elev(int pid){
    IntPtr h=OpenProcess(0x0400, false, pid); if(h==IntPtr.Zero) return -1;
    IntPtr t; if(!OpenProcessToken(h, 0x0008, out t)){CloseHandle(h);return -1;}
    int rb; IntPtr b=Marshal.AllocHGlobal(4);
    bool ok=GetTokenInformation(t,18,b,4,out rb); int v=-1;
    if(ok) v=Marshal.ReadInt32(b);
    Marshal.FreeHGlobal(b); CloseHandle(t); CloseHandle(h); return v;
  }
}
'@
Add-Type $code -ErrorAction SilentlyContinue

function Get-ProcInfo($id){
  $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
  if(-not $p){ return @{ pid=$id; alive=$false } }
  $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue
  $user = if($owner -and $owner.ReturnValue -eq 0){ "$($owner.Domain)\$($owner.User)" } else { "n/a" }
  $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue
  $parentName = if($parent){ $parent.Name } else { "unknown" }
  $elev = try { [Tkn]::Elev($id) } catch { -1 }
  return @{
    pid = $id; alive = $true
    name = $p.Name
    ppid = $p.ParentProcessId; parentName = $parentName
    cmdline = $p.CommandLine
    path = $p.ExecutablePath
    start = $p.CreationDate
    user = $user
    session = $p.SessionId
    handles = $p.HandleCount; threads = $p.ThreadCount
    elev = $elev   # 1=elevated/admin, 0=standard, -1=no-access
  }
}

Write-Output "=== PROCESS LAYER (elevation + parent chain) ==="
foreach($id in $pids){
  $info = Get-ProcInfo $id
  $info | ConvertTo-Json -Compress
  $chain = @(); $cur = $id; $guard=0
  while($cur -and $guard -lt 12){
    $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
    if(-not $pp){ break }
    $chain += "$($pp.ProcessId)=$($pp.Name)"
    $cur=$pp.ParentProcessId; $guard++
  }
  Write-Output ("  chain: " + ($chain -join " <- "))
}

Write-Output "=== SCHEDULED TASKS (auto-start check) ==="
$t = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match "zbit|litellm|zbit_api" -or $_.TaskPath -match "zbit|litellm" }
if($t){ $t | ForEach-Object { Write-Output ("  TASK: "+$_.TaskPath+$_.TaskName+" state="+$_.State) } } else { Write-Output "  NONE registered" }

Write-Output "=== C2 EGRESS TEST (peers scoped to target PIDs) ==="
foreach($id in $pids){
  $c = Get-NetTCPConnection -OwningProcess $id -State Established -ErrorAction SilentlyContinue
  if($c){
    foreach($x in $c){
      $r=$x.RemoteAddress
      $tag = if($r -match '^127\.|^::1|^192\.168\.1\.'){'LOCAL'}else{'EXTERNAL'}
      Write-Output ("  PID $id -> $r:$($x.RemotePort) [$tag]")
    }
  } else { Write-Output "  PID $id: no established conns" }
}

Write-Output "=== LISTENERS (bind address) ==="
foreach($id in $pids){
  $l = Get-NetTCPConnection -OwningProcess $id -State Listen -ErrorAction SilentlyContinue
  if($l){ $l | ForEach-Object { Write-Output ("  PID $id LISTEN $($_.LocalAddress):$($_.LocalPort)") } }
}
