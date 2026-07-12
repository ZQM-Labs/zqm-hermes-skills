---
name: windows-elevated-actions
description: Run PRIVILEGED Windows PowerShell actions (mount disks, firewall rules, service changes, anything needing admin) safely from a NON-elevated agent shell. Covers the UAC-denial trap where Start-Process -Verb RunAs -Wait reports success even when the prompt was dismissed, how to make scripts self-log to disk, and the mandatory re-verify-after-elevation step. Use whenever a PowerShell action fails with "Access is denied" or "CIM resource not available" and needs elevation — e.g. Set-Partition/Add-PartitionAccessPath (disk mount), New-NetFirewallRule, Set-Service, anything touching admin-only CIM.
---

# Windows Elevated Actions (from a non-elevated agent shell)

The agent terminal runs NON-elevated. Many real ops need admin: mounting a disk
(`Set-Partition -NewDriveLetter`), firewall rules (`New-NetFirewallRule`), service
config, etc. They throw `Access denied` / `Access to a CIM resource was not available`
when run non-elevated. This skill is the SAFE pattern to get them done.

## THE TRAP (cost me 3 failed attempts once)
`Start-Process powershell -Verb RunAs -Wait -ArgumentList "..."` does NOT report a
UAC denial as an error. If the user dismisses the UAC prompt (or it's silently
filtered because the parent shell isn't elevated), the process "returns" with
exit 0 and your script silently did NOTHING. You then verify and find the change
was never applied. Never trust "process returned."

## THE RELIABLE PATTERN
1. **Write the privileged script to a .ps1 file** (never inline PS — MSYS mangles `$`).
   Inside the script, wrap the action in try/catch and **write the outcome to a .log
   file on disk** (NOT just stdout — stdout from an elevated child may not reach you):
   ```
   $log = 'C:\Users\zqmco\thing_result.log'
   try {
       <the admin action, with -ErrorAction Stop>
       "OK: <what changed>" | Set-Content $log
   } catch {
       ("FAILED: " + $_.Exception.Message) | Set-Content $log
   }
   ```
2. **Launch elevated** from the non-elevated shell:
   `Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"<path>`""`
   This pops a UAC prompt on the user's desktop. They click yes.

   **PREFER BACKGROUND LAUNCH (no `-Wait`) for agent-driven elevation.** With `-Wait`, the
   agent's terminal HANGS until the human clicks the UAC prompt — a 120s tool timeout then kills
   it with no useful output, and the elevated process may never have started if the prompt was
   dismissed. Background pattern (non-blocking):
     powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"<path>`"'"
   Then tell the user "UAC prompt is on your desktop — click YES", and POLL the self-log +
   re-verify live state. Reserve `-Wait` only when the prompt will be answered instantly.
   Also: fire ONE elevated script per turn (batch all privileged writes into a single .ps1) —
   multiple `RunAs` calls pop multiple UAC prompts back-to-back and the user may dismiss the
   wrong one. Live case 2026-07-11: two RunAs launches in one turn confused the user; consolidated
   to one and it applied cleanly.
3. **RE-VERIFY against live system state** — read the .log, THEN independently confirm
   the change took (Get-NetFirewallRule / Get-Volume -DriveLetter D / Get-Partition).
   The log is a hint; the live state is truth.
   For a *visual* second opinion (e.g. confirm the UAC prompt appeared, or the new
   drive letter shows in File Explorer), the `computer-use` skill's `capture` tool is
   the right cross-check — drive the desktop, don't re-shell it.

## Why self-logging matters
When you launch elevated with `-Wait` and no redirect, you get zero output if UAC was
denied. The script writing its own .log means the result is on disk regardless of
whether the elevated stdout reached you. Read the .log with read_file after the launch.

## Diagnose permission need WITHOUT elevation
To confirm an action truly needs admin (vs a script bug), run it non-elevated via -File:
if it throws "Access is denied." → elevation is required and the UAC path is the only way.
If it throws something else → it's a logic bug; fix the script, don't escalate.

## Common admin-only ops (verify-after list)
- Mount disk: `Set-Partition -InputObject $p -NewDriveLetter D` → verify `Get-Volume -DriveLetter D`.
  NOTE: `Get-Partition.DriveLetter` is `[char]`; unmounted returns `'\\0'`, NOT $null.
  Test with `[string]::IsNullOrWhiteSpace($p.DriveLetter.ToString())` before assuming mounted.
- Firewall: `New-NetFirewallRule -DisplayName X -Direction Inbound -LocalPort 11434 -Protocol TCP -RemoteAddress 192.168.1.0/24 -Action Allow` → verify `Get-NetFirewallRule -DisplayName X | Get-NetFirewallAddressFilter`.
- Service: `Set-Service` / `Start-Service` → verify `Get-Service -Name X`.
- Anything touching Windows Defender / WinRM listener config → admin.

## LIVE PITFALLS (2026-07-11 hardening run — verified lessons)

### P1 — `Start-Process -Verb RunAs -Wait` BLOCKS the foreground terminal until UAC is clicked
Launching elevated with `-Wait` from the agent's bash/PowerShell terminal HANGS (foreground) until
the human clicks the UAC prompt — a 120s tool timeout then kills it with no useful output, and the
elevated process may never have started if the prompt was dismissed. **Fix:** launch elevated scripts
in the BACKGROUND (NO `-Wait`), tell the user "UAC prompt is on your desktop — click YES", then POLL
the self-log + live state. Pattern (background, non-blocking):
  powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"<path>\"'"
Then `read_file` the `.log` and re-verify live. The `-Wait` variant is only safe if you can guarantee
the prompt is answered within the tool timeout — prefer background + poll.

### P2 — a user-only-ACL'd file makes an elevated lockout-guard FALSELY refuse
Mutation B (sshd PasswordAuthentication no) is guarded: "if no `authorized_keys`, skip — would lock
out SSH." BUT if the non-elevated install step sets the file to user-only ACL (`zqmco:F`, no
SYSTEM/Admin), the ELEVATED script's `Get-Content $ak` can read EMPTY (admin token denied by the
stripped ACL), so `$akCount` computes 0 and the guard REFUSES even though the key is present. **Fix:**
make the elevated script SELF-CONTAINED — it copies the pubkey from `id_ed25519.pub` itself and sets
a permissive ACL (user+SYSTEM+Administrators FullControl) before the guard check, so the elevated read
always succeeds. Don't depend on a pre-written, tightly-ACL'd file being readable from the elevated
context. Reusable: `scripts/ssh_harden.ps1` (self-contained: installs key + ACLs + writes drop-in +
restarts sshd, all guarded).

### P3 — WinRM 5985 "disabled" but still 405 locally
Disabling `WINRM-HTTP-In-TCP` sets Enabled=False (PROVEN via `Get-NetFirewallRule`), but `:::5985`
still LISTENs and a LOCAL `curl http://127.0.0.1:5985` returns 405 — loopback isn't firewall-filtered
the same way. A 405 is NOT proof the rule is open to the LAN. To confirm the external drop, probe from
a DIFFERENT host (Node-2/3) or assert `Get-NetFirewallRule -Name WINRM-HTTP-In-TCP | Select Enabled`
is False. Don't mistake a local self-connect for an external open.

## Safety / consent
- NEVER auto-elevate silently. The UAC prompt is the user's explicit grant; surfacing the
  elevated command and letting them click yes IS the consent flow. Do not attempt to bypass
  UAC (no scheduled-task-trickery, no credential embedding).
  EXCEPTION: when the user EXPLICITLY grants self-elevation (e.g. "you can self-elevate, I give
  you approval"), proceed with the RunAs launch directly and do NOT re-gate — the explicit grant
  replaces the per-action UAC-click expectation. Still launch via the direct
  `powershell -NoProfile -Command "Start-Process ... -Verb RunAs"` form (see P13), never wrapped
  in `cmd.exe /c` (which swallows the elevation).
- NEVER put a password/credential in the script. For remote (WinRM) actions, prompt the
  user via `Read-Host -AsSecureString` inside the script, or use a session option that
  references a stored credential the user provided out-of-band.
- If a `clarify` times out, take the non-destructive path: write the script + hand the user
  the elevated command; do not guess at elevation.
- **Swarm tie-in:** inside a fleet-council-audit swarm, an elevated change's result must land
  in BOTH the self-log AND the swarm's `swarm_log`/`open_questions` (see fleet-council-audit →
  PERSIST FINDINGS TO SQLITE) so the coordination trail is honest. A privileged action that
  silently applied (or silently failed) is exactly the fact the blackboard/DB must record, not
  leave implicit. Cross-reference: fleet-council-audit owns the swarm shape; this skill owns
  the elevation mechanics.

## Remote execution via WinRM (fleet peers, from the non-elevated shell)
To run a privileged command ON A DIFFERENT node (e.g. probe Node-3 from the control
plane), use `Invoke-Command` over WinRM. The node creds live in `inventory.ini`
(Administrator, basic auth, cert validation ignored). Pattern:
- NEVER embed the password in the script or any file. Prompt at runtime with
  `Read-Host -AsSecureString` so the secret never enters the agent's context.
- `New-PSSession -ComputerName <ip> -Credential $cred -Authentication Basic
   -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck)`.
- Inside the remote `ScriptBlock`, gather facts and RETURN them (don't rely on a
  remote file write you can't read back). Re-verify the returned facts make sense.
- Test reachability first with `Test-WSMan -ComputerName <ip>` (no creds needed) —
  if that fails, the session will fail too; report the connectivity gap instead.
See `scripts/probe_remote_winrm.ps1` for the verified Node-3 Ollama probe used in
the 2026-07-10 swarm (self-documents the secure-credential + localhost-11434 check).

## Pitfalls
- `-Wait` + `-RedirectStandardOutput` are mutually exclusive parameter sets in Start-Process
  → pick `-Wait` (no redirect) and make the script self-log instead.
- Inline `-Command "..."` with `$_` breaks under MSYS bash → always `-File`.
- UAC dismissal = silent no-op, not an error. Always re-verify.
- A non-elevated `-ErrorAction SilentlyContinue` on Set-Partition returns no exception but the
  letter still won't apply → use `-ErrorAction Stop` + re-read the partition after.
- **ELEVATED CONTEXT CAN'T READ A USER-ONLY-ACL FILE (silent guard misfire).** If a non-elevated
  step locked a file to the user only (`icacls <f> /inheritance:r /grant:r "user:F"`), an elevated
  script run as the same user's ADMIN token may read it EMPTY. A guard that counts lines (e.g.
  "authorized_keys count > 0?") then sees 0 and WRONGLY REFUSES a safe mutation. FIX: (a) set the
  ACL to `user + SYSTEM + BUILTIN\Administrators` (all FullControl) so the elevated token can read
  it, OR (b) make the elevated script SELF-CONTAINED — have it write the file itself with the
  correct ACL + then do the mutation, rather than depending on a pre-existing user-locked file it
  can't see. Live case 2026-07-11: sshd hardening refused because authorized_keys was user-locked;
  rewrote the elevated script to install the key + ACL it itself, then it applied.
- **ONE UAC PROMPT PER TURN.** Firing several `Start-Process -Verb RunAs` in one turn pops multiple
  prompts back-to-back; the user may dismiss the wrong one and a privileged change silently no-ops
  (and `-Wait` would block on each). Collect every privileged write (fw rule + sshd drop-in + ACL)
  into a SINGLE .ps1 and launch it ONCE.
- **WinRM 5985 "disabled" but still 405 locally.** Disabling `WINRM-HTTP-In-TCP` sets Enabled=False
  (PROVEN via Get-NetFirewallRule), but `:::5985` still LISTENs and a LOCAL `curl http://127.0.0.1:5985`
  returns 405 — loopback isn't firewall-filtered the same way. A 405 is NOT proof the rule is open
  to the LAN. Confirm the external drop by probing from a DIFFERENT host (Node-2/3) or asserting
  `Get-NetFirewallRule -Name WINRM-HTTP-In-TCP | Select Enabled` is False. Don't mistake a local
  self-connect for an external open.
- Reusable scripts: `scripts/ssh_harden.ps1` (self-contained sshd key-only hardening — installs the
  pubkey with a permissive ACL, then writes the PasswordAuthentication=no drop-in + restarts sshd;
  fixes the P2 lockout-guard false-refusal). `scripts/probe_remote_winrm.ps1` (cross-node WinRM).
  `scripts/read_system_file.ps1` (P4 elevated reader), `scripts/read_defender_exclusions.ps1` (P10
  elevated Defender exclusion read), `scripts/disable_winrm_5985_all.ps1` (P6
  port+protocol sweep), `scripts/fix_authorized_keys_acl.ps1` (P5 rename-aware ACL),
  `scripts/silent_recon_skeleton.ps1` (full PASSIVE read-only enumeration — no Set/New/Disable; uses
  `-f` formatting so literal `[` brackets never abort the script, P7). For the full
  forensic-recreation methodology + the proven Ollama token-proxy pattern, see
  `references/forensic_elevation_runbook.md`.
  `scripts/read_system_file.ps1` (elevated reader for SYSTEM-owned files the non-elevated shell can't
  read — copies the target's content into a user-readable .log; see P4). `scripts/disable_winrm_5985_all.ps1`
  (disable EVERY inbound 5985 rule by port+protocol, not by DisplayName — fixes P6 duplicate-rule
  escape). `scripts/fix_authorized_keys_acl.ps1` (grants both `$env:USERNAME` AND the rename-aware
 account name + SYSTEM + Admin — fixes P5 account-rename SID/ACL mismatch).
 `scripts/disable_winrm_5985_listener.ps1` (P8 — surgically removes ONLY the HTTP listener by
 PATH, preserving HTTPS; avoids the wildcard `Remove-Item` that drops both). `scripts/probe_lan_ports.ps1`
 (P9 — READ-ONLY peer sweep to prove the real external surface after a single-host fix).
- **P4 — SYSTEM-owned files need an ELEVATED READER, not a non-elevated read.** Non-elevated
  `Get-Content` / `read_file` on SYSTEM-owned paths (e.g. `C:\ProgramData\ssh\*.pub` SSH host keys,
  owned by SYSTEM) returns "Permission denied" — even just to *read* them. Don't fight it with ACL
  hacks. Write a tiny ELEVATED script that copies the file's content into a user-readable `.log`
  (the content is public material — host keys are safe to display), launch it via RunAs (background,
  UAC prompt), then `read_file` the log. Reusable: `scripts/read_system_file.ps1 -File <target> -Log <out.log>`.
  Live case 2026-07-11: the three host public keys (RSA/ECDSA/ED25519) were unreadable non-elevated;
  the elevated reader dumped them cleanly. NOTE: always independently confirm the dump matches the
  file (re-read once more, or checksum) so a UAC dismissal (empty log) isn't mistaken for "no keys".

- **P5 — account-RENAME SID/ACL mismatch bricks the file you just protected.** The profile folder is
  `C:\Users\zqmco` but the live account is `ZQM-NODE-1\AlexZ` (account was renamed; `$env:USERNAME`
  returns `zqmco` but the SID's account name resolves to `AlexZ`). Granting only
  `$env:USERDOMAIN\$env:USERNAME` (= `ZQM-NODE-1\zqmco`) gives the ACE to a principal that does NOT
  match the actual token, so the non-elevated shell (running as `zqmco` = renamed `AlexZ` SID) is
  DENIED on its own file. Symptom hit 2026-07-11: a fix script reported "ACL repaired (user+SYSTEM+
  Admin)" but then `Get-Content authorized_keys` AND `bash cat` both returned "Access is denied".
  **Fix:** grant BOTH candidate identities — `$env:USERNAME` AND the rename-aware name
  (`ZQM-NODE-1\AlexZ`) — plus SYSTEM + BUILTIN\Administrators. Use well-known SIDs (SYSTEM,
  Administrators) when possible since they always resolve. Reusable: `scripts/fix_authorized_keys_acl.ps1`
  (adds all four, skips any that don't resolve). GENERAL RULE: on a host where the folder name ≠ the
  account name, never grant a single `$env:USERNAME` ACE and call it done.

- **P6 — duplicate firewall rules SHARE a DisplayName; disabling one leaves the other live.**
  `Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP'` (or matching by DisplayName) can return/disable only
  ONE rule even when TWO rules with the identical DisplayName exist. Live case 2026-07-11: we disabled
  `Windows Remote Management (HTTP-In)` (LocalSubnet) and reported WinRM 5985 "RESOLVED", but a SECOND
  `Windows Remote Management (HTTP-In)` (remote=Any) stayed `[True]` and `:::5985` kept answering —
  a forensic re-capture caught it. **Fix:** enumerate ALL inbound rules, filter by
  `LocalPort -eq 5985 -and Protocol -eq 'TCP'` across the WHOLE set (not by Name/DisplayName), and
  disable every match. Reusable: `scripts/disable_winrm_5985_all.ps1`. GENERAL RULE: when "disabling" a
  Windows firewall rule, iterate by port+protocol, not by a single DisplayName, or a twin rule survives.
- **P7 — a literal `[` inside a double-quoted interpolated string ABORTS the whole .ps1.** Inside
  `"... $($_.X) ..."`, a literal `[` (e.g. `"  TASK $($_.Name)  [$($_.State)]  $act"` or
  `"[ON] $dir"`) makes the PS parser expect an array index at that point →
  `Unexpected token 'TASK' in expression or statement` and the script dies before writing anything
  (so you get no log and no output — looks like a silent UAC denial). Hit it twice on the silent-recon
  script. **Fix:** never put a raw `[` in an interpolated string. Use the `-f` format operator
  (`"[{0}] {1}" -f $state,$dir`) OR assign the sub-values to plain `$vars` first and reference them
  without brackets. Applies to every self-logging/reader/elevated script you write. Reusable:
  `scripts/silent_recon_skeleton.ps1` uses `-f` throughout for exactly this reason.
- **P8 — removing the WinRM HTTP(5985) listener can ALSO drop the HTTPS(5986) listener.** `Remove-Item WSMan:\\localhost\\Listener\\*` (or deleting the HTTP listener object) can remove BOTH listener objects; the privileged log then shows AFTER = empty, and a re-probe of `.218:5986` returns closed while the `ZQM-WinRM-5986` firewall rule is STILL Enabled=True (nothing behind it). Symptom hit 2026-07-11: we killed 5985 to close plaintext, then found 5986 TLS was ALSO gone — not the intended "keep TLS, kill plaintext" state. **Fix (pick one):** (a) re-create the HTTPS listener — `New-Item -Path WSMan:\\localhost\\Listener -Transport HTTPS -Address * -CertificateThumbprint <thumb> -Force` then `Restart-Service WinRM`. **The `-Address *` is REQUIRED** — the bare command (`-Transport HTTPS -CertificateThumbprint <thumb> -Force`, no `-Address`) FAILS with "Cannot validate argument on parameter 'Address'. The argument is null or empty" (verified 2026-07-11: this exact omission broke the 5986 restore). A server-auth cert usually exists in `Cert:\\LocalMachine\\My`; fall back to any HasPrivateKey cert. To AVOID the collateral drop in the first place, kill 5985 by PATH, not wildcard — reusable `scripts/disable_winrm_5985_listener.ps1` removes only the HTTP listener object, preserving HTTPS. — OR (b) if NO cert exists, accept WinRM fully off (service Running but inert) and SAY SO; don't loop trying to re-bind. (c) If the GOAL was "WinRM fully off", the collateral drop is the desired end-state — just confirm BOTH 5985+5986 are gone and report "WinRM closed" rather than "TLS retained". GENERAL RULE: after any WSMan listener change, re-read `Get-ChildItem WSMan:\\localhost\\Listener` and assert the SURVIVING listener is the one you intended — the HTTP/HTTPS objects are independent and a wildcard delete does not discriminate.
- **P9 — single-host hardening does NOT mean the FLEET is closed.** A cross-host TCP probe (from Node-1 toward Node-2/3/4) is the only honest proof of external exposure, and it routinely reveals OTHER nodes still running the same risky service. Live 2026-07-11: closing Node-1's WinRM 5985 + Ollama :11434 left Node-2(.21)/Node-3(.46)/Node-4(.215) with **WinRM 5985 OPEN** and (N2,N4) **Ollama :11434 no-auth** — the fleet was the real exposure, not the one host. When "investigate fully" / "mutate" targets one node, finish by probing the peers and reporting the fleet-wide gap as a SEPARATE follow-up (per-host creds required). Reusable: `scripts/probe_lan_ports.ps1` (READ-ONLY LAN sweep — TCP-probes a port list across peer IPs to prove the real external surface; no elevation, edit the $peers/$ports arrays). Also `scripts/probe_remote_winrm.ps1` (already in this skill) generalizes to any port sweep across the LAN.

 - **P10 — Defender exclusions need an ELEVATED read; non-elevated returns empty, not an error.** `Get-MpPreference` (ExclusionPath / ExclusionProcess / ExclusionExtension, EnableControlledFolderAccess) and the `HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\{Paths,Processes}` registry keys are NOT readable from a non-elevated shell — you get a blank section with no exception, which is easy to misread as "no exclusions." Live 2026-07-11: a non-elevated `Get-MpPreference` returned nothing; the elevated read proved exclusions = `bounty-tools` + `_android` paths and 5 recon-tool processes (nuclei/amass/ffuf/katana/subfinder), ControlledFolderAccess=0 — benign (your own tooling). **Fix:** write an elevated self-logging script that dumps `Get-MpPreference` + the registry Paths/Processes subkeys to a `.log`, launch via RunAs (background, UAC), then `read_file` the log. Reusable: `scripts/read_defender_exclusions.ps1`.

 - **ORIENTATION — when the host has its own agent/KB folder, READ IT before acting.** If you find `~/zbit-knowledge-base`, `~/swarm`, or similar agent-memory dirs (often Defender-quarantined — a FALSE POSITIVE, not contamination), read `USER.md` / `SOUL.md` / `LESSONS_LEARNED.md` FIRST.
- **P11 — "I authorize the master key" is CONSENT, not SUFFICIENCY; the key must still be DISTRIBUTED.** When the user says "I'm at the keys, authorize the master key" (or similar), that is explicit verbal consent for fleet ops — but the local `id_ed25519.pub` is NOT yet on the peer nodes, so key-based login still FAILS (Permission denied). The gap is KEY DISTRIBUTION, not authorization. Fix path when the user is physically at the boxes: have them paste the pubkey onto each Windows peer's key file (`C:\Users\azelenski\.ssh\authorized_keys`, OR `C:\ProgramData\ssh\administrators_authorized_keys` if azelenski is a LOCAL ADMIN — OpenSSH-for-Windows ignores per-user keys for admin accounts), set ACL to user+SYSTEM+Administrators FullControl, then `Restart-Service sshd`. Verify with `ssh -o BatchMode=yes` key-only after. The agent NEVER sees passwords (SOUL.md rule #3) — the user does the console paste. GENERAL RULE: a "master key authorized" statement removes the consent gate; it does NOT bridge a missing-key auth rejection. Always probe key-auth (BatchMode) to confirm the key actually landed before claiming fleet access. Reusable alongside `scripts/ssh_harden.ps1` (which does the per-host install when run ON the box, or as the template the user pastes from).
- **P12 — OpenClaw gateway "startup_failed" = invalid `openclaw.json`, fix with `openclaw doctor --fix`.** Symptom: scheduled-task gateway won't start; `.openclaw/logs/stability/*startup_failed.json` says "Invalid config at openclaw.json". Root causes seen: missing `params.num_ctx` on Ollama model entries (needs 128000 / 262144 for native compat) + an UNKNOWN top-level key (e.g. `mcpServers` rejected by this version). Diagnostic (non-destructive): `openclaw doctor` prints the exact changes preview + "Unknown config keys". Repair: `openclaw doctor --fix` (first-party self-repair; auto-backs up to `openclaw.json.bak`). After fix, verify with `openclaw doctor` (no longer "Config invalid") and start the gateway — it binds `127.0.0.1:18789` (loopback) and logs "starting HTTP server". NOTE: `openclaw doctor --fix` can HANG at an interactive prompt if run with a TTY/foreground; run it foreground without piping (it writes the file then waits) — the file write completes even if the post-fix prompt blocks. Stop any manual test instance before letting the LogonTrigger task own the port to avoid a :18789 conflict. It tells you the host's real role (this box = DFORGE-11, the ZQM Hive orchestrator), your documented operating rules (e.g. "PowerShell via .ps1 files — bash strips `$`"), and the user's stated priorities (e.g. "SSH passwordless to all hosts" = exactly why key-only sshd hardening was on-target). Aligning actions with the KB's own intent prevents "fixing" something the user deliberately configured. A "CONTAMINATED" folder name is almost always a Defender FP on first-party code — confirm by reading, don't treat as threat.

- **P13 — wrapping the RunAs launch in `cmd.exe /c` SWALLOWS the elevation (silent no-op).** Live 2026-07-12: `cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"Start-Process powershell -Verb RunAs ...\""` produced NO log file and the privileged change never applied — the cmd wrapper hid/dropped the UAC prompt and the elevated child never executed. **Fix:** launch elevated DIRECTLY from the agent shell, with NO cmd.exe wrapper:
  `powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `\"<path>`\"'"`
  (background, non-blocking) then POLL the script's self-log + re-verify live. The `-Verb RunAs` MUST be the direct child of the agent's `powershell.exe`, not nested under `cmd.exe`.
- **P13b — a SYSTEM-owned scheduled task is INVISIBLE to a non-elevated `Get-ScheduledTask` (returns MISSING).** Live 2026-07-12: `Register-ScheduledTask` with `-Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount)` succeeded and ran (lastResult=0, proved via elevated re-query), but a non-elevated `Get-ScheduledTask -TaskName 'ZQM-Garden-Link'` returned MISSING. **Fix:** re-verify SYSTEM-owned tasks from an ELEVATED context (RunAs self-log script) — never trust a non-elevated MISSING for a SYSTEM-owned task. Trigger gotchas proven same run: `-RepetitionInterval` on `New-ScheduledTaskTrigger` REQUIRES `-Once` (or `-At`) as the base trigger type; and `-RepetitionDuration ([TimeSpan]::MaxValue)` overflows the scheduler (cap ~248 days) → just omit the duration cap for an unbounded 15-min repeat.
