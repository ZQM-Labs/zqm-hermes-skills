#!/usr/bin/env python3
# fleet_endpoint_probe.py <target_ip> [timeout_ms]
# FAST bounded TCP port probe for a single fleet node — used by "full endpoint review"
# leaves (one per node) and the LEAD's own Node-1 deep review.
#
# WHY THIS EXISTS (HIT 2026-07-11): a fleet sweep written as bash
#   for p in ...; do (echo > /dev/tcp/$ip/$p); done
# has NO connect timeout; against a filtered port it blocks until the kernel TCP
# timeout and stalls the whole loop (first fleet sweep TIMED OUT at 180s on Node-4).
# This uses a Python socket with an explicit 0.4s timeout -> a 30-port x 4-host
# sweep finishes in <30s. curl works for HTTP ports but NOT raw services
# (Redis/Telnet/SMB); use this for the full matrix.
import socket, sys, json, time

TARGET = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.218"
TO = float(sys.argv[2]) / 1000 if len(sys.argv) > 2 else 0.4

# Curated ZQM service map: port -> (service, default_exposure_risk)
PORTS = {
    21:("FTP",None), 22:("SSH","MED"), 23:("Telnet","CRIT"), 53:("DNS",None),
    111:("rpcbind","LOW"), 135:("RPC-EPMAP","LOW"), 139:("NetBIOS","LOW"),
    443:("HTTPS","INFO"), 445:("SMB","MED"), 548:("AFP","LOW"),
    662:("BNC?",None), 873:("rsync","LOW"), 892:("NFS-rquotad","LOW"),
    161:("SNMP","LOW"), 2049:("NFS","MED"),
    2179:("VM-RDP","LOW"), 3306:("MySQL","CRIT"), 3389:("RDP","CRIT"),
    5000:("HTTP-alt","INFO"), 5001:("DSM-HTTP","INFO"), 5432:("PostgreSQL","CRIT"),
    5900:("VNC","CRIT"), 5985:("WinRM-HTTP","MED"), 5986:("WinRM-HTTPS","LOW"),
    7000:("HTTP-alt","INFO"), 8000:("HTTP-alt","INFO"),
    8080:("HTTP-alt","INFO"), 8443:("HTTPS-alt","INFO"), 9000:("HTTP-alt","INFO"),
    9090:("Prometheus","INFO"), 9200:("Elastic","CRIT"),
    11211:("Memcached","CRIT"), 11434:("Ollama","HIGH"),
    11435:("Ollama-alt","HIGH"), 18789:("OpenClaw-MESH","LOW"),
    27017:("MongoDB","CRIT"), 50000:("?","?"),
}
for p in [80, 500, 6379, 8080, 8443, 9000]:
    PORTS.setdefault(p, ("unknown", None))

res = {}
for p in sorted(PORTS):
    svc, risk = PORTS[p]
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(TO)
    t0 = time.time()
    try:
        s.connect((TARGET, p))
        res[p] = {"svc": svc, "state": "OPEN", "risk": risk, "ms": round((time.time()-t0)*1000)}
    except socket.timeout:
        res[p] = {"svc": svc, "state": "FILTERED/timeout", "risk": risk, "ms": None}
    except (ConnectionRefusedError, OSError):
        res[p] = {"svc": svc, "state": "CLOSED", "risk": risk, "ms": None}
    finally:
        s.close()

open_ports = {p: res[p] for p in res if res[p]["state"] == "OPEN"}
print(json.dumps({
    "target": TARGET,
    "open": open_ports,
    "closed_count": sum(1 for p in res if res[p]["state"] == "CLOSED"),
    "filtered_count": sum(1 for p in res if res[p]["state"].startswith("FILTER")),
}, indent=2))
crit = [p for p in open_ports if open_ports[p]["risk"] == "CRIT"]
high = [p for p in open_ports if open_ports[p]["risk"] == "HIGH"]
print(f"# RISK TALLY open={len(open_ports)} CRIT={crit} HIGH={high}", file=sys.stderr)
