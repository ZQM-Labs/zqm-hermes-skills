# Auto-start / persistence-surface inventory (Windows)

When the task is "resolve all auto-start items / what runs at boot / map the
bots' auto-start" — the surface is WIDER than Win32_Service. Cover these three
layers, and ALWAYS verify each resolved target actually exists.

## Layers to enumerate
1. **Win32_StartupCommand** — Run keys (HKLM/HKU) + the per-user Startup folder.
   Some `Command` values are bare `.lnk` / `.vbs` names (not full paths) that
   resolve against the Startup folder; others are full exe paths or `%windir%`
   expansions. `Location` tells you which (e.g. `Startup`, `HKU\...\Run`,
   `HKLM\...\Run`, `HKU\.DEFAULT\...\Run`, `Public`).
2. **Startup folder** — enumerate explicitly:
   `([Environment]::GetFolderPath('Startup'))` →
   `C:\Users\<user>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`.
   Watch for `desktop.ini` (noise, skip).
3. **Scheduled Tasks** — a component can be auto-started by Task Scheduler even
   when its Startup `.vbs` is dead. Filter by name:
   `Get-ScheduledTask | Where-Object { $_.TaskName -match "ZQM|Ollama|Hermes|Indexer|Gateway|OpenClaw" }`.
   Dump actions: `$t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }`.
   (Full scheduled-task audit recipe — triggers, LastTaskResult codes — is in
   command-bank.md under "scheduled-task custom-audit recipe".)

## Resolving .lnk targets (the real command line)
A `.lnk` hides TargetPath + Arguments + WorkingDirectory. Reveal with the
WScript.Shell COM object (PowerShell, single-quoted so MSYS doesn't eat `$`):
```powershell
$sh = New-Object -ComObject WScript.Shell
$l = $sh.CreateShortcut("C:\Users\zqmco\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk")
"TargetPath=$($l.TargetPath)"; "Arguments=$($l.Arguments)"; "WorkingDirectory=$($l.WorkingDirectory)"
```
**Gotcha:** `CreateShortcut` does NOT error if the target exe/script is missing
— it returns the intended path. You MUST `Test-Path` the resolved TargetPath
(and, for script args, the script file itself) to know if it actually runs.

## Reading a .vbs auto-starter
Start-here `.vbs` files are usually thin redirectors. Read the file
(`read_file`) and follow what they `Run`/`CreateObject`. They often point at a
SECOND script that may itself be missing (e.g. a Startup `Hermes_Gateway.vbs`
that launches `gateway-service\Hermes_Gateway.vbs` which doesn't exist).

## CRITICAL pitfall: stale / broken targets
In the ZQM-NODE-1 run, 3 of 4 custom auto-start items pointed at paths that did
NOT exist:
- Startup `Hermes_Gateway.vbs` → `gateway-service\Hermes_Gateway.vbs` (**missing**).
- `ZQM-Node-01-Indexer.lnk` → `OneDrive\Desktop\zqm-node-01-indexer\app.py` (**dir missing**).
- `ZQM-Skill-Automation-Center.lnk` → `AppData\Local\hermes\skills\...\serve_dashboard.py` (**only stale .pyc cache present**).
Only `Ollama.lnk` resolved to a real, existing target. So a "list the
auto-start" pass that stops at the `.lnk` path would report 4 live bots — wrong.

**When a target is missing, find the real code:**
```
search_files  path=C:\Users\zqmco  pattern=serve_dashboard.py  target=files
search_files  path=C:\Users\zqmco  pattern=Hermes_Gateway.vbs   target=files
```
The live code often lives elsewhere — here it was under
`OneDrive\Desktop\repos\<repo>\...`, not the path the `.lnk` named. Map the real
repo dir, note `app.py`/`config.json`/service-install scripts, and the logs dir
(separate — e.g. `AppData\Local\hermes\logs\`).

## Custom (non-Microsoft) service enumeration
```powershell
Get-CimInstance Win32_Service |
  Where-Object { $_.PathName -and $_.PathName -notmatch 'system32|svchost' } |
  Select-Object Name,DisplayName,PathName,State,StartMode | Format-List
```
Report Running vs Stopped/Manual. Note when NONE of the custom bots are
registered as services — they run via Startup folder / Scheduled Tasks instead.

## Output shape
A tight table per bot: | automation | mechanism (Startup .lnk / .vbs /
Scheduled Task) | resolved target | EXISTS? (✅ runs / ❌ broken) | real
code/config/logs path |. Lead with the broken-items finding, not a flat dump.
No secrets: don't print config.json / .env / token contents — note existence
only.
