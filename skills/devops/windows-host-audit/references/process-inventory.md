# Live bot / automation / AI-agent process inventory + spawn tree

Class of task: "what automation/bot/agent processes are actually running on this
Windows host? give me PID, path, command line, parent PID, memory, listening
ports, and confirm/deny specific components, then build the spawn tree."

Verified method from the ZQM-NODE-1 inventory (2026-07-10). Read-only.

## Capture (run from git-bash)
```bash
# 1. All processes -> JSON (CIM, NOT Get-Process: gives ExecutablePath +
#    CommandLine + ParentProcessId + WorkingSetSize).
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
  'Get-CimInstance Win32_Process | Select-Object ProcessId,Name,ExecutablePath,CommandLine,ParentProcessId,WorkingSetSize | ConvertTo-Json -Depth 2' > /tmp/procs.json

# 2. Listening ports -> PID.  DO NOT use Get-NetTCPConnection -> ConvertTo-Json
#    (see gotcha below).  Use netstat -ano through cmd.exe for an authoritative map.
cmd.exe /c "netstat -ano | findstr LISTENING" > /tmp/ports.txt
```
Parse with Python: build `pid -> proc`, derive `pid_ports` from the
`addr:port   PID` columns of ports.txt, then emit a parent->child tree.

## GOTCHA — Get-NetTCPConnection -> ConvertTo-Json mangles OwningProcessId
`Get-NetTCPConnection -State Listen | Select-Object LocalAddress,LocalPort,OwningProcessId | ConvertTo-Json`
returns **OwningProcessId: null for EVERY row** (PowerShell's JSON serializer
drops the CIM uint property). If you key a port->PID map on that, you get one
`None` bucket and silently lose every owner. The `Format-Table` view shows the
PID fine, but it is not programmatically usable.
**Fix:** `netstat -ano` (via `cmd.exe /c`) is the authoritative, parseable
port->PID source. Columns: `proto  localaddr:port  foreign  state  PID`.
Optionally corroborate with the `Format-Table` form of Get-NetTCPConnection if
you want the PowerShell-native view, but trust `netstat -ano` for the mapping.

## Exclude the agent's OWN audit noise
Your inventory run spawns subprocesses that show up in the scan:
`bash.exe -c "...hermes-snap..."`, `powershell.exe -Command "Get-CimInstance Win32_Process..."`,
`head.exe -80`, `python.exe .../hermes.exe` (this agent's own sessions).
Filter them out so they don't pollute the bot list:
```python
noise_re = re.compile(r'hermes-snap|procs\.json|ports\.json|win32_process|get-nettcp|Win32_Service|CONVERTTO-JSON|Get-CimInstance', re.I)
```
Note: the *legitimate* Hermes/ollama/openclaw processes have stable, identifiable
command lines (`python.exe hermes.exe`, `ollama.exe serve`, `openclaw\dist\index.js gateway`) —
keep those; only drop rows whose command line contains audit-fingerprint strings.

## Confirm a specific component: check PROCESSES AND SERVICES
A component can be present as a stopped Windows service with no live process.
So "is X running?" = scan processes AND registered services:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
 'Get-CimInstance Win32_Service | Where-Object { $_.Name -match "ollama|hermes|cua|zqm|skill|openclaw|automation|index|gateway" } | Select-Object Name,DisplayName,State,StartMode,PathName | Format-Table -AutoSize | Out-String'
```
(Single-quote the PS, or `$_` gets bash-expanded — see SKILL.md §0.)
In the ZQM-NODE-1 run this caught that **cua-driver, ZQM-Node-01-Indexer, and
ZQM-Skill-Automation-Center had NEITHER a process NOR a registered service**
-> genuinely not running, not just idle.

## Build the spawn tree
```python
by = {p['ProcessId']: p for p in procs}
children = {}
for p in procs:
    children.setdefault(p['ParentProcessId'], []).append(p['ProcessId'])
# walk from a known root (component PID, or explorer.exe/svchost) and indent.
```
Attach `pid_ports` (from netstat) and `WorkingSetSize/1048576` (MB) to each node.

Tree for the ZQM-NODE-1 live set:
```
explorer.exe (4992)
└─ ollama app.exe (13240)  -> 127.0.0.1:49672
   └─ ollama.exe serve (11556) -> 0.0.0.0:11434          [LLM server]
cmd.exe (8588)                                      [launcher, parent 8972 exited]
└─ node.exe (12676) openclaw gateway --port 18789 -> 127.0.0.1:18789   [Hermes gateway]
powershell (22220) -> hermes.exe (8476) -> python (10936) -> worker (23768, 197MB)
powershell (2184)  -> hermes.exe (22636) -> python (22844) -> worker (22200, 176MB)
```
(WebView2 children of `ollama app.exe` are GUI renderers/gpu/network helpers,
not the model server — they belong to the app host, not `ollama.exe serve`.)

## Output shape that worked
A table per confirmed component (PID / PPID / Path / Cmd / Mem / Ports), then a
plain-text spawn tree, then a CONFIRMED-ALIVE vs NOT-FOUND ledger for each
named component the user asked about. Lead with the confirmation/denial verdicts.
