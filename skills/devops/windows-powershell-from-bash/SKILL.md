---
name: windows-powershell-from-bash
description: >-
  Run PowerShell / WMI-CIM queries and Windows-native commands from the
  bash (MSYS/git-bash) terminal on this Windows host without bash eating your PowerShell variables. Use whenever you need real OS/hardware/WMI numbers from a Windows machine that you're driving through the bash shell (inventory, diagnostics, config probes, service state checks).
---

# Running PowerShell from the bash (MSYS/git-bash) terminal

The agent's `terminal` runs through **bash on MSYS**, not PowerShell or cmd.
`powershell.exe` is available, but inline `-Command` strings are dangerous.

## THE PITFALL (cost this session: 4 failed commands)
Bash performs **variable expansion** on the command line *before* PowerShell
sees it. PowerShell's `$_` (pipeline variable), `$var`, `$($subexpr)`, and
`$true` all start with `$` and get mangled or dropped by bash.

Symptoms you'll see:
- `Missing argument in parameter list` / `Missing ')' in method call`
- `You must provide a value expression following the '/' operator`
- bash: `syntax error near unexpected token \"'F2'\"` (the `$(...)` got parsed by bash)
- `[math]::Round(/c/WINDOWS/system32...` — the `$_.` was stripped, leaving `/c/...`

Inline `-Command` works ONLY for trivial strings with **no** `$`, `()` of the
PowerShell kind, or `{}`. Anything with `Select-Object @{...}`, `$_`,
`$(Get-Date)`, or loops MUST go to a file.

## THE FIX (always do this)
1. Write the PowerShell to a `.ps1` file with `write_file` (write_file does not
   pass through bash, so `$_` and `$var` survive verbatim).
2. Execute it with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:/Users/<user>/probe.ps1'`.
3. Clean up the temp script afterward (`rm -f`).

This is the SAME protection pattern used for ad-hoc verification scripts
(hermes-verify- prefix) — keep PowerShell out of the bash command line.

### INLINE `-Command` WITH `$_` / `$var` — MUST BE SINGLE-QUOTED (verified 2026-07-12)
The file method is safest, but for a quick one-liner you MUST wrap the entire
`-Command` argument in **single** quotes in bash. If you use double quotes,
bash expands every `$_` / `$var` / `$($...)` BEFORE PowerShell sees it:
- `powershell -NoProfile -Command "Get-ScheduledTask | Where-Object { $_.TaskName -match 'x' }"` -> bash eats `$_` -> PowerShell receives `... /c/WINDOWS/system32.TaskName -match 'x' ...` and throws `The term '/c/WINDOWS/system32.TaskName' is not recognized`. (Bit this session TWICE.)
- FIX: `powershell -NoProfile -Command 'Get-ScheduledTask | Where-Object { $_.TaskName -match "x" }'` (outer single quotes; double quotes INSIDE for the match pattern). Bash leaves `$_` intact, PowerShell runs it.
Rule of thumb: if the inline command contains ANY PowerShell `$`, single-quote the whole `-Command`. When unsure, just write a `.ps1` and use `-File`.

### Example
```powershell
# write_file -> C:/Users/<user>/probe.ps1
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors | Format-List

# terminal — FORWARD SLASHES in -File path (MSYS strips backslashes)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:/Users/<user>/probe.ps1'
```

## When you DO need a one-liner inline
Quote hard and avoid `$`. Even then, prefer the file method. If unavoidable,
single-quote the whole `-Command` argument and use `''` for any needed literal
quotes — but note bash single-quotes still won't protect a `$` from being a
bash `$` unless escaped as `\\$`. The file method is simpler and reliable.

## TWO MORE bash/MSYS gotchas (verified 2026-07-11)
- **`$host` is a reserved automatic variable in PowerShell.** Never assign to
  `$host` (e.g. `$host = "192.168.1.46"`) — it throws
  `Cannot overwrite variable Host because it is read-only or constant.`
  Name your target `$target`, `$ip`, or `$node` instead. (Bit a TCP-scan
  script this session: one wasted run before the fix.)
- **Always use FORWARD SLASHES in the `-File` path.** MSYS bash strips
  backslashes from UNQUOTED paths (`C:\\Users\\zqmco\\script.ps1` →
  `C:Userszqmcoscript.ps1`, PowerShell reports "file does not exist"). Double-
  quoted backslashes *sometimes* survive bash but are fragile. PowerShell
  accepts `/` as a path separator on Windows, so pass
  `-File 'C:/Users/zqmco/script.ps1'` (single-quoted, forward slashes).
  The failure transcript is in `references/invocation-gotchas.md`.

## TWO MORE `.ps1` AUTHORING GOTCHAS (verified 2026-07-11)
When you write PowerShell into a `.ps1` via `write_file` and run `-File`, the
bash-expansion trap is gone — but TWO more bugs bite at *author* time:
- **Literal `%` next to a `{N}` format placeholder breaks the parser.** Writing
  `"...free={3} GB ({4}%) | ..." -f ...` throws
  `You must provide a value expression following the '%' operator.`
  (PowerShell reads `%` as the ForEach-Object/`%` operator, not a literal.)
  FIX: compute the percent into a variable and keep `%` OUT of the `-f` string,
  e.g. `$pct = [math]::Round(($a/$b)*100,1)` then
  `"...({0} pct)..." -f $pct`. Or append the sign outside the placeholder.
- **Non-ASCII glyphs (em-dash —, curly quotes, smart chars, AND the
  mojibake `?` replacement char) in the source `.ps1` corrupt the script**
  and throw `Missing closing '}' in statement block` / `The string is missing
  the terminator` at the offending line. The write_file path does NOT
  sanitize them — a stray `—` or a `?` that replaced an em-dash mid-comment
  silently breaks the parse. THIS BURNED 3 FAILED COMMANDS in one session:
  a `Write-Output "=== ... — what's ..."` comment with a `?` in place of an
  em-dash threw ParserError, and TWO follow-on runs failed on the same
  corrupted line. FIX: keep the `.ps1` ASCII-ONLY — use a hyphen `-` not
  an em-dash, `pct` not `%`, straight quotes. If a re-run reports a parse
  error at a line that looks fine, suspect an invisible non-ASCII char: rewrite
  the whole file ASCII and re-run. Do NOT fight it line-by-line — the
  corruption is often in a comment you'd otherwise skip.
Both were hit writing the Node-1 storage/shares/network audit this session; the
first pass failed to parse and had to be rewritten ASCII + `%`-free.

## Windows PowerShell 5.1 vs PowerShell 7 PARAMETER GOTCHAS (verified 2026-07-11)
The agent's `powershell.exe` is **Windows PowerShell 5.1**, NOT PowerShell 7.
PS7-only cmdlet parameters do NOT exist in 5.1 and fail with a misleading
`A parameter cannot be found that matches parameter name 'X'`
ParameterBindingException that LOOKS like a typo, not a version gap.
- **`Test-Connection -TimeoutSeconds` is PS7-only.** In 5.1 it throws the
  ParameterBindingException and the WHOLE sweep aborts (silent zero-hosts result,
  no error surfaced to caller). FIX: `Test-Connection -ComputerName $ip -Count 1
  -Quiet` (no timeout switch), OR `ping.exe -n 1 -w 1000 $ip` from bash (ms
  timeout), OR `[System.Net.NetworkInformation.Ping]` with a timeout in C#.
- Other commonly-missing-in-5.1 params: `Test-Connection -TcpPort` (PS7-only).
  `Test-NetConnection` works but some extras vary by build. When unsure, target
  the lowest-common-denominator param set, or verify with
  `Get-Help <Cmdlet> -Parameter *` before building a script around it.
- If a PS7-only feature is truly required, invoke `pwsh.exe` (if installed) instead
  of `powershell.exe` — but pwsh is NOT guaranteed present on these nodes, so
  prefer the 5.1-compatible form.

## `Get-EventLog -LogName <ARRAY>` FAILS in PS 5.1 (verified 2026-07-11)
`Get-EventLog -LogName System,Application -EntryType Error` throws
`Cannot convert 'System.Object[]' to the type 'System.String' required by
parameter 'LogName'`. PS 5.1's `-LogName` takes a SINGLE string, not an array
(unlike `Get-WinEvent` which accepts arrays). FIX: loop per log:
```powershell
foreach ($L in @('System','Application')) {
  Get-EventLog -LogName $L -EntryType Error -Newest 8 |
    Select-Object TimeGenerated,Source,Message
}
```
Write the loop to a `.ps1` (file method) — don't inline, the `$L`/`$_` get
bash-mangled. This bit a fleet diagnostics sweep: the array form silently errors
instead of returning merged results, so you get an empty/erroring probe.

## Read-only inventory recipe (reusable skeleton)
For hardware/OS inventory, query these CIM classes (all read-only, no state change):
- OS/version/build: `Get-ComputerInfo` (WindowsProductName, WindowsVersion,
  WindowsBuildLabEx, OsArchitecture, OsInstallDate, OsLastBootUpTime)
- CPU: `Win32_Processor` (Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed)
- RAM: `Win32_OperatingSystem` TotalVisibleMemorySize / FreePhysicalMemory (bytes → /1MB for GB)
- Disks: `Get-PSDrive -PSProvider FileSystem` (Used/Free) + `Win32_DiskDrive` (Size) for physical
- GPU: `Win32_VideoController` (Name, DriverVersion, AdapterRAM)
- Uptime: `(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime`
- Board/BIOS: `Win32_BaseBoard`, `Win32_BIOS`, `Win32_ComputerSystem`

See `references/invocation-gotchas.md` for the exact failure transcripts,
the `$host`/forward-slash gotchas, and the before/after that motivated this skill.
