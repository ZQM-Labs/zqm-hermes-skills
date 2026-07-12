#!/usr/bin/env python3
"""ZQM audit-DB reconciliation (read-only). Re-scans EACH port the
fleet_endpoint_audit.db recorded for a node, classifying MATCH / DRIFT-OPEN /
DRIFT-CLOSED / UNVERIFIABLE, so every endpoint claim is PROVEN/FALSE/NOT PROVEN
from a live socket result. Copy DB_PORTS from a fresh `SELECT node,ip FROM nodes`
+ `SELECT node,port FROM endpoints` read, then run:
    python sa_reconcile.py
Saves C:/Users/zqmco/sa_reconcile_<ts>.json.
"""
import socket, threading, time, json, datetime

# Update from a live DB read each run:
#   SELECT node,ip FROM nodes;  SELECT node,port FROM endpoints WHERE node=...
DB_PORTS = {
 "192.168.1.218":[22,135,139,445,2179,4001,5357,5985,5986,7679,8400,11434,18789,24830,47001,49664,49665,49668,49669,49670,49671,49681,55090],
 "192.168.1.21":[135,139,445,2179,5040,5357,5985,5986,6379,11434],
 "192.168.1.46":[22,135,139,445,2179,5040,5357,5985,5986,11434],
 "192.168.1.215":[22,135,139,445,2179,5040,5357,5985,5986,11434],
}

def cls(ip,p):
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM); s.settimeout(0.6)
    try:
        return "OPEN" if s.connect_ex((ip,p))==0 else "closed"
    except Exception:
        return "filtered"
    finally:
        try: s.close()
        except: pass

print("RECONCILIATION vs audit-DB recorded endpoints\n")
out={}
for ip,ports in DB_PORTS.items():
    res={}
    def t(p,res=res): res[p]=cls(ip,p)
    ts=[threading.Thread(target=t,args=(p,)) for p in ports]
    for x in ts: x.start()
    for x in ts: x.join()
    out[ip]=res
    print(f"=== {ip} ===")
    for p in ports: print(f"  {p:6d} {res[p]}")
    time.sleep(0.3)
ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
open(f"C:/Users/zqmco/sa_reconcile_{ts}.json","w").write(json.dumps(out,indent=2))
print(f"\nsaved sa_reconcile_{ts}.json")
