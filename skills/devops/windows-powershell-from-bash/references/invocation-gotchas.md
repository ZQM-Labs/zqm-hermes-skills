# PowerShell-from-bash invocation gotchas — evidence

## Trigger
Driving a Windows 10 workstation through the agent `terminal`, which is **bash
on MSYS/git-bash**, NOT PowerShell. `powershell.exe` exists but inline
`-Command` argument strings get pre-expanded by bash.

## The broken pattern (DO NOT USE for non-trivial PS)
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-PSDrive ... | Select-Object Name, @{n='UsedGB';e={[math]::Round($_.Used/1GB,2)}} ..."
```
Bash strips `$_.` → `[math]::Round(/c/WINDOWS/system32.Used/1GB,2)` and the
parser dies.

## Real failure transcripts (this session)
1. RAM query:
   `Missing argument in parameter list` at the `$os=...; =[math]::Round(.TotalVisibleMemorySize...)`
   → bash ate `$os`, `$total`, etc.
2. Disk query:
   `Missing ')' in method call` / `You must provide a value expression following the '/' operator`
   / `Unexpected token 'c/WINDOWS/system32.Used/1GB'`
3. GPU query: same class of errors on `$_.AdapterRAM`.
4. Uptime query: bash itself errored —
   `syntax error near unexpected token ''F2''` on the `$($up.TotalDays.ToString('F2'))`
   `$(...)` subexpression was parsed by bash, not PowerShell.

## The working pattern (USE THIS)
Write PS to a `.ps1` with write_file (no bash in the path), then:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:/Users/zqmco/inv.ps1'
```
write_file content example that ran clean:
```powershell
$os = Get-CimInstance Win32_OperatingSystem
$total = [math]::Round($os.TotalVisibleMemorySize/1MB,2)
$free  = [math]::Round($os.FreePhysicalMemory/1MB,2)
$used  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/1MB,2)
Write-Output "TotalGB=$total FreeGB=$free UsedGB=$used"
Get-PSDrive -PSProvider FileSystem | Select-Object Name, @{n='UsedGB';e={[math]::Round($_.Used/1GB,2)}}, @{n='FreeGB';e={[math]::Round($_.Free/1GB,2)}}, @{n='TotalGB';e={[math]::Round(($_.Used+$_.Free)/1GB,2)}} | Format-Table -AutoSize
$bt = $os.LastBootUpTime; $up = (Get-Date) - $bt
Write-Output "LastBoot=$bt UptimeDays=$($up.TotalDays.ToString('F2'))"
```
Clean up the temp script after (`rm -f`).

## Why this is durable, not a transient failure
It is a structural fact of the host: the terminal is bash, PowerShell is a
child process, and `$`/`$()` belong to both shells with conflicting rules.
Any future session querying WMI/CIM or running non-trivial PS from this bash
terminal will hit the same wall unless it writes a `.ps1`.

## TWO MORE gotchas (verified 2026-07-11)
- **`$host` is a reserved automatic variable.** Never assign to `$host`
  (e.g. `$host = "192.168.1.46"`). PowerShell throws
  `Cannot overwrite variable Host because it is read-only or constant.`
  Rename to `$target` / `$ip` / `$node`. (Bit a TCP-scan script this session:
  one wasted run before the fix.)
- **Forward slashes in the `-File` path.** MSYS bash strips backslashes from
  UNQUOTED paths, so `powershell.exe -File C:\Users\zqmco\script.ps1` arrives as
  `C:Userszqmcoscript.ps1` and PowerShell reports "file does not exist". Even
  double-quoted `"C:\Users\...\".ps1` is fragile (bash escaping edge cases).
  PowerShell accepts `/` as a path separator on Windows — always pass
  `-File 'C:/Users/zqmco/script.ps1'` (single-quoted, forward slashes).
