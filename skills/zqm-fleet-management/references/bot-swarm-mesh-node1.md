# Local Bot/Automation Swarm Mesh on Node-1 (ZQM-NODE-1)

Use when the user says "investigate all bots/automations", "mesh the bots
together", or "make the bots coordinate in swarms" on the control-plane laptop
(192.168.1.218). Covers enumeration + the coordination wiring proven working
2026-07-11.

## 1. Enumeration method (parallel council)
- Dispatch 3 leaf `delegate_task` agents in ONE batch: (A) scheduled tasks —
  filter non-`\Microsoft\*`, dump State/Triggers/Action(Execute+Arguments)/
  LastRunResult; (B) live process spawn-tree + listening ports via
  `Win32_Process` + `Get-NetTCPConnection`; (C) auto-start resolution —
  `Win32_StartupCommand` + Startup-folder `.lnk`/`.vbs` + custom services.
- LEAD re-verifies headline claims with live `Get-NetTCPConnection`,
  `Test-Path`/`ls`, and a direct spawn of whatever subagents claimed.
  Subagent summaries are self-reports, NOT verified facts.
- Startup folder:
  `C:\Users\zqmco\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`
  Resolve `.lnk` via `WScript.Shell.CreateShortcut` -> TargetPath/Arguments/
  WorkingDirectory. Resolve `.vbs` by reading its `target = "..."` line.

## 2. Broken-startup-link finding + fix
This session 3 of 4 custom Startup items pointed at MISSING paths; real code
lives under `OneDrive\Desktop\repos\...`:
- `Hermes_Gateway.vbs` -> missing `...\hermes\gateway-service\Hermes_Gateway.vbs`
  -> real: `OneDrive\Desktop\repos\hermes-config\gateway-service\Hermes_Gateway.vbs`
- `ZQM-Node-01-Indexer.lnk` -> missing `...\Desktop\zqm-node-01-indexer\app.py`
  -> real: `OneDrive\Desktop\repos\zqm-node-01-indexer\app.py`
- `ZQM-Skill-Automation-Center.lnk` -> missing `...\hermes\skills\...\serve_dashboard.py`
  -> real: `OneDrive\Desktop\repos\hermes-config\skills\skill-automation-center\scripts\serve_dashboard.py`
- `Ollama.lnk` was the only one with a valid target.
FIX: back up each original to `.bak`, then repoint (.lnk Arguments +
WorkingDirectory, .vbs target line) to the `repos\` paths. Verify each
`Test-Path` now returns True.

## 3. Two gateways — the collision question (RESOLVED)
- **OpenClaw gateway**: Scheduled Task "OpenClaw Gateway" ->
  `C:\Users\zqmco\.openclaw\gateway.cmd` ->
  `node ...\openclaw\dist\index.js gateway --port 18789`, loopback only.
  This is what the broken "Hermes_Gateway" Startup .vbs was meant to launch.
- **Native Hermes gateway**: runs `hermes_cli.main gateway run`; DEFAULT port
  is **8645** (`gateway.py:335` -> `help="Bind port (default: 8645)"`).
  -> NO collision with OpenClaw's 18789. Both can run simultaneously.
Decision: leave both, or disable the OpenClaw task if you want a single gateway.

## 4. Swarm coordination wiring (VERIFIED working)
- **Shared brain**: Ollama :11434. Both gateways set model
  `ollama/qwen3.6:latest` via `baseUrl: http://127.0.0.1:11434`.
- **Shared knowledge layer**: ZQM-Node-01-Indexer — Flask+Waitress HTTP on
  :5000 AND an MCP server (`mcp_server.py`; `mcp` SDK installed under
  Python312). Register it as a stdio MCP server in OpenClaw so gateway agents
  can call `search_files` / `rebuild_index` / etc. Edit
  `C:\Users\zqmco\.openclaw\openclaw.json`:
  ```json
  "mcpServers": [
    {
      "name": "zqm-node-01-indexer",
      "command": "C:\\Users\\zqmco\\AppData\\Local\\Programs\\Python\\Python312\\python.exe",
      "args": ["C:\\Users\\zqmco\\OneDrive\\Desktop\\repos\\zqm-node-01-indexer\\mcp_server.py"],
      "cwd": "C:\\Users\\zqmco\\OneDrive\\Desktop\\repos\\zqm-node-01-indexer",
      "env": {"PYTHONIOENCODING": "utf-8", "PYTHONPATH": "C:\\Users\\zqmco\\OneDrive\\Desktop\\repos\\zqm-node-01-indexer"}
    }
  ]
  ```
  OpenClaw spawns the MCP server per-agent-session (stdio) when an agent calls
  a tool — it will NOT appear in gateway logs until then. VERIFY by spawning
  `python mcp_server.py` and doing initialize -> tools/list (8 tools) ->
  tools/call search_files (real hits).
- **Shared state/identity backbone**: Skill-Automation-Center :9000 (Flask).
  `zqm_auth` = per-user bearer token in `~/.zqm-auth/token`;
  `zqm_multi_tenant_db` / `zqm_user_resolver` = per-user `~/.zqm-data/<user>/`
  + per-user `state.db` (WAL, busy_timeout). All bots read/write ONE per-user
  coordination store -> that is the swarm's shared memory.

## 5. MCP server `call_tool` SDK-signature bug (FIX)
`indexer/mcp_server.py` used the OLD handler signature
`async def call_tool(request: CallToolRequest)` and raised
`call_tool() takes 1 positional argument but 2 were given` on `tools/call`.
The installed `mcp` SDK (>=1.x) invokes the decorated handler as
`func(tool_name, arguments)`. Fix (back up first):
```python
@self.server.call_tool()
async def call_tool(tool_name: str, arguments: dict) -> CallToolResult:
    arguments = arguments or {}
    # body already used tool_name/arguments; drop the old `request.params.*` lines
```
After fix, `tools/call search_files` returns real workstation hits.

## 6. Whoosh index rebuild — crash-loop ROOT CAUSE + recovery
Symptom: `app.py` (indexer HTTP :5000) throws repeatedly
`FileNotFoundError ... MAIN_xxxx.seg` and crash-loops. The `.seg` it wants
vanishes because a REBUILD deleted the dir under it.

ROOT CAUSE = CONCURRENT rebuilds, not a corrupt store. `build_index(rebuild=True)`
does `shutil.rmtree(INDEX_DIR)` then `create_in` — so TWO+ processes running
`build_index`/`app.py` AT ONCE delete each other's segments. This session had
FOUR contenders (3 separate `python -c "build_index(...)"` PIDs + the old
`app.py`) all stomping `~/.zqm-node-01-indexer/index`. Killing only the looping
`app.py` does NOT fix it — a sibling rebuild deletes the index again.

RECOVERY (order matters):
1. List EVERY python proc touching the indexer, not just the looping one:
   `Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python' -and $_.CommandLine -match 'app.py|build_index|mcp_server' }`
   Kill ALL of them (Stop-Process -Force). Leave Hermes agents + skill-center alone.
   ⚠ A stray MCP-server subproc spawned by an earlier verify run holds the
   WRITELOCK too — it shows up here, kill it.
2. `rm -rf ~/.zqm-node-01-indexer/index` (+ `metadata.db*`). If `rm` says
   "Device or resource busy" it means a killer missed a holder — re-list and kill.
3. Run `build_index(rebuild=True)` EXACTLY ONCE, as a background job
   (`terminal(background=true)`), then `process(action=wait)` on that session.
   Do NOT run it foreground — the 600s foreground cap kills the sweep mid-way.
   Do NOT poll the log with identical `tail` commands (loop-warning); check the
   `BUILD DONE` marker or proc liveness differently each time.
4. `build_index` is synchronous and writes `config.json` only at the very END,
   and commits the Whoosh writer every 100 docs (`batch_since_commit >= 100`).
   So even an INTERRUPTED build leaves a PARTIAL-but-VALID index (real `.seg`/`.toc`)
   that `app.py` can serve — you do NOT need the full sweep to bring the bot up.

## 8. Defender real-time-scan I/O WEDGE (full-workstation scan)
The full `build_index` crawl (`DEFAULT_SCAN_ROOTS` = C:\, Program Files, Users,
Windows, ...) calls `extract_text_content` on every file. With Defender
real-time protection ON this gets I/O-wedged: the proc stays "alive" but burns
~0.03s total CPU after 30 min and the log barely advances
(24,400→24,500 over several minutes). It may NEVER finish.
Mitigations (pick per situation):
- **You don't need the full sweep.** A single clean rebuild with batched commits
  (step 6.3) yields a serveable partial index. Start ONE `app.py` on it and prove
  `search_files` returns hits — that's sufficient to verify the swarm link.
- **Narrow the roots.** Pass a smaller `root_paths` to `build_index` (e.g. just
  `OneDrive\Desktop`) to validate fast, or persist a trimmed `DEFAULT_SCAN_ROOTS`
  that EXCLUDES the slow/huge trees (node_modules, C:\Windows\WinSxS,
  ProgramData package caches, \.git/objects).
- **Don't block on a wedged build.** If the proc is alive but frozen, kill it and
  serve the committed partial index; widen scan roots later when you have time.

## 7. Security flag
`C:\Users\\zqmco\\.openclaw\\openclaw.json` and `devices/paired.json` contain
PLAINTEXT gateway + operator tokens (loopback-only exposure). Rotate when
convenient — the bind is loopback so exposure is local-file only, but anyone
with file read on the box gets admin gateway access.

## 9. USER CONSENT GATE ON DESTRUCTIVE LOCAL ACTIONS (2026-07-11)
Killing a running service / `rm -rf` on the user's own box is destructive.
If the approval gate returns `BLOCKED: User denied this command`
(e.g. when you try `Stop-Process` / `rm -rf` the wedged `build_index`),
the CORRECT response is:
- STOP that workflow immediately. Take NO further destructive action.
- Do NOT retry the kill. Do NOT rephrase it. Do NOT route around it with a
  "different" command that achieves the same outcome (that is still a
  destructive kill the user already denied).
- Do NOT keep polling the log / "waiting" as if you will proceed anyway.
- Report the live state (which indexer PIDs are still alive, what index
  segments are on disk) and offer concrete, mutually-exclusive options, e.g.:
  (a) approve killing the wedged build + the looping app.py, then start ONE
      clean app.py on the committed index;
  (b) approve only killing the wedged build;
  (c) the user handles the processes themselves and tells you when the
      indexer is up clean.
Then WAIT for the user's selection. This overrides any momentum toward
"just fix it."
The crash-looping `app.py` and the wedged `build_index` are SEPARATE processes;
do not assume a denial aimed at one also covers the other, and do not use that
as an excuse to kill the other "since it wasn't the one blocked." When in
doubt, ask. This session the agent got the kill blocked TWICE and kept pushing
— wrong. The consent gate is a hard stop, not a soft suggestion.
