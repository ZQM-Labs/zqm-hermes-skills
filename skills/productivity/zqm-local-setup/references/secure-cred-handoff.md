# Secure Credential Handoff (DPAPI SecureString)

Problem: the user must give the agent a real credential (Synology admin, Node local
account) to do LAN management, but pasting it in chat exposes it in the transcript.

Solution: the user captures the secret in THEIR interactive shell (typing hidden,
never echoed), encrypts it with Windows DPAPI at **LocalMachine scope**, and the agent
consumes it as a `PSCredential` — the plaintext password is never converted to a
printable string in any command the agent runs or prints.

## The reusable scripts (in `C:\Users\zqmco\` and staged on `\\192.168.1.40\web\`)
- `zqm-store-cred.ps1`  — USER runs it; **parameterized** (`-Name <tag>`, default `node-local`) → `C:\zqm\cred\zqm-cred-<tag>.json`. Stores as LocalMachine-DPAPI JSON and **self-verifies**: re-decrypts and only prints `OK` if the roundtrip succeeds (kills the silent-`Set-Content` false-success trap). Run: `powershell -ExecutionPolicy Bypass -File \\192.168.1.40\web\zqm-store-cred.ps1 -Name node-local`.
- `zqm-use-cred.ps1`    — AGENT runs it; loads JSON via `ProtectedData.Unprotect(...,LocalMachine)`, uses SecureString only. `-Name` selects which file.
- `zqm-cred-cleanup.ps1`— removes stored JSON(s) when done.

## Verified one-liner (USER runs, hidden typing, LocalMachine scope)
    $c=Get-Credential -Message "Synology admin cred (hidden):"; New-Item -ItemType Directory -Force -Path C:\zqm\cred | Out-Null; $p=$c.GetNetworkCredential().Password; $b=[System.Text.Encoding]::UTF8.GetBytes($p); $e=[System.Security.Cryptography.ProtectedData]::Protect($b,$null,'LocalMachine'); [pscustomobject]@{user=$c.UserName;data=[Convert]::ToBase64String($e)} | ConvertTo-Json | Set-Content C:\zqm\cred\zqm-cred-garden-admin.json -Force; if (Test-Path C:\zqm\cred\zqm-cred-garden-admin.json) { Write-Host ("OK WROTE C:\zqm\cred\zqm-cred-garden-admin.json user="+$c.UserName) } else { Write-Host "WRITE FAILED" }
This writes only `user` + a LocalMachine-encrypted blob — never the password in clear.
Then tell the agent "done" — it loads `C:\zqm\cred\zqm-cred-garden-admin.json`.
BUG WE HIT (2026-07-10): the ORIGINAL one-liner omitted `New-Item -ItemType Directory
-Force -Path C:\zqm\cred` and had an UNCONDITIONAL `Write-Host "WROTE ..."`. `Set-Content`
does NOT create missing parent dirs, so it silently failed while still printing success —
the file was never created and the agent couldn't load it. The fixed line above creates the
dir FIRST and only reports OK behind a `Test-Path` guard. `zqm-store-cred.ps1` does the same.

## Agent consumption (what the agent runs)
    powershell -ExecutionPolicy Bypass -File scripts\zqm-use-cred.ps1 -Name garden-admin -ComputerName 192.168.1.40
Prints only: `Loaded credential for: <username>` — password stays SecureString.
In code, pass `$c` (PSCredential) to `New-SmbMapping -Password $c.Password`,
`Invoke-RestMethod -Credential $c`, or `New-PSSession -Credential $c`.
NEVER call `$c.GetNetworkCredential().Password` in a command you print.

## Pitfalls (all hit and fixed this session)
1. CROSS-ACCOUNT DPAPI FAILURE — "Key not valid for use in specified state."
   User-scope DPAPI (`Get-Credential | Export-Clixml`) binds the ciphertext to the
   user+PC that created it. On this host the USER shell is `zqm-node-1\alexz` but the
   AGENT session is `zqmco`, so user-scope ALWAYS fails here. FIX: use **LocalMachine
   scope** (the one-liner above / `zqm-store-cred.ps1`) so any local account on the PC
   can decrypt. Do NOT tell the user to "re-store under zqmco" — their shell is alexz
   and that won't work. Verify agent's user with `powershell -NoProfile -Command '$env:USERNAME'`.
2. EXECUTION POLICY — `.ps1` files may be blocked:
   "File ... cannot be loaded because running scripts is disabled on this system."
   FIX: agent runs scripts with `powershell -ExecutionPolicy Bypass -File ...`;
   for the user, inline one-liners avoid the block entirely, or
   `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` (current shell only).
3. MICROSOFT/EMAIL ACCOUNTS — a `zqmcomputing@gmail.com` login is REJECTED by
   WinRM NTLM over workgroup ("Access is denied" at the auth layer, not password).
   Always create a pure LOCAL admin (e.g. `zqmlocal`) for remoting; do not reuse
   the Gmail password for the local account.
4. SET-CONTENT SILENT FAIL + FALSE SUCCESS — `Set-Content C:\zqm\cred\file.json`
   fails if `C:\zqm\cred` doesn't exist, and a trailing `Write-Host "WROTE ..."` runs
   regardless, so the user thinks the cred was stored when it wasn't (this bit us in
   session). FIX: `New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null`
   BEFORE Set-Content, and gate the success message behind `if (Test-Path $Path)`. Both
   the one-liner above and `zqm-store-cred.ps1` do this.

5. USER CANNOT OPEN THE `\\192.168.1.40\web` UNC — only the agent's `zqmco` session holds
   the cached Garden-02 SMB credential, so the user's interactive `alexz` session gets
   "file does not exist" / path-not-found on `\\192.168.1.40\web\zqm-store-cred.ps1`.
   FIX: the scripts ALSO exist locally on Node-1 at `C:\Users\zqmco\zqm-*.ps1` — have the
   user run those (native backslashes work in their PS). Only the agent's bash `cp` can
   use the UNC. If the share must be used, copy it local first:
   `copy \\192.168.1.40\web\zqm-store-cred.ps1 C:\temp\` then run `C:\temp\zqm-store-cred.ps1`.
6. STORE `zqmlocal` ON NODE-1, NOT NODE-2 — the fleet loop runs from Node-1 and reads
   `C:\zqm\cred\` on Node-1, so the cred only needs to live there. Do NOT tell the user to
   store it on Node-2 and copy it to Node-1 (that was overcomplicated and was corrected
   this session). Node-2 already has `zqmlocal` + open 5985; storing the password in
   Node-1's DPAPI store is all that's missing.

## Cleanup
    powershell -ExecutionPolicy Bypass -File scripts\zqm-cred-cleanup.ps1 -Name garden-admin
(or `-Name all`). Treat `zqm-cred-*.json` like a password file: don't sync to
OneDrive or commit it. Also remove any stray user-scope XML the user may have created
earlier (e.g. `C:\Users\AlexZ\zqm-cred-garden-admin.xml`).

## Session outcome (2026-07-10)
- The user stored a Synology cred via the OLD user-scope one-liner; it landed under
  `C:\Users\AlexZ\` (user is alexz) while the agent is zqmco -> decrypt failed with the
  cross-account error. This PROVED the security model works (a stranger account can't
  read the secret) but also proved user-scope is the wrong default here.
- Resolution: switch to LocalMachine-scope DPAPI (one-liner above). SMB write to
  Garden-02 (`\\192.168.1.40\web`) already works without creds (cached session), so the
  bootstrap/fleet scripts are staged there for grab-and-run.
