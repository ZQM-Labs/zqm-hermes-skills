#!/usr/bin/env python3
"""
exposure_scan.py — full TCP exposure scan from the control-plane / scanner host.

WHY THIS EXISTS: when a delegated exposure-map leaf 429's (sub-agent API rate limit)
with no data, the LEAD runs the scan itself here on the scanner box (Node-1 in the ZQM
fleet). It has the real Python + no per-call API budget, so it closes the gap the council
left. 1062 ports x 7 hosts ~= 7434 probes in ~15s with a 200-worker pool.

USAGE:
  python exposure_scan.py                 # uses HOSTS/PORTS below
  python exposure_scan.py --hosts 192.168.1.21 192.168.1.215 --ports 6379 11434

OUTPUT: per-host open port list, printed + optionally written as JSON (--json out.json).
RE-PROBE hot findings (Redis/Ollama/OpenClaw) separately in the same turn per the re-probe rule.

STRONGER-CONFIRM NOTE (critical 2026-07-11 lesson): a connect() success is weak evidence.
If a surprising port appears (or a council leaf denies one), confirm with a STRONGER method
before reporting exposure:
  - banner grab:  s=connect(); s.recv(200)  -> FTP "220 ...", SSH "SSH-2.0-..."
  - telnet IAC:   s.sendall(b"\\xff\\xfb\\x01"); s.recv(100)  -> "\\xff\\xfb..." reply proves a real daemon
  - HTTP:         GET / and read Server/title
Do NOT reflexively trust a council "handshake proved absent" claim — a leaf's handshake can
be a FALSE NEGATIVE (the ZQM Synology units really DO expose :21 FTP, :23 Telnet, :111, :2049).
"""
import socket, concurrent.futures, argparse, json

HOSTS = {
    "Node-1 control-plane": "192.168.1.218",
    "Node-2": "192.168.1.21",
    "Node-3": "192.168.1.46",
    "Node-4 central-farm": "192.168.1.215",
    "Gateway G1": "192.168.1.173",
    "Gateway G2": "192.168.1.40",
    "Synology NAS": "192.168.1.53",
}
HIGH = [1158,1433,1521,1863,2049,3128,3306,3389,3690,4369,5000,5001,5432,5672,
        5900,5985,5986,6379,7000,7070,8000,8080,8443,9000,9090,9200,9300,11211,
        11434,11435,13306,18789,27017,27018,28015,50000,50030,50070]
LOW = list(range(1, 1025))
ALLPORTS = sorted(set(LOW + HIGH))

SVC = {22:"SSH",80:"HTTP",443:"HTTPS",445:"SMB",3389:"RDP",3306:"MySQL",5432:"PostgreSQL",
       6379:"Redis",11211:"Memcached",27017:"MongoDB",1521:"Oracle",1433:"MSSQL",2049:"NFS",
       3128:"Squid",5900:"VNC",5985:"WinRM-HTTP",5986:"WinRM-HTTPS",873:"rsync",5000:"DSM-http",
       5001:"DSM-https",8080:"HTTP-alt",8443:"HTTPS-alt",9000:"portainer",9090:"prometheus",
       9200:"elasticsearch",9300:"es-transport",11434:"Ollama",11435:"Ollama-2",
       18789:"OpenClaw-mesh",23:"Telnet",111:"rpcbind",139:"NetBIOS",161:"SNMP",548:"AFP",892:"nfs-rquotad"}

def scan(ip, p, to=0.35):
    try:
        with socket.create_connection((ip, p), timeout=to):
            return p
    except Exception:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hosts", nargs="*", help="IPs (else all HOSTS)")
    ap.add_argument("--ports", nargs="*", type=int, help="custom port list (else 1-1024 + HIGH)")
    ap.add_argument("--json", help="write results to this JSON path")
    ap.add_argument("--to", type=float, default=0.35, help="connect timeout")
    args = ap.parse_args()

    targets = [("custom", h) for h in args.hosts] if args.hosts else list(HOSTS.items())
    ports = args.ports if args.ports else ALLPORTS

    results = {}
    for name, ip in targets:
        with concurrent.futures.ThreadPoolExecutor(max_workers=200) as ex:
            opens = list(filter(None, ex.map(lambda p: scan(ip, p, args.to), ports)))
        results[name] = {"ip": ip, "open": sorted(opens),
                         "services": {str(p): SVC.get(p, f"srv{p}") for p in sorted(opens)}}
        print(f"{name:22s} {ip:16s} open={len(opens)} -> {sorted(opens)}")
    if args.json:
        with open(args.json, "w") as f:
            json.dump(results, f, indent=2)
        print(f"wrote {args.json}")

if __name__ == "__main__":
    main()
