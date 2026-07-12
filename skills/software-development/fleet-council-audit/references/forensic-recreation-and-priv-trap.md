# Forensic recreation & privileged-remediation traps (session 2026-07-11)

User idiom: "diagnostics and forensic science recreation" = INDEPENDENT RE-DERIVATION of
every prior claim from raw live state, written to a chain-of-custody artifact, NOT a
re-statement of the old report. The act of re-deriving often surfaces errors in the
original pass — treat that as a first-class finding, not embarrassment.

## 1. Forensic capture recipe (re-derive everything, non-elevated)
Write `forensic_capture.ps1` (or reuse) that dumps, self-logged to a .txt:
- OS via `Get-CimInstance Win32_OperatingSystem` (Caption/Build — NOT Get-ComputerInfo, which lies "Win10" on 24H2).
- Listening ports: `Get-NetTCPConnection -State Listen` (LocalAddress:LocalPort + OwningProcess).
- Key services: `Get-Service sshd,WinRM,OllamaService` + `Get-Process ollama,pythonw`.
- Firewall: every rule where DisplayName matches Ollama/OpenSSH/WinRM, with
  `Get-NetFirewallPortFilter` (LocalPort/Protocol) + `Get-NetFirewallAddressFilter` (RemoteAddress).
  PRINT `Enabled` for each — this is where duplicate/missed rules hide.
- SSH state: authorized_keys existence+line count, sshd_config.d presence, host pubkey filenames,
  authorized_keys ACL via `(Get-Acl $ak).AccessToString`.
- Ollama proxy chain: loopback 200, LAN no-token 401, LAN with-token 200.
- Artifact manifest: `Get-ChildItem` of the audit dir with size + mtime (chain of custody).
Persist the .txt path + key rows into the SQLite `probes` table as a recreation artifact.

## 2. TRAP: WinRM 5985 has TWO inbound rules — disabling one leaves the other ENABLED
The "Windows Remote Management (HTTP-In)" 5985 rule exists TWICE:
  - one with RemoteAddress=LocalSubnet (often already present)
  - one with RemoteAddress=**Any** (the genuinely open one)
Disabling by `-Name 'WINRM-HTTP-In-TCP'` hit only ONE; the `Any` rule stayed `[True]` and the
listener remained on `:::5985`. The original "RESOLVED WinRM plaintext" claim was WRONG until
this was caught by re-derivation.
FIX (idempotent, elevated): loop ALL inbound rules, match PortFilter LocalPort=5985 + TCP,
`Disable-NetFirewallRule` each. Then re-verify `Get-NetFirewallRule | ?{$_.LocalPort-eq 5985}`
shows ZERO `[True]`. Keep 5986 (TLS) enabled.

## 3. TRAP: over-strict ACL on authorized_keys blocks the ELEVATED mutation that needs it
To satisfy OpenSSH perms I ran `icacls authorized_keys /inheritance:r /grant:r "user:F"` —
that stripped SYSTEM/Admin ACEs, leaving the file **user-only**. A later elevated
`Start-Process -Verb RunAs` (even though it runs as the same user with admin token) got
"Access to the path is denied" when trying to read/append the key, so the sshd hardening
(Mutation B: PasswordAuthentication no) ABORTED — correctly, via the lockout guard, but the
root cause was MY earlier ACL change, not a missing key.
FIX: when writing authorized_keys from a non-elevated step but planning an elevated mutation
that touches it, set ACL to **user + SYSTEM + BUILTIN\Administrators** (FullControl each),
inheritance disabled. Template:
  $acl = New-Object System.Security.AccessControl.FileSecurity
  $acl.SetAccessRuleProtection($true,$false)
  $acl.AddAccessRule((New-Object FileSystemAccessRule("$env:USERDOMAIN\$env:USERNAME","FullControl","Allow")))
  $acl.AddAccessRule((New-Object FileSystemAccessRule("SYSTEM","FullControl","Allow")))
  $acl.AddAccessRule((New-Object FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")))
  Set-Acl $ak $acl
Then the elevated drop-in write + `Restart-Service sshd` succeeds.

## 4. Mutation-B sequencing that worked (lockout-guarded, reversible)
0. (non-elevated) ensure id_ed25519.pub exists; copy into authorized_keys (1 line); set ACL per #3.
1. (elevated, self-logging) write `C:\ProgramData\ssh\sshd_config.d\99-zqm-hardening.conf`:
     PasswordAuthentication no
     PubkeyAuthentication yes
     PermitRootLogin no
   then `Restart-Service sshd -Force`.
2. Re-verify: `Test-Path` drop-in; `Get-Service sshd` Running; attempt a key login + confirm
   password is refused. If authorized_keys had 0 usable keys, REFUSE (never disable password
   auth with no working alternative — that's the lockout guard).
NOTE: sshd reads sshd_config.d drop-ins; if none exist, PasswordAuthentication defaults ON.
Win OpenSSH for admins may use `administrators_authorized_keys` instead of `~/.ssh/authorized_keys`
— check BOTH when deciding where to install the key.

## 5. UAC prompt reliability
`Start-Process -Verb RunAs -Wait` in a FOREGROUND terminal call BLOCKS until the UAC prompt is
resolved; if the user doesn't click, the agent's terminal call TIMES OUT (exit 124) and you can't
tell if it ran. Prefer launching elevated scripts BACKGROUND (no -Wait) so the UAC appears
independently on the desktop and the self-log is written whenever the user authorizes. Then
poll the .log + live state. A UAC dismissal leaves the .log from the LAST successful run (stale)
— always re-read it AFTER launching, and confirm via live state, not the log timestamp.

## 6. "read them all" = read the SYSTEM-owned host public keys
Host keys in C:\ProgramData\ssh\*.pub are ACL-denied to the non-elevated MSYS shell (even via
cat). To display them: elevated `Get-Content` each (ssh_host_rsa/ecdsa/ed25519_key.pub) into a
self-log, then read the log. They are PUBLIC material (safe to show). User identity key lives
in ~/.ssh/id_ed25519.pub; Ollama has its own ~/.ollama/id_ed25519.pub (internal, not an SSH
login key). authorized_keys absence = why SSH key-auth can't be enabled yet.
