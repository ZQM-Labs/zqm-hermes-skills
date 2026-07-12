---
name: windows-powershell-admin
description: Run PowerShell on a Windows host driven through the bash/MSYS2 terminal. Covers the variable/non-ASCII mangling pitfall and its fix (write a .ps1 then Execute-File), the prompt-gated elevated-script pattern this user requires, Get-CimInstance instead of wmic, and the fact that BIOS/firmware settings need a reboot. Use for any Windows system query, audit, config, or remediation on this machine.
---

# Windows PowerShell Administration (via bash/MSYS2 terminal)

## When to use
- Querying hardware/software/security state on this Windows box (CPU, RAM, disks, GPU, services, BitLocker, TPM, Secure Boot).
- Producing an audit/remediation script the user runs themselves (often as Admin).
- Anything that would otherwise use `wmic`.

## Core pitfall - inline PowerShell through the bash tool gets mangled
The terminal tool runs bash (MSYS2/MINGW64) on top of Windows, NOT PowerShell. Passing PowerShell inline via `-Command "..."` works for trivial one-liners but CORRUPTS anything non-trivial in transit:
- `$null`, `$_` and `$_.Property` get stripped or rewritten into garbage (e.g. `/c/Windows/System32.Length`).
- `| Select-String` / `| Where-Object` piped from a PowerShell cmdlet are reinterpreted by bash and error out ("command not found").
- Non-ASCII chars such as em-dashes (`—`) corrupt the script and break parsing with "Missing ')' in method call" / "Unexpected token".
- Backslashes inside `\\` paths get eaten or doubled inconsistently.

This is the #1 recurring failure mode on this host. Do not hand-write long PowerShell inline. See `references/ps1-mangling-pitfall.md` for concrete transcripts.

## The fix (always do this)
1. Write the script to a .ps1 file with the `write_file` tool. write_file preserves `$_` and em-dashes; the bash tool does not.
2. Run it with: `powershell -NoProfile -ExecutionPolicy Bypass -File C:/tmp/<name>.ps1`
   - Forward slashes or escaped backslashes both work in the path.
   - Keep the script ASCII-only (no em-dashes) to be safe.
3. Validate syntax BEFORE handing a script to the user. Use `scripts/syntax-check.ps1`:
   `powershell -NoProfile -ExecutionPolicy Bypass -File C:/tmp/syntax-check.ps1 -Path C:/tmp/<name>.ps1`
   Hand the script over only after you see "SYNTAX OK".

## Elevation / Admin model (this user's standing preference)
- The agent's shell runs NON-admin (IsAdmin:False). That BLOCKS reads of Secure Boot, TPM, raw SMART, and BitLocker protectors.
- This user wants small, self-contained, PROMPT-GATED PowerShell scripts they run themselves (often as Admin), NOT the agent executing everything.
- Every script handed to the user must:
  - Self-check elevation first and exit cleanly if not Admin.
  - Be READ-ONLY by default. Any mutation (enable/disable/set/reboot) is behind an explicit `Read-Host` Y/N prompt.
  - Print AND save a log file (e.g. `C:\tmp\<name>-report.txt`) so the user can paste results back.
- Never promise to "do X without a reboot" when X is a BIOS/firmware setting - see below.

## wmic is broken - use CIM
`wmic` returns exit code 127 on this host. Use `Get-CimInstance` instead:
- `wmic cpu get ...`           -> `Get-CimInstance Win32_Processor`
- `wmic computersystem get ...` -> `Get-CimInstance Win32_ComputerSystem`
- disks                        -> `Get-PhysicalDisk` + `Get-StorageReliabilityCounter`
- BitLocker                    -> `Get-BitLockerVolume` (module may be absent; fall back to `manage-bde.exe`, which is always present)

## BIOS / firmware settings need a reboot
DRAM frequency (XMP/DOCP), boot order, Secure Boot toggle, etc. are applied at POST. The memory controller retrains at boot - there is NO live/software-only way to change DRAM speed from Windows. Any "enable XMP" task ends in exactly one reboot. Dell's `cctk` (Command | Configure) can stage a profile from Windows but is NOT preinstalled and is NOT on scoop's default buckets - verify it exists (`where cctk`) before relying on it, otherwise give the user the F2 manual path.

## Pitfalls
- Do not pipe PowerShell cmdlets into bash utilities (`| head`, `| grep`) - bash eats them. Filter inside PowerShell, or write a .ps1 and run with -File.
- `Get-Tpm` SpecVersion often comes back empty even when TPM is healthy - not an error.
- `manage-bde -protectors -get` reports "no protector" if protection was resumed without a key having been backed up; export keys via `Win32_EncryptableVolume.GetKeyProtectorNumericalPassword` AFTER enabling.
- `ConvertTo-SecureString` is UNAVAILABLE when the `Microsoft.PowerShell.Security` module fails to load (corrupted TypeData on some hosts - error "could not be loaded" with benign AuditToString/Sddl duplicate-member warnings). Build a `PSCredential` via reflection instead:
  ```powershell
  $secType=[System.Management.Automation.PSCredential].Assembly.GetType('System.Management.Automation.PSSecureStringHelper')
  $m=$secType.GetMethod('GetSecureString',[Reflection.BindingFlags]'Static,NonPublic')
  $secure=$m.Invoke($null,@($pass))
  $cred=New-Object System.Management.Automation.PSCredential($user,$secure)
  ```
- `SkipCertificateCheck` does NOT exist in PowerShell 5.1 (it's PS 6+). To hit a self-signed HTTPS endpoint (e.g. an appliance web UI on your LAN), bypass TLS validation with a custom callback:
  ```powershell
  Add-Type @'
  using System.Net; using System.Security.Cryptography.X509Certificates;
  public class T { public static void I(){ ServicePointManager.ServerCertificateValidationCallback = delegate { return true; }; } }
  '@
  [T]::I()
  Invoke-WebRequest -Uri 'https://host.example' -UseBasicParsing
  ```
- UNC paths (`\\\\host\\share\\file`) typed inline or through bash get reinterpreted as drive paths (`C:\\host\\...`) and fail "does not exist". Put any UNC access in a `.ps1` file run with `-File`.
- **`wsl.exe` output is UTF-16LE AND can HANG.** Two bugs in one:
  1. wsl.exe writes UTF-16LE to stdout. Piping it through PowerShell (`wsl -l -v 2>&1 | ForEach-Object {...}`) re-encodes it into null-padded garbage (`C\u0000l\u0000a\u0000s\u0000s...`). Fix: run via `Start-Process -RedirectStandardOutput C:\tmp\wsl.out`, then `Get-Content C:\tmp\wsl.out -Encoding Unicode -Raw`.
  2. When the WSL MSI COM class is unregistered (REGDB_E_CLASSNOTREG — common after a broken WSL/Windows update), `wsl.exe` does not error, it **HANGS forever**. A bare `wsl --status` / `wsl -l -v` in a script freezes the whole probe/repair. Fix: ALWAYS run wsl via `Start-Process` with `$p.WaitForExit(8000)` and `if (-not $done) { $p.Kill() }`. Never call wsl.exe directly in a pipeline.
  (Reproved 2026-07-11: `wsl -l -v` hung 60s+; bounded Start-Process returned in <9s with a clean timeout message. repair-wsl.ps1 must use this pattern so it reaches `regsvr32 msi.dll` instead of hanging at diagnosis.)
- **`[Parser]::ParseFile` returns the AST and floods stdout if you don't suppress it.** The standard syntax-check idiom is `$null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)` — the `$null =` is REQUIRED. Without it, the checker dumps every file's full AST to the terminal (seen 2026-07-11: 360KB of AST on a 67-file sweep; skill's own check-syntax.ps1 had this bug until fixed).
- **`Get-FileHash` cmdlet is ABSENT on this host's PowerShell 5.1 build** (returns CommandNotFoundException, even though it normally ships in Microsoft.PowerShell.Utility — this build's module set is partially broken, consistent with the ConvertTo-SecureString/TypeData issues). To hash a file, use .NET directly:
  ```powershell
  $b = [System.IO.File]::ReadAllBytes('C:\tmp\x.out')
  $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash($b)
  ($h | ForEach-Object { $_.ToString('x2') }) -join ''
  ```
  (Used 2026-07-11 to anchor audit evidence when Get-FileHash failed. Also note: `Get-FileHash` result can be silently swallowed by `$ErrorActionPreference='SilentlyContinue'`, so read `.Hash` explicitly or use the .NET path.)
- **MSYS `ping` is UNRELIABLE on this host — use `Test-Connection` / `TcpClient`.** A bash `ping -c1 -W1 <ip>` sweep reported ALL 17 LAN hosts as DOWN, but PowerShell `Test-Connection -ComputerName <ip> -Count 1 -Quiet` confirmed every one UP (and the live ARP table showed them). The MSYS ping binary is non-functional here — do NOT trust bash `ping` for reachability. For liveness use `Test-Connection`; for port checks use a raw `System.Net.Sockets.TcpClient` with a 2s `AsyncWaitHandle.WaitOne` timeout (the `Test-NetConnection -AsJob` combo throws in PS 5.1). Seen 2026-07-11 during the ZQM-MESH neighbor audit.

## Templates / scripts / references
- `templates/prompt-gated-admin-skeleton.ps1` - copy this for any audit/remediation script you hand the user.
- `scripts/syntax-check.ps1` - drop-in syntax validator to run before handing a script over.
- `references/ps1-mangling-pitfall.md` - concrete corruption transcripts and the exact fix recipe.
