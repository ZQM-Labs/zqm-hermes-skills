"""Ad-hoc self-verify of an MCP server the way the gateway spawns it.

Proves the swarm TOOL channel works end-to-end: spawn the EXACT stdio
server the gateway config points at (command/args/cwd/env), then drive a
JSON-RPC session: initialize -> tools/list -> tools/call.

WHY this (not just `tools/list`): an MCP server can import + list
tools fine but throw on `tools/call` (e.g. the mcp SDK >=1.x
`call_tool(tool_name, arguments)` signature change, or a locked index
the call would touch). Listing alone hides that. A real `tools/call`
against a read-only tool is the decisive "does the swarm actually mesh" test.

Set the 4 constants below to the bot you are verifying. The MCP entry
in the gateway config (openclaw.json `mcpServers[].command/args/cwd/env`)
must match these exactly.

Run:
  powershell -NoProfile -ExecutionPolicy Bypass -Command \
    "& 'C:\Users\zqmco\AppData\Local\Programs\Python\Python312\python.exe' '<this file>'"
"""
import subprocess, json, os, sys

# --- bot-under-test constants (edit per bot) ---
PYTHON = r"C:\Users\zqmco\AppData\Local\Programs\Python\Python312\python.exe"
MCP_SCRIPT = r"C:\Users\zqmco\OneDrive\Desktop\repos\zqm-node-01-indexer\mcp_server.py"
CWD = r"C:\Users\zqmco\OneDrive\Desktop\repos\zqm-node-01-indexer"
ENV_EXTRA = {"PYTHONIOENCODING": "utf-8"}  # add ZQM_INDEX_DIR etc. if the bot needs it

# A SAFE tool to call (read-only; does not need a populated/built index).
# Prefer get_index_stats / list_filters over search_files (which needs docs).
PROBE_TOOL = "get_index_stats"
PROBE_ARGS = {}


def main():
    env = {**os.environ, **ENV_EXTRA}
    p = subprocess.Popen(
        [PYTHON, MCP_SCRIPT], cwd=CWD,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, bufsize=1, env=env,
    )

    def send(o):
        p.stdin.write(json.dumps(o) + "\n")
        p.stdin.flush()

    def read():
        while True:
            line = p.stdout.readline()
            if not line.strip():
                continue
            m = json.loads(line)
            if m.get("id") in (1, 2, 3):
                return m

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                         "clientInfo": {"name": "selfverify", "version": "0"}}})
        init = read()
        ok_init = bool(init and init.get("result"))
        print("initialize ok:", ok_init)

        send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tl = read()
        tools = (tl or {}).get("result", {}).get("tools", [])
        names = [t["name"] for t in tools]
        print("tools advertised:", names)

        send({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
              "params": {"name": PROBE_TOOL, "arguments": PROBE_ARGS}})
        tc = read()
        if tc.get("result"):
            content = tc["result"].get("content", [{}])
            print(f"tools/call '{PROBE_TOOL}' ->",
                  (content[0].get("text", "")[:300] if content else "OK (no text)"))
        else:
            print(f"tools/call '{PROBE_TOOL}' ERROR:", tc.get("error"))

        assert ok_init, "FAIL: MCP initialize failed"
        assert "search_files" in names, "FAIL: expected search_files in tools"
        assert tc.get("result"), f"FAIL: tools/call raised {tc.get('error')}"
        print("\nSELF-VERIFY PASSED: gateway can spawn + call this bot's MCP tools")
    finally:
        p.terminate()


if __name__ == "__main__":
    main()
