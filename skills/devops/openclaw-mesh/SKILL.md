---
name: openclaw-mesh
description: 'Operate the ZQM agent MESH: OpenClaw gateway (Node-1 — :18789 LISTENING on 127.0.0.1 loopback (verified 2026-07-11 v3); collision with native Hermes gateway is LIVE, owner undecided)
  hosting the agent runtime + MCP server, the shared Ollama :11434 LLM brain, the
  ZQM-Node-01 Indexer (:5000 Flask+Waitress + MCP stdio), and the Skill-Automation-Center
  (:9000 shared auth/state). Covers the verified live port map, MCP swarm registration
  into openclaw.json, the plaintext-token hazard, and the NATIVE-HERMES-GATEWAY :18789
  COLLISION that must be resolved by asking the user. Use when troubleshooting the
  mesh, registering a bot, or reasoning about agent topology.'
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - openclaw
    - mesh
    - mcp
    - gateway
    - agent-topology
    - port-map
    related_skills:
    - fleet-council-audit
    - ollama-fleet-lb
    - ollama-recovery
    - zqm-fleet-management
    - zqm-local-setup
    - zqm-systems-review
---
# OpenClaw Agent Mesh — topology & ops

## When to use
- Reasoning about which agent/bot can call which service on the ZQM mesh.
- Registering a bot's MCP server into the OpenClaw gateway.
- The "False Exists(Tgt):True" Startup `.lnk` trap, or any mesh port collision.
- Wiring Hermes ↔ OpenClaw ↔ Cline on Node-1.

## Verified live port map (2026-07-11)
| Service | Port | Bind | Role |
|---|---|---|---|
| Ollama | :11434 | [::] LAN | shared LLM brain — every agent calls this |
| OpenClaw gateway | :18789 | 127.0.0.1 loopback | agent runtime + MCP host — **LISTENING** (verified v3, pid 23208); collision with native Hermes gateway is **LIVE** (owner undecided — ask user) |
| ZQM-Node-01-Indexer | :5000 | 127.0.0.1 loopback | Flask+Waitress search + MCP stdio |
| Skill-Automation-Center | :9000 | 127.0.0.1 loopback | shared auth/state (SAC_PORT) |
| Native Hermes gateway | (default) | — | **COLLISION RISK** w/ OpenClaw on :18789 |

Agent sandbox CAN reach 192.168.1.0/24; Ollama on :11434 is the shared compute.

## MCP swarm registration (verified recipe)
A bot exposing an MCP server is registered into `~/.openclaw/openclaw.json`
(`mcpServers[]`) so every gateway agent can CALL its tools — the swarm coordination
channel, no bespoke IPC.
1. Pre-flight (non-destructive): `python -c "import mcp, mcp_server; print('ok')"`
2. BACK UP `openclaw.json` (may contain PLAINTEXT tokens — never print them).
3. Edit JSON with a Python script (`json.load`/`json.dump`) so existing tokens are
   preserved verbatim. Entry shape OpenClaw accepts: `name`, `command`, `args`, `cwd`,
   `env`. Example (indexer):
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
4. PROVE with `scripts/swarm_mcp_probe.py` (spawns the exact stdio server, does
   initialize + tools/list). If it returns N tools, the swarm channel works regardless
   of whether the gateway is currently running.
5. Registration takes effect when the gateway next starts (Scheduled Task "OpenClaw
   Gateway" at logon). No launch needed to prove it.

## THE :18789 COLLISION (resolve by asking, never guess)
The native Hermes gateway has NO PORT env set → uses its built-in default, which
COLLIDES with OpenClaw on :18789. Pick ONE owner of :18789:
- Pin the Hermes gateway via its `PORT` env, OR
- Disable the OpenClaw Scheduled Task.
ASK the user which gateway owns :18789 before changing anything. Do not auto-decide.

## Plaintext-token hazard (open security item)
`~/.openclaw/openclaw.json` + `~/.openclaw/devices/paired.json` carry PLAINTEXT
gateway/operator tokens. Loopback-only bind limits exposure to local-file read. Flag
for rotation; NEVER print them into a report or chat.

## The "False Exists(Tgt):True" trap (exact idiom)
A Startup `.lnk` pointing at `pythonw.exe ... SomeScript.py`: a naive
`WScript.Shell` `Test-Path` on `.TargetPath` returns True (pythonw exists) while the
real `.py` is missing. The broken part is `.Arguments`, not `.TargetPath`.
```powershell
Test-Path $lnk.Arguments.Trim('"')   # verify the SCRIPT, not the interpreter
```
After repair, re-dump and assert BOTH resolve.

## References
- Proven probe: `software-development/fleet-council-audit/scripts/swarm_mcp_probe.py`
- Shared state backbone: `zqm_auth` (`~/.zqm-auth/token`), `zqm_multi_tenant_db`,
  `zqm_user_resolver` (per-user `~/.zqm-data/<user>/` + state.db WAL)
- ollama-fleet-lb (Ollama is the mesh's shared LLM brain)
