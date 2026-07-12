# PowerShell Validation Pitfalls on Windows

When validating PowerShell scripts from a non-PowerShell shell:
- Inline `-Command "..."` can mangle `$_` and `[ref]` tokens through multiple interpreter layers.
- Safer pattern: write a tiny `.ps1` helper under `%LOCALAPPDATA%\Temp` and invoke it with `-File <path>`.
- Example helper for syntax-only checks:
  - `param([string]$Target)`
  - `$errors = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Target), [ref]$null, [ref]$errors)`
  - `if ($errors) { $errors | ForEach-Object { Write-Output $_.ToString() }; exit 1 }`
  - `Write-Output 'PS1_PARSE_OK'; exit 0`
- Do not rely on `$_` expansion in double-quoted strings from git-bash wrappers; prefer single quotes or helper scripts.
