# Auto-start repair — fixing dead Startup `.lnk` / `.vbs` bots

Detection (see `references/auto-start-inventory.md`) often finds Startup-folder
links whose target script no longer exists. This is the REPAIR recipe used live
on ZQM-NODE-1 (2026-07-10): 3 of 4 custom automations were dead links
(Hermes_Gateway.vbs, ZQM-Node-01-Indexer.lnk, ZQM-Skill-Automation-Center.lnk);
all 3 were repointed at their real `OneDrive\Desktop\repos\` code and verified.

## When to use
After an audit reports a `.lnk`/`.vbs` whose resolved target `Test-Path` = False.
The real code almost always lives under `OneDrive\Desktop\repos\<name>\`
(NOT the `AppData\Local\hermes\skills\...` or bare `Desktop\` path the link claims).

## Recipe (read-only safe — edits only link target lines, never kills processes)
1. **Backup first:** `Copy-Item <link> <link>.bak -Force` for every item.
2. **`.vbs` redirector:** read with `Get-Content -Raw`, string-replace the
   `target = "C:\old\path.vbs"` line, write back with `Set-Content -NoNewline`.
3. **`.lnk`:** use `WScript.Shell.CreateShortcut(<path>)`, then set
   `.Arguments` (the script path) AND `.WorkingDirectory` (script's dir), call
   `.Save()`. Do NOT just change `TargetPath` — for pythonw bots the launcher
   (`pythonw.exe`) is fine; the broken part is the `.py` inside `Arguments`.
4. **Re-verify:** `Test-Path` the **trimmed `Arguments`** value
   (`$l.Arguments.Trim('"')`). Confirm = True before declaring fixed.

## Re-runnable template
`scripts/repair-broken-startup.ps1` — copy it, edit the `$fixes` array
(type/old/new per link), run `powershell -NoProfile -ExecutionPolicy Bypass
-File <script>`. It backs up, edits, and prints a per-item verification line.

## Caveats
- **Two-gateway risk:** if you repair a Hermes gateway link, confirm it won't
  collide with an already-running gateway (e.g. OpenClaw on :18789). Check
  listening ports first; prefer logon-launch over forcing a second instance.
- **Launch-verify after fix:** double-click the `.lnk`/`.vbs` in a hidden window
  and confirm it stays up + which port it binds, OR leave it for next logon.
- **Plaintext tokens:** if the real code's config holds secrets (OpenClaw
  `openclaw.json`, `devices/paired.json`), flag for rotation — never print them.
