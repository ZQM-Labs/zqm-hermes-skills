---
name: hermes-mcp-management
description: "Add, configure, and verify Model Context Protocol (MCP) servers in Hermes Agent via the CLI. Covers the non-obvious gotchas: `hermes mcp add` is interactive in non-TTY (pipe 'y' to accept all tools), the agent cannot edit ~/.hermes/config.yaml directly (use the CLI), the official sequential-thinking package name, and the mandatory restart to load tools. Use whenever the user says 'add MCP', 'add more mcps', 'wire up an MCP server', or wants MCP tools available to Hermes."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
---

# Hermes MCP Management

Hermes has a native MCP client: configured servers connect at startup, their
tools auto-register as `mcp_<server>_<tool>`, and inject into every platform
toolset. This skill is about the *operational* workflow of adding/configuring
them — the parts that bite when you do it from inside the agent. For the full
config schema and transport options, the bundled `hermes-agent` skill has
`references/native-mcp.md` (load it with skill_view if you need timeouts,
sampling, or env filtering detail).

## CRITICAL GOTCHAS (read before acting)

### 1. The agent CANNOT edit config.yaml directly
`patch` / `write_file` on `~/.hermes/config.yaml` are refused with:
`Refusing to write to Hermes config file: ... Agent cannot modify
security-sensitive configuration. Edit ~/.hermes/config.yaml directly or use
'hermes config' instead.`
→ Always use `hermes mcp add` / `hermes config`. Do NOT try to append an
`mcp_servers:` block to the file by hand from the agent.

### 2. `hermes mcp add` is interactive in non-TTY — it cancels and saves nothing
When run without a terminal, `add` prints `Enable all N tools? [Y/n/select]:`
and, receiving EOF, prints `Cancelled.` and writes nothing. The server only
saved once a `y` was piped in.
→ Pipe the answer: `printf 'y\n' | hermes mcp add <name> ...`
(`y` accepts all tools. The `select` sub-prompt is not reachable this way —
fine for all-tools.)

### 3. Tools need a restart to load
`discover_mcp_tools()` runs at agent startup. Adding a server does NOT make its
tools usable in the current session. Tell the user to exit Hermes and relaunch
(`hermes`). Verify presence only after the restart, or use `hermes mcp test`.

### 4. Package-name quirks
The official Sequential Thinking server is **hyphenated**:
`@modelcontextprotocol/server-sequential-thinking`. The unhyphenated
`@modelcontextprotocol/server-sequentialthinking` 404s on npm. When a server
fails to connect with "Connection closed" / 404, treat the package name as a
prime suspect and check `npm view <name> version` before retrying.

### 4b. Tool-NAME mapping pitfall (filesystem especially)
The MCP tool names registered are derived from the SERVER NAME you pass to
`hermes mcp add`, NOT the npm package. So `hermes mcp add filesystem ...` yields
`mcp_filesystem_list_directory` etc. (14 tools), NOT `mcp_fs_*`. The filesystem
server's published npm name is `@modelcontextprotocol/server-filesystem` but you
invoke the tools as `mcp_filesystem_<tool>`. Concretely, the secret-free bundle
gives these tool prefixes: `mcp_filesystem_*` (14: list_allowed_directories,
read_file, write_file, edit_file, list_directory, search_files, create_directory,
move_file, get_file_info, read_media_file, read_multiple_files, read_text_file,
search_files, list_directory_with_sizes), `mcp_time_*` (2), `mcp_fetch_*` (1,
just `mcp_fetch_fetch`), `mcp_sequentialthinking_*` (1). When you go to CALL a tool,
use the prefix you chose at `add` time — guessing `mcp_fs_*` or `mcp_file_*`
returns "tool not found" even though the server is healthy.

### 4c. Filesystem server needs a PATH arg or the add fails/empty
`hermes mcp add filesystem --command npx --args -y @modelcontextprotocol/server-filesystem`
with NO trailing path produces a server that connects but exposes nothing useful
(no allowed-directory root). Always pass the scoped path as the LAST arg:
`... @modelcontextprotocol/server-filesystem C:/Users/zqmco` (forward slashes OK on
Windows; `C:\Users\zqmco` also works). Scope to the smallest tree the agent needs
(this host: `C:/Users/zqmco`). Verify with `mcp_filesystem_list_allowed_directories`
after restart — it must return your scoped path, not be empty.

## Local stdio servers (custom python / node / ts scripts)

Any stdio MCP server launched from a LOCAL script works with `--command <interp> --args <script>`.
This is how you wire your own ZQM repos (zqm-local-tools, ollama-bridge, zqm-node-01-indexer)
as MCP servers — verified working 2026-07-12:

```bash
# Python MCP server (points at the .py entry, NOT a module name)
printf 'y\n' | hermes mcp add zqm-local \
  --command python --args "C:/Users/zqmco/Documents/repo_staging/zqm-local-tools/mcp_server.py"

# Python MCP server that needs a venv interpreter (same shape; just use that python path)
printf 'y\n' | hermes mcp add zqm-indexer \
  --command python --args "C:/Users/zqmco/Documents/repo_staging/zqm-node-01-indexer/mcp_server.py"

# Compiled Node/TypeScript MCP server — point at the BUILD OUTPUT, not the .ts source
# Build first: cd <repo> && npm install && npm run build   (emits build/index.js)
printf 'y\n' | hermes mcp add ollama-bridge \
  --command node --args "C:/Users/zqmco/Documents/repo_staging/ollama-bridge/build/index.js"
```

NOTES (learned 2026-07-12):
- `--args` takes the SCRIPT PATH as a single quoted arg. `node`/`python` launches the
  script directly — there is no `npx`/package-name resolution, so the path must exist on disk.
- For Node/TS: ALWAYS register the COMPILED output (`build/index.js` / `dist/index.js`), never
  the `.ts` source — `node` cannot run TypeScript. Verify `build/<file>.js` exists before
  registering (`npm run build` runs `tsc`; confirm exit 0 + the .js is present).
- `npm install` for a self-contained local repo is usually clean (0 vulnerabilities) and needs
  no network at runtime afterward. `pip install` of the python server's deps is likewise local.
- `hermes mcp list` truncates the command/args column — confirm the full registration landed by
  grepping `~/.hermes/config.yaml` (or AppData/Local/hermes/config.yaml on Windows) for the name.
- Same timing caveat as npx/uvx servers: tools load only after a Hermes RESTART.

## Workflow

1. Check current state first — don't assume empty, but know the baseline:
   `hermes mcp list`  (prints "No MCP servers configured." when none)
2. **Decide server set from available secrets FIRST.** Before adding anything, check
   `~/.hermes/.env` for tokens. If NONE exist (common on a fresh/credential-free host),
   lead with the **secret-free bundle** (filesystem, time, fetch, sequentialthinking) —
   all run off npx/uvx with zero credentials, so you get real tool coverage without
   blocking on a token the user hasn't supplied. Only THEN consider token-backed servers
   (GitHub, etc.) once the user provides a secret. Live case 2026-07-11: host had no
   tokens; the secret-free bundle was installed (4 servers / 20 tools) and exercised live
   without ever needing a credential. Don't stall the whole MCP setup waiting on a token
   that may not exist.
3. Confirm prerequisites exist: `node`/`npx` (npx-based servers), `uvx`
   (uvx-based servers), and the `mcp` Python package for HTTP transport.
4. Add each server with a piped `y` (recipe block in references/known-good-servers.md).
5. Verify: `hermes mcp list` (status ✓ enabled) and `hermes mcp test <name>`
   (lists discovered tools).
6. Tell the user to restart Hermes to load the tools.

## Token-backed servers

MCP servers that need a secret must get it via `--env KEY=VALUE`, and the secret
should live in `~/.hermes/.env` (KEY=value, no quotes) — NOT pasted into chat.
The native client also filters the subprocess environment to a safe baseline and
only passes what you declare in `env`, so the token will NOT leak to other
servers. See references/known-good-servers.md for the GitHub example.

## Verify, don't assume

After `add`, run `hermes mcp test <name>` and confirm a tool count > 0. A
successful `✓ Connected! Found N tool(s)` during `add` is a good sign, but `test`
re-runs the connection independently. If `add` reports "Failed to connect:
Connection closed", the server binary likely 404'd (package-name issue) or isn't
installed — diagnose before saving.

### 5. Verify by INVOKING, not just `mcp test`
`hermes mcp test` only confirms connection + tool *discovery*. The user's standing
rule is "verify every claim with live output." After a session reload makes the
tools live, actually CALL at least one tool per server to prove end-to-end wiring:
- `mcp_time_get_current_time` (any TZ) — proves the clock/data path works.
- `mcp_fetch_fetch --url https://example.com` — proves outbound network works.
- `mcp_filesystem_list_allowed_directories` — proves the scoped path is correct.
- `mcp_sequentialthinking_sequentialthinking` — see caveat below; needs the full
  required schema or it errors.
Treat `test` as a smoke check; a real tool call is the proof.
**TIMING CAVEAT (debugged 2026-07-11):** the tools are NOT callable in the SAME
turn you add the server — `discover_mcp_tools()` runs at agent startup, so a restart
(`hermes`, relaunch) is mandatory before `mcp_*` tools appear or are invocable.
Plan the flow: add+test → tell user to restart → THEN (next turn) invoke to prove.
Attempting to call `mcp_*` in the add turn fails with "tool not found" — that is NOT
a broken server, just pre-restart timing.

### 6. `sequentialthinking` requires `nextThoughtNeeded: boolean`
Calling `mcp_sequentialthinking_sequentialthinking` WITHOUT `nextThoughtNeeded`
blows up with: `MCP error -32602: Input validation error ... expected boolean,
received undefined` (path: nextThoughtNeeded). The tool also needs `thought`,
`thoughtNumber`, `totalThoughts`. Always send the full schema:
thought, thoughtNumber, totalThoughts, nextThoughtNeeded (bool), plus optional
isRevision/revisesThought/branchFromThought/branchId/needsMoreThoughts.

## Overlap note
The bundled/protected `hermes-agent` skill owns the MCP *concept and config
schema* (native-mcp.md). This skill owns the *agent-side CLI workflow and
gotchas*. They are complementary; the curator may cross-link later.
