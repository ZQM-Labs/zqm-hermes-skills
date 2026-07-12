# Working Windows process-probe for Layer 1 (process + elevation + parent chain).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File win-process-probe.ps1 <pid1> <pid2> ...
# Proven pattern from the ZBit-stack three-layer investigation (PIDs 1908 / 19120).
param(
  [int[]]$Pids = @(1908, 19120)
)

# --- elevation check via C# TypeAccelerator (TokenElevation class 18) ---
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

# IMPORTANT: never name a probe var $PID — PowerShell's $PID is read-only (shell PID).
function Get-ProcInfo($id){
  $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
  if(-not $p){ return @{ pid=$id; alive=$false } }
  $owner = $p.GetOwner()
  $user = if($owner -and $owner.User){ "$($owner.Domain)\$($owner.User)" } else { "n/a" }
  $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue
  $parentName = if($parent){ $parent.Name } else { "unknown" }
  $elev = try { [Tkn]::Elev($id) } catch { -1 }
  return @{
    pid = $id; alive = $true; name = $p.Name
    ppid = $p.ParentProcessId; parentName = $parentName
    cmdline = $p.CommandLine; path = $p.ExecutablePath
    start = $p.CreationDate; user = $user; session = $p.SessionId
    handles = $p.HandleCount; threads = $p.ThreadCount
    elev = $elev   # 1=admin/elevated, 0=standard, -1=noaccess
  }
}

foreach($id in $Pids){
  $info = Get-ProcInfo $id
  $info | ConvertTo-Json -Compress
}

# scheduled-task check (manual launch => NONE registered)
Write-Output "=== SCHEDULED TASKS (zbit/litellm) ==="
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match "zbit|litellm" -or $_.TaskPath -match "zbit|litellm" }
if($tasks){ $tasks | ForEach-Object { Write-Output ("TASK: "+$_.TaskPath+$_.TaskName+" state="+$_.State) } } else { Write-Output "NONE registered" }

# full parent chain to session root
Write-Output "=== PARENT CHAIN ==="
foreach($id in $Pids){
  $chain = @(); $cur = $id; $guard=0
  while($cur -and $guard -lt 12){
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
    if(-not $p){ break }
    $chain += ("$($p.ProcessId)=$($p.Name)")
    $cur = $p.ParentProcessId; $guard++
  }
  Write-Output ("PID $id chain: " + ($chain -join " <- "))
}
