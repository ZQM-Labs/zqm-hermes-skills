#!/usr/bin/env python3
"""ZQM live LAN discovery probe (read-only). Threaded TCP connect-scan per host
+ HTTP/HTTPS fingerprint (CERT_NONE) + SSH banner + NetBIOS (nbtstat) + OUI.
Adjust SUBNET_HOSTS / PORTS / ARP / OUI to the current fleet map, then run:
    python sa_probe.py
Outputs a JSON snapshot to C:/Users/zqmco/sa_snapshot_<ts>.json and prints a report.
"""
import socket, json, threading, urllib.request, ssl, re, time, datetime, os

SUBNET_HOSTS = ["192.168.1.1","192.168.1.21","192.168.1.46","192.168.1.82",
                "192.168.1.91","192.168.1.144","192.168.1.170","192.168.1.172",
                "192.168.1.215","192.168.1.218","192.168.1.220"]
PORTS = [20,21,22,23,25,53,69,80,81,88,110,111,123,135,137,139,143,161,162,389,
         443,445,465,514,587,631,636,993,995,1024,1080,1433,1521,1723,2049,3000,
         3128,3260,3306,3389,3690,4369,5000,5001,5432,5601,5672,5900,5984,5985,
         5986,6379,6443,7000,7070,8000,8008,8009,8080,8081,8443,8888,9000,9042,
         9090,9100,9200,9300,10000,11211,15672,27017,32400,50000,50001,50013]
WEB_PORTS = {80,81,443,631,8000,8008,8009,8080,8081,8443,8888,9000,10000,50000,50001}
ARP = {"192.168.1.1":"4c:ab:f8:04:e1:e1","192.168.1.46":"8c:17:59:79:bc:dd",
       "192.168.1.82":"f8:0f:f9:56:9b:03","192.168.1.91":"7c:4d:8f:4d:f2:92",
       "192.168.1.144":"6c:bf:b5:02:83:2c","192.168.1.170":"10:7c:61:83:50:70",
       "192.168.1.172":"20:1f:3b:ac:f3:71","192.168.1.215":"f0:d4:15:e4:30:4a",
       "192.168.1.218":"00:00:00:00:00:00","192.168.1.220":"a0:36:bc:43:ba:40"}
OUI = {"4c:ab:f8":"(router/AP)","8c:17:59":"(fleet N3)","f8:0f:f9":"Google Inc.",
       "7c:4d:8f":"HP Inc.","6c:bf:b5":"(Garden)","10:7c:61":"ASUSTek COMPUTER INC.",
       "20:1f:3b":"Google Inc.","f0:d4:15":"(fleet N4)","a0:36:bc":"Intel Corporate"}
KNOWN = {"192.168.1.218":"Node-1 (self)","192.168.1.21":"Node-2",
         "192.168.1.46":"Node-3","192.168.1.215":"Node-4",
         "192.168.1.1":"gateway/router","192.168.1.144":"ZQM-GARDEN-04"}

def oui_vendor(mac):
    if not mac or mac=="00:00:00:00:00:00": return "(self)"
    pre=":".join(mac.split(":")[:3]).lower()
    if pre in OUI: return OUI[pre]
    try:
        v=urllib.request.urlopen(f"https://api.macvendors.com/{mac}",timeout=8).read().decode().strip()
        if "errors" not in v and v: return v
    except Exception: pass
    return "(unknown OUI)"

def nbname(ip):
    try:
        out=os.popen(f'nbtstat -A {ip} 2>nul').read()
        m=re.search(r"(\S+)\s+<00>\s+UNIQUE",out)
        if m: return m.group(1)
    except: pass
    return ""

def scan_ports(ip):
    openp=[]
    def t(p):
        s=socket.socket(socket.AF_INET,socket.SOCK_STREAM); s.settimeout(0.35)
        try:
            if s.connect_ex((ip,p))==0: openp.append(p)
        except: pass
        finally: s.close()
    ts=[threading.Thread(target=t,args=(p,)) for p in PORTS]
    for x in ts: x.start()
    for x in ts: x.join()
    return sorted(openp)

def http_fp(ip,port):
    https = port in (443,8443,5001,5986,6443)
    scheme="https" if https else "http"
    try:
        ctx=ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
        req=urllib.request.Request(f"{scheme}://{ip}:{port}/",headers={"User-Agent":"Mozilla/5.0"})
        r=urllib.request.urlopen(req,timeout=5,context=ctx if https else None)
        data=r.read(4000).decode("utf-8","ignore")
        m=re.search(r"<title>(.*?)</title>",data,re.I|re.S)
        return {"code":r.status,"server":r.headers.get("Server","?"),
                "title":(m.group(1).strip()[:80] if m else ""),
                "location":r.headers.get("Location","")}
    except urllib.error.HTTPError as e:
        return {"code":e.code,"server":e.headers.get("Server","?"),"title":"","location":e.headers.get("Location","")}
    except Exception as e:
        return {"error":str(e)[:60]}

def ssh_banner(ip):
    try:
        s=socket.socket(); s.settimeout(3); s.connect((ip,22)); s.settimeout(2)
        b=s.recv(200).decode("utf-8","ignore").strip(); s.close(); return b
    except Exception: return ""

def probe(ip):
    rec={"ip":ip,"known_as":KNOWN.get(ip,""),"mac":ARP.get(ip,""),
         "vendor":oui_vendor(ARP.get(ip,"")),"live": ip in ARP}
    if ip not in ARP:
        rec["note"]="not in ARP / unreachable"; return rec
    rec["open_ports"]=scan_ports(ip)
    web={}
    for p in rec["open_ports"]:
        if p in WEB_PORTS: web[str(p)]=http_fp(ip,p)
    if web: rec["http"]=web
    if 22 in rec["open_ports"]: rec["ssh_banner"]=ssh_banner(ip)
    nb=nbname(ip)
    if nb: rec["netbios"]=nb
    return rec

results=[probe(ip) for ip in SUBNET_HOSTS]
ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
out=f"C:/Users/zqmco/sa_snapshot_{ts}.json"
open(out,"w").write(json.dumps(results,indent=2))
for r in results:
    line=f"\n{r['ip']}"
    if r['known_as']: line+=f"  [{r['known_as']}]"
    if r.get('netbios'): line+=f"  NB={r['netbios']}"
    line+=f"\n  MAC {r['mac']}  Vendor: {r['vendor']}"
    if not r['live']:
        line+="\n  STATE: DOWN"; print(line); continue
    line+=f"\n  Open: {r.get('open_ports')}"
    if 'ssh_banner' in r: line+=f"\n  SSH : {r['ssh_banner']}"
    for p,fp in r.get('http',{}).items():
        line+=f"\n  :{p} -> {fp.get('code')} {fp.get('server')} title='{fp.get('title')}'"
    print(line)
print(f"\nSnapshot saved: {out}")
