---
name: windows-secure-credential-handoff
description: "Securely get a secret (password, API token) from the user into the agent's PowerShell session on the SAME Windows PC without it ever appearing in chat/transcript. Use when the agent's shell runs as a different local account than the one the human types in (e.g. human=alexz, agent=zqmco), or whenever you must consume a user-supplied credential for SMB/SSH/DSM/API work but the user refuses to paste it in chat. Covers machine-scope DPAPI (ProtectedData LocalMachine), the cross-account 'Key not valid' failure of user-scope DPAPI, the Add-Type assembly-load pitfall, the Set-Content silent-fail trap, and the verify-without-printing consumer pattern."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [windows, powershell, dpapi, credential, secrets, secure-handoff, lan, zqm]
---

# Secure Credential Handoff (Windows, no chat exposure)

## When to use
- The user must give you a password / API token, but pasting it in chat is unacceptable (transcript leakage, shared logs, or the user simply refuses — "i need a method for you to securely obtain credentials from me").
- Your agent terminal runs as a DIFFERENT local Windows account than the interactive shell the human uses (e.g. human is `alexz`, agent is `zqmco`). A naive `Export-Clixml` under the human's account is unreadable by the agent.
- You then need that secret to drive SMB mounts, SSH, Synology DSM API, WinRM `-Credential`, etc.

## Core technique: machine-scope DPAPI
Use `[System.Security.Cryptography.ProtectedData]::Protect/Unprotect` with `DataProtectionScope.LocalMachine`.
- LocalMachine scope = decryptable by ANY local account on the SAME PC. This is what bridges alexz → zqmco.
- User scope (`Export-Clixml` default, or `DataProtectionScope.CurrentUser`) is bound to the creating user and FAILS in another account with: "Key not valid for use in specified state."

The file stores only `{ "user": "<acct>", "data": "<base64 of DPAPI ciphertext>" }`. The plaintext password never hits disk or chat.

## Procedure

### STORE — human runs this in an INTERACTIVE PowerShell (typing hidden, nothing sent to chat)
Single line (paste-ready, in templates/store-cred-oneline.txt):
    $c=Get-Credential -Message "Credential (hidden, not sent to chat):"; New-Item -ItemType Directory -Force -Path C:\zqm\cred | Out-Null; $p=$c.GetNetworkCredential().Password; $b=[System.Text.Encoding]::UTF8.GetBytes($p); $e=[System.Security.Cryptography.ProtectedData]::Protect($b,$null,'LocalMachine'); [pscustomobject]@{user=$c.UserName;data=[Convert]::ToBase64String($e)} | ConvertTo-Json | Set-Content C:\zqm\cred\zqm-cred-<name>.json -Force; if (Test-Path C:\zqm\cred\zqm-cred-<name>.json) { Write-Host ("OK WROTE C:\zqm\cred\zqm-cred-<name>.json user="+$c.UserName) } else { Write-Host "WRITE FAILED" }

Rules:
- `New-Item -Force -Path <dir>` MUST run before `Set-Content` (Set-Content does NOT create parent dirs).
- The `if (Test-Path ...)` guard makes the success message HONEST. Without it, a failed write still prints "WROTE" (we hit this — the file was never created and the message lied).

### CONSUME — agent runs this (never prints plaintext)
Single line (in templates/use-cred-consumer.ps1 as a script, or inline):
    Add-Type -AssemblyName System.Security; $p="C:\zqm\cred\zqm-cred-<name>.json"; $o=Get-Content $p -Raw|ConvertFrom-Json; $enc=[Convert]::FromBase64String($o.data); $pw=[System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($enc,$null,"LocalMachine")); $sec=ConvertTo-SecureString $pw -AsPlainText -Force; $c=New-Object System.Management.Automation.PSCredential($o.user,$sec); Write-Host ("LOADED user: "+$c.UserName+" (password NOT printed)")

Then pass `$c` to `-Credential`, `Invoke-RestMethod -Credential`, `New-SmbMapping -Password $c.Password`, etc. NEVER call `$c.GetNetworkCredential().Password` in a statement you print, and never `Write-Host $pw`.

## Pitfalls (all hit and fixed in-session)
1. **`Unable to find type [System.Security.Cryptography.ProtectedData]`** — a FRESH PowerShell runspace (like the agent's) has not loaded the assembly. Always `Add-Type -AssemblyName System.Security` BEFORE using `[ProtectedData]`. The human's interactive shell may already have it loaded (so their store worked while your consume failed).
2. **Cross-account with user-scope DPAPI fails** — `Export-Clixml` written by `alexz` cannot be decrypted by `zqmco`: "Key not valid for use in specified state." Switch to `ProtectedData` + `LocalMachine`.
3. **`Set-Content` silent failure + false success** — if the target directory doesn't exist, Set-Content fails but a trailing `Write-Host "WROTE"` still runs. Guard with `New-Item -Force` + `Test-Path` check.
4. **Quoting/line-break in pasted one-liners** — when the user copies a multi-line command, backtick continuations can break. Prefer a single-line form (provided in templates). If the human reports "it printed WROTE but you can't find the file," suspect a path/translation issue (C:\zqm vs /c/zqm) AND a missing directory — verify with `Test-Path` via PowerShell, not bash `ls` (path translation can mislead).
5. **A rejected credential at the TARGET is NOT a handoff failure.** If the consumer loads fine (username prints) but the remote service says "invalid account/password" (e.g. Synology DSM error 101), the pipeline worked — the STORED secret is simply wrong. Re-run STORE with correct creds; don't debug the handoff.
6. **LocalMachine DPAPI trade-off** — any local admin on the box can decrypt the file. Fine for a solo LAN; unacceptable for shared/multi-tenant. State this to the user. If strict user-only isolation is required, run the agent as the SAME account the human uses instead.
7. **Running the consumer .ps1 from the agent's bash/terminal: `-File` path mangling.** The agent's PowerShell often launches under MSYS/git-bash, where backslashes in `-File C:\Users\...` get STRIPPED → `C:Users...` → "file does not exist"; and `cmd /c "... -File \"C:\...""` injects stray quotes → "Illegal characters in path." RELIABLE WORKAROUND: `cp` the script to a flat path like `C:\temp\probe.ps1`, then `cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\probe.ps1"`. Also: complex inline `-Command` blocks (indexed `$matches[1]`, nested calls) trip the PARSER with "MissingArrayIndexExpression" — prefer writing the script to a file and running it via `C:\temp\` over pasting multi-line `-Command` payloads. For raw TLS/HTTP probing, Python (execute_code) is more reliable than PS 5.1 and sidesteps all the quoting.

## Verification (prove the round-trip without exposing the secret)
After STORE, the agent loads and prints only:
    LOADED user: <username> (password NOT printed)
If that appears, the secret is in hand. Then attempt the real action (SMB map / DSM login) — a success there is the end-to-end proof.

## Cleanup
Delete the JSON when done: `Remove-Item C:\zqm\cred\zqm-cred-<name>.json -Force`. Treat it like a password file: do not sync to OneDrive or commit it.

## Support files
- `templates/store-cred-oneline.txt` — paste-ready STORE one-liner (human runs, hidden typing).
- `templates/use-cred-consumer.ps1` — agent-side consumer (loads, prints username only, optionally SMB-maps or is a starting point for DSM/SSH).
- `references/synology-dsm-api.md` — using the handed-off cred against Synology DSM (login API, error-code table, PS 5.1 self-signed-cert bypass). This was the first real consumer of the handoff in-session.
