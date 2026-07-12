"""
swarm_mcp_probe.py - PROVE a swarm MCP link works WITHOUT depending on the gateway.

Run exactly the stdio spawn the gateway will use, do a JSON-RPC initialize +
tools/list handshake, and print the advertised tools. This is the decisive
"does the swarm actually mesh" test: if a bot's MCP server advertises its
tools here, every gateway agent can call them.

Usage:
  python swarm_mcp_probe.py <python_exe> <mcp_server_script> [cwd]

Exit 0 if the server comes up and advertises >=1 tool; else exit 1.
Read-only / non-destructive: spawns the server, reads its protocol, terminates it.

Example (ZQM-Node-01 indexer -> OpenClaw gateway):
  python swarm_mcp_probe.py \
    "C:\Users\zqmco\AppData\Local\Programs\Python\Python312\python.exe" \
    "C:\Users\zqmco\OneDrive\Desktop\repos\zqm-node-01-indexer\mcp_server.py" \
    "C:\Users\zqmco\OneDrive\Desktop\repos\zqm-node-01-indexer"
"""
import subprocess, json, sys, os


def main():
    if len(sys.argv) < 3:
        print("usage: swarm_mcp_probe.py <python_exe> <mcp_server_script> [cwd]")
        return 2
    py, script = sys.argv[1], sys.argv[2]
    cwd = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(script)

    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    if cwd not in env.get("PYTHONPATH", ""):
        env["PYTHONPATH"] = (cwd + os.pathsep + env.get("PYTHONPATH", "")).rstrip(os.pathsep)

    p = subprocess.Popen([py, script], cwd=cwd,
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, bufsize=1, env=env)

    def send(obj):
        p.stdin.write(json.dumps(obj) + "\n")
        p.stdin.flush()

    def read_msg():
        while True:
            line = p.stdout.readline()
            if not line.strip():
                continue
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "swarm-probe", "version": "0"}}})
        init = read_msg()
        if "result" not in init:
            print("initialize FAILED:", init.get("error"))
            return 1
        print("initialize OK: serverInfo present =",
              bool(init["result"].get("serverInfo")))

        send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools = read_msg()
        names = [t["name"] for t in (tools or {}).get("result", {}).get("tools", [])]
        print("TOOLS ADVERTISED:", names)
        print("TOOL COUNT:", len(names))
        return 0 if names else 1
    except Exception as e:
        print("probe error:", e)
        return 1
    finally:
        p.terminate()


if __name__ == "__main__":
    sys.exit(main())
