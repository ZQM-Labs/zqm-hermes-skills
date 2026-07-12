# Windows "Bots & Automations" Audit (ZQM-NODE-1 class)

Method for enumerating EVERY autonomous/recurring execution surface on a Windows box
when the user asks "what bots/automations run on this node."

## Why a dedicated method
A plain running-process list misses most automations: scheduled tasks, logon-startup
shortcuts, and (critically) windowless launchers. This session the user asked exactly
this; the reusable discipline is below.

## Enumeration surfaces (run ALL)
1. **Scheduled tasks** — `Get-ScheduledTask` (State Ready/Running = enabled). 205 defined
   on Node-1; ~95% are stock Windows housekeeping. Filter to user-authored: tasks under
   `\` root with non-Microsoft publishers, or anything whose Action points at a user path
   (`C:\Users\...`, `C:\Users\zqmco\.openclaw\...`). Capture Action + Triggers.
2. **Startup shortcuts** — `Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\*.lnk"`.
   Resolve each `.lnk` target (see technique below) to detect DEAD links (target missing).
3. **Run / RunOnce keys** — `HKLM:\` + `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run*`.
   Use `Get-ItemProperty`; ignore the stock `SecurityHealth`, `msedge`, `OneDrive`,
   `GoogleDriveFS`, `Chrome` auto-launch entries unless they matter.
4. **Running server/bot processes** — `Get-CimInstance Win32_Process` filtered on name OR
   CommandLine match: `python|pythonw|node|ollama|go\.exe|java|docker|comfy|server|agent|bot|watch`.
5. **Listening ports** — `Get-NetTCPConnection -State Listen`, resolve owner via
   `Get-Process -Id $_.OwningProcess`. Cross-ref against the process list to confirm what
   actually holds a port vs what is merely installed.
6. **Container/workload hosts** — `wsl --list --verbose`, `docker ps -a` (daemon may be down
   → "failed to connect" is expected if Docker Desktop isn't running; not an error to fake).
7. **Hermes cron** — `cronjob action='list'` from the agent. Local-only; output goes to the
   job log, not back into the chat. Empty list = no scheduled Hermes automations.

## PITFALL: `pythonw.exe` is missed by a `python` name regex
A `Where-Object { $_.Name -match 'python' }` filter does NOT match `pythonw.exe` — the
windowless launcher used by Startup `.lnk` shortcuts. This session the Indexer +
Automation-Center shortcuts launched `pythonw.exe` with a hidden window, so they never
appeared in the `python` match. To confirm whether a pythonw bot is actually running, run a
SEPARATE query: `Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'pythonw.exe' }`.
Rule: when auditing bots, query `python` AND `pythonw` separately (and `node`, `ollama`).

## TECHNIQUE: resolve `.lnk` targets to catch dead autoruns
A Startup `.lnk` can exist but point at a deleted script. Resolve it:
```powershell
$sh = New-Object -ComObject WScript.Shell
$l = $sh.CreateShortcut('C:\Users\zqmco\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\ZQM-Node-01-Indexer.lnk')
"$l.TargetPath | $l.Arguments"
```
Then `Test-Path $l.TargetPath`. If missing -> dead link firing every logon. This session two
shortcuts (ZQM-Node-01-Indexer, ZQM-Skill-Automation-Center) pointed at scripts that no
longer existed on disk; `pythonw.exe` count was 0, confirming they were silent failures.

## Reconcile "registered" vs "running"
- A process in step 4 with no entry in steps 1-3 = launched manually / by another parent
  (e.g. Hermes agent, OpenClaw gateway spawned by a task).
- A step 1/2 entry with NO live process = the automation is registered but not currently
  executing (dead link, crashed, or conditional trigger). Report both states explicitly.

## Delivery
Write the consolidated inventory to a file (e.g. `C:\Users\zqmco\ZQM-NODE-1_BOTS_AUDIT.txt`)
and summarize in plain terminal text: group into (a) ACTIVE agents, (b) DEAD/BROKEN autoruns,
(c) registered-but-not-running, (d) flags (LAN-exposed ports, missing scripts).
