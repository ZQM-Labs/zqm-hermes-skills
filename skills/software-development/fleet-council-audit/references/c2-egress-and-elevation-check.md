# C2 / Egress Test + Process Elevation Check

Reusable recipe used 2026-07-11 on the ZBit stack (PIDs 1908 / 19120) when the
user asked "are these C2 nodes?". Two independent tests, both decisive, both
read-only.

## 1. C2 EGRESS TEST (does the process phone OUT to a controller?)

A C2 node takes COMMANDS from an external controller: it initiates connections to
a foreign/non-local IP. A service that only ACCEPTS loopback connections is NOT
C2 by topology alone. The decisive probe is the ESTABLISHED-connection peer set.

```powershell
# For each PID, list ESTABLISHED peers and tag LOCAL vs EXTERNAL.
foreach ($p in @(1908,19120)) {
  $c = Get-NetTCPConnection -OwningProcess $p -State Established -ErrorAction SilentlyContinue
  if ($c) {
    foreach ($x in $c) {
      $r = $x.RemoteAddress
      $tag = if ($r -match '^127\.|^::1|^192\.168\.1\.') { 'LOCAL' } else { 'EXTERNAL' }
      Write-Output ("PID $p -> $r:$($x.RemotePort) [$tag]")
    }
  } else { Write-Output "PID $p: no established conns" }
}
```

INTERPRETATION (PROVEN live this session):
- ZBit stack: only `127.0.0.1 <-> 127.0.0.1` self-pairs. External-peer grep BLANK.
  => NO egress. Not C2.
- CRITICAL: the box will have OTHER PIDs with EXTERNAL peers (browser, telemetry,
  GitHub/Azure sync). Those are unrelated processes -- do NOT attribute them to the
  target PID. Always filter by `-OwningProcess <targetpid>` so you only see THAT
  process's peers. A `netstat` grep for "EXTERNAL" across the whole host is a
  false-positive trap if you don't scope to the PID.

bash + netstat alternative (coarser but works from MSYS):
```
netstat -ano | grep -E "1908|19120" | grep -i ESTABLISHED | grep -vE "127.0.0.1|192.168.1."
# blank = no external egress from those PIDs
```

## 2. PROCESS ELEVATION (admin-token) CHECK

A service running with an admin token is a higher blast-radius if compromised.
`Get-CimInstance Win32_Process` does NOT expose token elevation directly, but the
process token's `TokenElevation` (class 18) does, via a tiny C# Add-Type.

```powershell
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
# returns: 1 = elevated/admin token, 0 = standard, -1 = no access
[Tkn]::Elev(1908)
[Tkn]::Elev(19120)
```

LIVE RESULT (2026-07-11): BOTH ZBit-stack PIDs returned elev=1 -> running under an
ADMIN token (launched from an elevated explorer/cmd session). Not a C2 signal by
itself, but a hardening note: if either is ever rebound to 0.0.0.0, it becomes an
admin-privileged open service. Keep loopback-only.

## C2 VERDICT TEMPLATE
For ANY "is X a C2 node" question, emit:
1. LISTEN bind address (loopback vs 0.0.0.0) -- from netstat.
2. ESTABLISHED peer set of the target PID (scoped) -- external = C2 signal.
3. Source review (first-party code? eval/exec? writes confined?) -- from identify-listener.md.
4. Verdict: PROVEN C2 / NOT C2 (with the three evidence lines).
Only "external egress + foreign controller + covert channel" = C2. A loopback-only
first-party service is NOT C2 regardless of admin token.
