# Known-Good MCP Server Recipes

Exact, verified `hermes mcp add` commands. Each line was run successfully and the
server connected + tools were discovered. Pipe `printf 'y\n'` to accept all tools
when driving the command non-interactively (see SKILL.md — `hermes mcp add` is
interactive in non-TTY and cancels otherwise).

## Secret-free bundle (no API tokens needed)

```bash
# Filesystem — 14 tools; scoping dir is the LAST arg (path with forward slashes OK on Windows)
printf 'y\n' | hermes mcp add filesystem \
  --command npx --args -y @modelcontextprotocol/server-filesystem C:/Users/zqmco

# Time — 2 tools (get_current_time, convert_time)
printf 'y\n' | hermes mcp add time --command uvx --args mcp-server-time

# Fetch — 1 tool (fetch URL + extract content)
printf 'y\n' | hermes mcp add fetch --command uvx --args mcp-server-fetch

# Sequential Thinking — 1 tool (dynamic step-by-step reasoning scratchpad)
# PACKAGE NAME IS HYPHENATED: @modelcontextprotocol/server-sequential-thinking
# The unhyphenated @modelcontextprotocol/server-sequentialthinking 404s on npm.
# INVOCATION CAVEAT: mcp_sequentialthinking_sequentialthinking REQUIRES
# nextThoughtNeeded: boolean (plus thought, thoughtNumber, totalThoughts) or it
# throws MCP -32602 "expected boolean, received undefined".
printf 'y\n' | hermes mcp add sequentialthinking \
  --command npx --args -y @modelcontextprotocol/server-sequential-thinking
```

## Token-backed servers (need a secret first)

Put the token in `~/.hermes/.env` (KEY=value, no quotes), then pass it through:

```bash
# GitHub — needs GITHUB_PERSONAL_ACCESS_TOKEN
printf 'y\n' | hermes mcp add github \
  --command npx --args -y @modelcontextprotocol/server-github \
  --env GITHUB_PERSONAL_ACCESS_TOKEN=$GITHUB_PERSONAL_ACCESS_TOKEN
```

For HTTP-transport servers use `--url` instead of `--command/--args`:

```bash
printf 'y\n' | hermes mcp add company_api \
  --url https://mcp.internal.example.com/mcp
```

## Verify after adding

```bash
hermes mcp list                 # shows servers, tool counts, status
hermes mcp test <name>          # re-connects and lists discovered tools
```

## Load order

MCP tools do NOT appear in the current session. Exit Hermes and relaunch
(`hermes`) for `discover_mcp_tools()` to connect and register `mcp_<server>_<tool>`.
