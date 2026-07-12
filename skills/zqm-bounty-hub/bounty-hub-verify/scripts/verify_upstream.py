import json, socket, os, urllib.request, urllib.error
from datetime import datetime, timezone

TARGETS = [
    ("localhost", 11434, "Ollama"),
    ("localhost", 8000, "FastAPI"),
    ("localhost", 8188, "ComfyUI"),
    ("192.168.1.218", 5000, "Node-01 Indexer"),
    ("192.168.1.21", 5000, "Node-02 Indexer"),
]

def tcp_open(host, port, timeout=2):
    s = socket.socket()
    s.settimeout(timeout)
    try:
        s.connect((host, port))
        s.close()
        return True
    except Exception:
        return False

def http_get(url, timeout=5):
    try:
        r = urllib.request.urlopen(url, timeout=timeout)
        data = r.read()
        return {"status": r.status, "content_type": r.headers.get("Content-Type", ""), "bytes": len(data)}
    except urllib.error.HTTPError as e:
        return {"status": e.code, "error": str(e)}
    except Exception as e:
        return {"status": None, "error": str(e)}

results = []
for host, port, name in TARGETS:
    port_open = tcp_open(host, port)
    detail = None
    if port_open:
        if port == 11434:
            detail = http_get(f"http://{host}:{port}/api/tags")
        elif port == 8000:
            detail = http_get(f"http://{host}:{port}/health")
        elif port == 8188:
            detail = http_get(f"http://{host}:{port}/")
        elif port == 5000:
            detail = {}
            for p in ["/api/health", "/health", "/api/status", "/"]:
                r = http_get(f"http://{host}:{port}{p}")
                detail[p] = r
                if r.get("status") in (200, 301, 302):
                    break
    results.append({"name": name, "host": host, "port": port, "tcp_open": port_open, "http": detail})

config_paths = [
    (r"C:\Users\zqmco\.zqm-node-01-indexer\config.json", "Node-01 Config"),
    (r"C:\Users\zqmco\.zqm-node-02-indexer\config.json", "Node-02 Config"),
]
fs_checks = [{"path": p, "label": label, "exists": os.path.exists(p)} for p, label in config_paths]

report = {"timestamp_utc": datetime.now(timezone.utc).isoformat(), "targets": results, "filesystem": fs_checks}
print(json.dumps(report, indent=2))
