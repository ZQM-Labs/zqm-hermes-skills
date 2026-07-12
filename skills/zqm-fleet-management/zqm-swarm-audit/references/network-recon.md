# Network Recon — condensed recipe + device tells

## Command sequence (Windows host, git-bash terminal)
```bash
arp -a                      # what's on the wire (recently talked only)
ipconfig                    # interfaces / subnets
for ip in 192.168.1.1 21 46 215; do ping -n 1 -w 800 $ip >/dev/null && echo "$ip UP" || echo "$ip DOWN"; done
nbtstat -A <ip>             # NetBIOS name (Windows hosts only)
curl -sI http://<ip>        # HTTP headers (Server:, 301/404)
curl -skI https://<ip>:8443 # self-signed TLS (git-bash curl fine)
python sa_probe.py          # full threaded discovery + fingerprint
python sa_reconcile.py      # re-scan DB-recorded ports, classify drift
```

## Device fingerprint tells (from 2026-07-12 live scan)
| Device | SSH banner | Web Server | Notes |
|--------|-----------|------------|-------|
| Windows OpenSSH | `SSH-2.0-OpenSSH_for_Windows_*` | n/a | port 22 on nodes |
| ASUS router | `dropbear` | `httpd/3.0` :80/:8443, `lighttpd/1.4.39` 401 :443 | ASUSWRT |
| TerraMaster TOS | `OpenSSH_8.8` | `nginx/1.21.0` title `TOS Loading` | Garden appliance |
| Synology DSM | n/a | nginx, `/webapi/query.cgi` API | hit `SYNO.API.Info` to confirm |
| Google Cast/Nest | n/a | 404 :8443/:8008/:9000 | Google OUI f8:0f:f9 / 20:1f:3b |
| HP printer | n/a | nginx, 301 :80->:443 | HP OUI 7c:4d:8f, often all ports closed |

## OUI quick table (fleet + observed 2026-07-12)
- 4c:ab:f8 -> router/AP (gateway .1)
- 8c:17:59 / f0:d4:15 -> fleet nodes N3/N4
- 6c:bf:b5 -> ZQM-GARDEN-04
- f8:0f:f9 / 20:1f:3b -> Google Inc. (cast/nest x2)
- 7c:4d:8f -> HP Inc. (printer)
- 10:7c:61 -> ASUSTek (router)
- a0:36:bc -> Intel NIC (server box .220)

## Reconciliation classification (vs fleet_endpoint_audit.db)
- MATCH        = DB OPEN  and live OPEN
- DRIFT-OPEN   = DB CLOSED and live OPEN  (new exposure — flag)
- DRIFT-CLOSED = DB OPEN  and live CLOSED (exposure removed)
- UNVERIFIABLE = host DOWN (every port closed because dark) -> claim NOT PROVEN, ledger item stays OPEN

## Pitfalls (full list in SKILL.md)
- arp -a = recently-talked only; ping/TCP sweep to populate for full /24.
- macvendors.com 429 -> space 3-4s or embed OUI table.
- nbtstat -A empty for non-Windows = normal.
- host DOWN != port closed; don't record CRITICAL as FALSE, mark UNVERIFIABLE.
- self-signed TLS needs `ssl.CERT_NONE` or urllib throws.
