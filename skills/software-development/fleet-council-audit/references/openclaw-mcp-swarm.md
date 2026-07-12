# OpenClaw gateway MCP swarm-registration (ZQM-Node-1, 2026-07-11)

## What this proves
A bot that exposes an MCP server can be registered into the OpenClaw gateway
(`~/.openclaw/openclaw.json` -> `mcpServers[]`) so that every gateway agent
(OpenClaw's own agents, and the native Hermes gateway if it boots) can CALL the
bot's tools. That is the concrete swarm coordination channel: bots share each
other's capabilities without bespoke IPC.

## Why this is the right wiring
- OpenClaw natively supports stdio MCP servers (CHANGELOG "add stdio to
  McpServerSchema transport union"; dist has `resolveStdioMcpServerLaunchConfig`,
  `assertSupportedSessionSetup(mcpServers)`, "Configure MCP on the OpenClaw
  gateway or agent instead"). So the gateway consumes the bot, no glue code.
- The bot side is already there: the indexer's `mcp_server.py` exposes
  `search_files`, `get_index_stats`, `rebuild_index`, `find_files_by_type`,
  `find_large_files`, `find_recent_files`, `list_filters`, `search_stats` and
  has a `main()` + `__main__` entrypoint. It needs the `mcp` PyPI SDK installed
  (verified present under Python312) plus its own deps (whoosh/flask/waitress).
- Shared STATE/IDENTITY backbone already exists in the Skill-Automation-Center:
  `zqm_auth` (per-user bearer token in `~/.zqm-auth/token`), `zqm_multi_tenant_db`
  + `zqm_user_resolver` (per-user `~/.zqm-data/<user>/` + per-user state.db with
  WAL + busy_timeout). So bots already write to one coordination store.

## Registration recipe (verified)
1. Pre-flight (non-destructive): confirm the bot's MCP entrypoint imports under
   its Python and the SDK is present:
   `python -c "import mcp, mcp_server; print('ok')"`
2. Back up `openclaw.json` (it may contain PLAINTEXT tokens - never print them).
3. Edit JSON to add an `mcpServers` entry. Exact shape OpenClaw accepts
   (from dist `mcp-stdio` module): `name`, `command`, `args`, `cwd`, `env`.
   Example (indexer):
   ```json
   {
     "name": "zqm-node-01-indexer",
     "command": "C:\\Users\\zqmco\\AppData\\Local\\Programs\\Python\\Python312\\python.exe",
     "args": ["C:\\Users\\zqmco\\OneDrive\\Desktop\\repos\\zqm-node-01-indexer\\mcp_server.py"],
     "cwd": "C:\\Users\\zqmco\\OneDrive\\Desktop\\repos\\zqm-node-01-indexer",
     "env": { "PYTHONIOENCODING": "utf-8",
              "PYTHONPATH": "C:\\Users\\zqmco\\OneDrive\\Desktop\\repos\\zqm-node-01-indexer" }
   }
   ```
   Use a Python script (`json.load`/`json.dump`) to edit so existing tokens are
   preserved verbatim - do NOT hand-rewrite the file.
4. PROVE the link with `scripts/swarm_mcp_probe.py` (spawns the exact stdio
   server, does initialize + tools/list, prints the advertised tools). If it
   returns N tools, the swarm channel is functional regardless of whether the
   gateway is currently running.
5. The registration takes effect when the gateway next starts (Scheduled Task
   "OpenClaw Gateway" at logon). No launch required to prove it.

## Port map of the swarm (verified live, 2026-07-11)
- Ollama :11434  [::]  LAN-exposed  -> shared LLM brain (every agent calls this)
- OpenClaw gateway :18789 127.0.0.1 loopback -> agent runtime + MCP host
- ZQM-Node-01-Indexer :5000 127.0.0.1 loopback (Flask+Waitress) + MCP stdio
- Skill-Automation-Center :9000 127.0.0.1 loopback (SAC_PORT env) + shared auth/state
- Native Hermes gateway: NO PORT ENV set -> uses built-in default. COLLISION RISK
  with OpenClaw on :18789. Pin it (PORT env) or disable the OpenClaw task. ASK
  the user which gateway owns :18789; do not guess.

## Open security item (unchanged)
`~/.openclaw/openclaw.json` + `~/.openclaw/devices/paired.json` carry PLAINTEXT
gateway/operator tokens. Loopback-only bind limits exposure to local-file read.
Flag for rotation; never print them into a report.

## The "False Exists(Tgt):True" trap - exact verification idiom
When a Startup `.lnk` points at `pythonw.exe ... SomeScript.py`, a naive
`WScript.Shell` `Test-Path` on `.TargetPath` returns True (pythonw exists) while
the real `.py` is missing. The broken part is `.Arguments`, not `.TargetPath`.
Verify the actual script:
  `Test-Path $lnk.Arguments.Trim('"')`   # .Arguments is the script path
NOT just `Test-Path $lnk.TargetPath`.
After repair, re-dump and assert BOTH resolve.
