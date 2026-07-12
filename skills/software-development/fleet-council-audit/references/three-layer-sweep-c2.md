# Three-Layer LEAD-ONLY Sweep + C2 Verdict (co-located stack)

Reusable recipe for when the user pastes a startup log / names a PID and wants a
full **process / service / security** investigation of a known co-located service
stack (e.g. the ZBit Agent API `:8400` + LiteLLM `:4001`), WITHOUT a fan-out
(one box, <=3 services -> run LEAD-only, do not delegate).

Live-tested 2026-07-11 on PIDs 1908/19120 (ZBit stack). Produced a clean
C2=FALSE verdict from connection topology alone.

## Layer 1 - PROCESS (PowerShell -File, never inline)
Write a `.ps1` (see `scripts/three_layer_investigate.ps1`) and run:
`powershell -NoProfile -ExecutionPolicy Bypass -File <path> 2>&1`

The script must collect, per PID:
- `CommandLine` / `ExecutablePath` (`Get-CimInstance Win32_Process -Filter "ProcessId=$id"`)
- parent chain walk (to `explorer.exe` = manual desktop launch; `cmd.exe`->`.bat` = manual;
  a ScheduledTask host = auto-start; Startup `.lnk` = logon)
- owner via `Invoke-CimMethod -InputObject $p -MethodName GetOwner` (NOT `.InvokeMethod()` - throws)
- **ELEVATION TOKEN** - see below
- `Get-ScheduledTask -TaskName '*<name>*'` -> empty = NOT registered = manual launch

### Read a process's elevation token from a NON-elevated agent shell
`GetOwner` gives domain\user but NOT whether the token is admin. Detect it with
a tiny C# P/Invoke compiled at runtime (works unprivileged; uses
`TokenElevation` information class 18):

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
Add-Type $code
# [Tkn]::Elev($pid) -> 1 = elevated/admin token, 0 = standard, -1 = no access
```

Caveat: `OpenProcess(0x0400=PROCESS_QUERY_LIMITED_INFORMATION,...)` may return -1
for PIDs you don't own / cross-session. Treat -1 as "could not read", not "standard".

## Layer 2 - SERVICE (bash curl + netstat, no `$`)
- Bind check: `netstat -ano | grep -E ":(8400|4001)" | grep LISTENING` -> confirm
  `127.0.0.1` only (loopback). `0.0.0.0` = reachable off-box (escalate).
- Auth matrix (curl from bash, avoids PS `$`):
  - open routes: `GET /`, `/health`, `/openapi.json`, `/docs`, `/redoc` -> expect 200 unkeyed
  - `GET /v1/models` (no key) -> 401; `GET /v1/models` (header `X-Api-Key: bogus`) -> 401
    (proves key is header-only; query-param key correctly rejected)
  - LiteLLM: `GET /health/liveliness`, `/v1/models` (open); `POST /v1/chat/completions`
    (no key) -> decisive open-inference test; `POST /key/generate` -> 500/422
    (no Postgres -> admin NOT exploitable)
- VERIFY AUTH BOTH DIRECTIONS + prove writes persisted (see agent-service-log-audit.md).

## Layer 3 - SECURITY / C2 VERDICT
Decisive test: does the TARGET PID hold any ESTABLISHED connection to a non-loopback,
non-LAN IP?

```bash
netstat -ano | grep -E "1908|19120" | grep -i ESTABLISHED | grep -vE "127.0.0.1|192.168.1."
# blank = NO external egress = no C2 beacon
```

**CRITICAL - attribute peers to the RIGHT PID.** A box-wide external-peer scan shows
connections owned by OTHER processes (browser, telemetry, sync). e.g. this session the
only EXTERNAL peers were on PIDs 5564/5556/17548/12000 (GitHub/Azure/browser) - NONE
were 1908/19120. A C2 false-positive happens if you read the box-wide list and blame the
target. ALWAYS filter `netstat` by the target PIDs (and/or `Get-NetTCPConnection
-OwningProcess <pid> -State Established`) BEFORE judging.

### C2 verdict template
- Hallmarks of C2: outbound beacon to a public/external IP on a non-standard port,
  periodic polling, encrypted exfil channel, hidden controller.
- If target PIDs show ONLY loopback self-pairs (127.0.0.1<->127.0.0.1) and zero external
  egress -> PROVEN not C2 by connection topology.
- If also first-party code (no eval/exec, local-only writes) -> benign, not C2.
- Report PROVEN, cite the filtered netstat as evidence.

## Persist
Consolidated SQLite ledger (one `.db`, 3+ tables: process_layer / net / service_probe,
plus a `verdict` table). EXTEND the primary service's ledger across its own follow-up
passes; spin a SIBLING ledger for a DIFFERENT backing service (per the "investigate
further" verb guidance). See `scripts/audit_to_sqlite.py` for the schema pattern.

## Gotchas hit this session
- Bash env vars (`$WINPY`) do NOT persist across `terminal` calls - re-declare the python
  path at the top of every call, or inline the absolute path.
- A uvicorn log line printed twice (parent+worker startup) != two instances - `netstat`
  shows ONE PID listening = ONE service.
- User CONSENT GATE: a PowerShell probe with a `:`-in-string parse failure was DENIED by
  the user. Do not retry denied commands; the netstat evidence already settled the question.
