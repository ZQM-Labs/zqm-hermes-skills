# Windows shell/subprocess pitfalls on this workstation

## Symptom A: PowerShell string parsing breaks in terminal() calls
PowerShell reports syntax errors or truncation when long Python stdout payloads with backslashes and control characters are passed through git-bash into PowerShell.

Root cause: git-bash converts line endings on heredoc strings and can emit Windows line endings, which can make PowerShell interpret otherwise valid strings/output streams as unterminated or corrupt.

Fix:
- Do not pass long Python triple-quoted strings into PowerShell via terminal() wrappers.
- Prefer short inline commands and explicit argv tokens in `subprocess` invocations from code, rather than nested multiline scripts.
- Move file parsing/inspection into Python code via `execute_code`; limit shell actions to non-PowerShell commands in `terminal()`.

## Symptom B: Using PowerShell builtins through terminal() on Windows
Repeated patient-facing failures happen when `terminal()` calls rely on PowerShell builtins or complex PowerShell JSON output is heavily nested.

Fix:
- Treat `terminal()` as a POSIX bash shell on this Windows host.
- Use `ls`, `grep`, `find`, `wc`, etc., not `Get-ChildItem`, `Select-String`, `$env:FOO`.
- Do not rely on PowerShell pipeline operators in `terminal()` calls; use bash equivalents.

## Antipatterns to drop
- `subprocess.run(["powershell","-NoProfile","-Command","long multiline python f-string script"])`
- Deeply nested triple-quoted backslash-heavy payloads passed through bash/powershell argv.
- Strict PowerShell-conditioned mental model for `terminal()` on this Windows host.

## Symptom C: `urllib.parse` masks `urllib.request`/`urllib.error` in execute_code on Windows
Symptom: `AttributeError: module 'urllib' has no attribute 'request'` even though `urllib.parse` imported cleanly.

Root cause: in this Windows execute_code runtime, importing only `urllib.parse` does not populate `urllib.request`/`urllib.error` on the package namespace.

Fix:
- Always import together: `import urllib.parse, urllib.request, urllib.error`.
- Alternatively use `from urllib import request, error` explicitly before any `urllib.request.*` usage.
- For HTTP probes in Windows diagnostics, prefer explicit submodule import over implicit package attribute access.

## Recommended Windows execution contract for this skill
1. Read files, parse JSON/YAML, and inspect process trees with `execute_code` + Python stdlib.
2. Use `terminal()` for git/cmd/curl/winget operations in POSIX syntax.
3. Reserve PowerShell for elevated validation only, and only after the user approves elevation.
4. Prefer `Get-NetTCPConnection` over `netstat -ano` for local listening-port enumeration; PowerShell builtins returned cleaner formatted data in `zqm-systems-review` runs than cmd-style `netstat`.
