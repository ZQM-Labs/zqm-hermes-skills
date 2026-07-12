#!/usr/bin/env python3
"""Combined three-layer probe (process / service / security) for a localhost service.
Copy this into a working dir, set PIDS + PORTS below, run with the explicit interpreter.
Persists to SQLite (audit-schema.sql layout). No secrets stored.

Layers:
 1. PROCESS  -> delegates to references/win-process-probe.ps1 (elevation, parent chain)
 2. SERVICE  -> netstat listener bind + HTTP auth probes (no/bogus/valid key)
 3. SECURITY -> netstat ESTABLISHED egress filter (loopback + LAN stripped) = C2 test

Usage:
  python three-layer-probe.py
"""
import subprocess, json, sqlite3, os, datetime, urllib.request, re

PS1 = r"references/win-process-probe.ps1"   # relative to skill dir or absolute
DB  = "three_layer_audit.db"

# ---- targets ----
PIDS   = [1908, 19120]
PORTS  = {1908: 8400, 19120: 4001}
PROBES_8400 = {  # (method, url, headers)  edit to match the service
    "GET / (open?)":            ("GET",  "http://127.0.0.1:8400/", {}),
    "GET /health (open?)":      ("GET",  "http://127.0.0.1:8400/health", {}),
    "GET /openapi.json (open?)":("GET",  "http://127.0.0.1:8400/openapi.json", {}),
    "GET /v1/models (no key)":  ("GET",  "http://127.0.0.1:8400/v1/models", {}),
    "GET /v1/models (bogus)":   ("GET",  "http://127.0.0.1:8400/v1/models", {"X-Api-Key":"bogus"}),
}
PROBES_4001 = {
    "GET /health/liveliness":   ("GET",  "http://127.0.0.1:4001/health/liveliness", {}),
    "GET /v1/models (open?)":   ("GET",  "http://127.0.0.1:4001/v1/models", {}),
    "POST /v1/chat/completions (no key)": ("POST", "http://127.0.0.1:4001/v1/chat/completions",
                                           {"Content-Type":"application/json"}),
    "POST /key/generate (mgmt)":("POST", "http://127.0.0.1:4001/key/generate",
                                           {"Content-Type":"application/json"}),
}
PROBE_MAP = {8400: PROBES_8400, 4001: PROBES_4001}

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=90).stdout

def http_probe(method, url, headers):
    try:
        data = b'{"model":"zbit-fast","messages":[{"role":"user","content":"hi"}]}' if method=="POST" else None
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        r = urllib.request.urlopen(req, timeout=6)
        return r.status, r.read().decode()[:200]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]
    except Exception as e:
        return "ERR", str(e)[:120]

# Layer 1
ps_out = sh(f'powershell -NoProfile -ExecutionPolicy Bypass -File "{PS1}"')
proc = {}
for line in ps_out.splitlines():
    line = line.strip()
    if line.startswith("{") and "pid" in line:
        try: proc[json.loads(line)["pid"]] = json.loads(line)
        except: pass

# Layer 2 / 3 from netstat
net = sh("netstat -ano")
listeners, established = {}, {}
for ln in net.splitlines():
    m = re.search(r"TCP\s+([\d:\.\[\]]+):(\d+)\s+([\d:\.\[\]]+):(\d+|\*)\s+(\w+)\s+(\d+)", ln)
    if not m: continue
    laddr, lport, raddr, rport, state, pid = m.groups()
    pid = int(pid)
    if state == "LISTENING": listeners.setdefault(pid, []).append(f"{laddr}:{lport}")
    elif state == "ESTABLISHED": established.setdefault(pid, []).append(f"{raddr}:{rport}")

external = {}
for pid, conns in established.items():
    for peer in conns:
        if not re.match(r"^(127\.|::1|0\.0\.0\.0|\[?::\]?|192\.168\.1\.)", peer):
            external.setdefault(pid, []).append(peer)

sp = {}
for pid, probes in PROBE_MAP.items():
    sp[pid] = {ep: http_probe(*cfg) for ep, cfg in probes.items()}

# persist
con = sqlite3.connect(DB); c = con.cursor()
c.executescript(open("references/audit-schema.sql").read() if os.path.exists("references/audit-schema.sql")
                else open(__file__.replace(".py","_schema.sql")).read())
c.execute("INSERT INTO run_meta VALUES (?,?)", ("ts", datetime.datetime.utcnow().isoformat()+"Z"))
for pid, d in proc.items():
    for fld in ["name","cmdline","ppid","parentName","elev","session","user","start"]:
        c.execute("INSERT INTO process_layer VALUES (?,?,?)", (pid, fld, str(d.get(fld))))
for pid, ls in listeners.items():
    for x in ls: c.execute("INSERT INTO net VALUES (?,?,?)", (pid,"LISTEN",x))
for pid, es in established.items():
    for x in es: c.execute("INSERT INTO net VALUES (?,?,?)", (pid,"EST",x))
for pid, probes in sp.items():
    svc = {8400:"zbit8400",4001:"litellm4001"}.get(pid,"svc")
    for ep,(code,body) in probes.items():
        c.execute("INSERT INTO service_probe VALUES (?,?,?,?)", (svc, ep, str(code), body[:120]))
c.execute("INSERT INTO verdict VALUES (?,?,?)", ("security", f"external egress for {list(external) or 'none'}", "PROVEN"))
c.execute("INSERT INTO verdict VALUES (?,?,?)", ("verdict", "C2 node?", "FALSE" if not external else "UNRESOLVED"))
con.commit(); con.close()

print("PROCESS:", {p:{k:proc[p].get(k) for k in ('name','elev','ppid','parentName')} for p in proc})
print("LISTEN:", {p:listeners.get(p) for p in PIDS})
print("EXT_EGRESS(C2 test):", external or "NONE")
for pid in PIDS:
    print(f"PROBES {pid}:", {k:v[0] for k,v in sp[pid].items()})
print("WROTE", DB)
