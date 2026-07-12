#!/usr/bin/env python3
"""Bulk TCP LISTENING listener -> process -> parent map (READ-ONLY, Windows/MSYS).

Why this exists:
- netstat -ano is the AUTHORITATIVE port->PID source. Get-NetTCPConnection JSON
  serializes OwningProcessId as null, so never trust it for listener census.
- We then enrich each PID with Win32_Process (path + parent) via CIM (read-only).

Usage:
  python win_listener_proc_map.py
Emits a table to stdout AND writes listener_detail.txt under %LOCALAPPDATA%.
"""
import subprocess, re, json, os

# 1) Listener census via netstat (port->PID that actually works)
net = subprocess.run(["cmd.exe", "/c", "netstat -ano -p TCP"],
                     capture_output=True, text=True, timeout=60).stdout
pat = re.compile(r"TCP\s+([\d.]+):(\d+)\s+[\d.]+:\d+\s+LISTENING\s+(\d+)")
listeners = [(ip, int(port), int(pid)) for ip, port, pid in pat.findall(net)]

# 2) Process map via CIM (read-only)
ps = subprocess.run(
    ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
     "Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,"
     "Name,ExecutablePath,CommandLine | ConvertTo-Json -Compress"],
    capture_output=True, text=True, timeout=90)
try:
    procs = json.loads(ps.stdout)
    if isinstance(procs, dict):
        procs = [procs]
except Exception:
    procs = []

pmap = {}
for p in procs:
    try:
        pmap[int(p["ProcessId"])] = p
    except Exception:
        pass

def nm(pid):
    p = pmap.get(pid)
    return p["Name"] if p else "?"

tmp = os.path.join(os.environ.get("LOCALAPPDATA", "C:/Users/zqmco/AppData/Local/Temp"),
                   "listener_detail.txt")
print(f"{'IP':15} {'PORT':6} {'PID':6} {'PROC':24} {'PPID':6} PARENT")
rows = []
for ip, port, pid in sorted(listeners, key=lambda x: (x[0], x[1])):
    p = pmap.get(pid, {})
    name = p.get("Name", "?")
    ppid = p.get("ParentProcessId")
    pname = nm(ppid) if ppid is not None else "?"
    print(f"{ip:15} {port:<6} {pid:<6} {name[:24]:24} {str(ppid):6} "
          f"{pname[:18]:18} {p.get('ExecutablePath') or '?'}")
    rows.append((ip, port, pid, name, ppid, pname,
                 p.get("ExecutablePath"), p.get("CommandLine")))

with open(tmp, "w") as f:
    for ip, port, pid, name, ppid, pname, path, cmd in rows:
        f.write(f"{ip}:{port} pid={pid} name={name} ppid={ppid} parent={pname} "
                f"path={path} cmd={cmd}\n")
print(f"\nWROTE {tmp}  ({len(rows)} listeners)")
