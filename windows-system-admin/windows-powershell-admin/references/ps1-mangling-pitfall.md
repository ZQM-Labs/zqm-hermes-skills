# The inline-PowerShell-through-bash mangling pitfall

## Root cause
The Hermes terminal tool drives bash (MSYS2/MINGW64) on this Windows host, not PowerShell.
When you pass PowerShell inside `powershell -Command "..."`, the bash layer rewrites
dollar-vars and non-ASCII bytes before PowerShell ever sees them. Trivial one-liners
survive; anything non-trivial is corrupted.

## What gets mangled (real transcripts from 2026-07-10)

### 1. `$_` / `$null` / `$_.Property` stripped or rewritten
Command tried:
`powershell -Command "Get-ChildItem C:\tmp\bitlocker-keys ... | ForEach-Object { ... $_.Length }"`
Error produced:
```
/c/Windows/System32.Length : The term '/c/Windows/System32.Length' is not recognized ...
```
Fix: write the script to a .ps1 via write_file (write_file preserves `$_`), then:
`powershell -NoProfile -ExecutionPolicy Bypass -File C:/tmp/verify-keys.ps1`

### 2. Piping PowerShell cmdlets into bash `| head` / `| grep`
Command tried:
`powershell -Command "Get-Service ... | Where-Object {=== RUNNING SERVICES ===.Status ...}"`
Error: `=== : The term '===' is not recognized as the name of a cmdlet ...`
Also: `| Select-String ...` inside a `-Command` string triggers "command not found" from bash.
Fix: do all filtering inside the .ps1. Never append `| head` / `| grep` to a PowerShell
cmdlet through the bash tool.

### 3. Non-ASCII (em-dash `—`) breaks parsing
A script containing `---` header lines with em-dashes parsed with:
"Unexpected token '... in expression or statement." / "Missing closing ')' in expression."
Fix: keep .ps1 ASCII-only. Use `---` (hyphens) or `[SECTION]`, never em-dashes, in
strings you want to survive transit.

### 4. `$null` eaten in a -Command one-liner
`[ref]$null` became empty -> "Missing condition in if statement after 'if ('."
Fix: write the check to a .ps1 file. See scripts/syntax-check.ps1.

## The fix recipe (always)
1. write_file the script (ASCII, no em-dashes).
2. `powershell -NoProfile -ExecutionPolicy Bypass -File C:/tmp/<name>.ps1`
3. Before handing to user, validate: `powershell -NoProfile -ExecutionPolicy Bypass -File
   C:/tmp/syntax-check.ps1 -Path C:/tmp/<name>.ps1` -> expect "SYNTAX OK".

## Why this matters
Three separate sessions (Ollama install, workstation audit, XMP enable) all hit this and
lost time to it. The pattern is 100% reproducible on this host. Writing the .ps1 instead
of inlining it is the single highest-leverage habit for PowerShell work here.
