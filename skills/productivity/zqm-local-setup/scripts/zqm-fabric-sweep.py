#!/usr/bin/env python
# zqm-fabric-sweep.py - discover live hosts on 192.168.1.0/24.
# Use before concluding a node "doesn't exist" or to find an unidentified Windows node
# (e.g. a not-yet-built Node-5). Pure ICMP ping sweep, no creds. Run:
#   C:\Users\zqmco\Documents\comfy\ComfyUI\.venv\Scripts\python.exe scripts\zqm-fabric-sweep.py
import subprocess, concurrent.futures

def ping(ip):
    try:
        r = subprocess.run(['ping', '-n', '1', '-w', '500', ip],
                           capture_output=True, text=True, timeout=4)
        return ip if 'Reply from' in r.stdout else None
    except Exception:
        return None

def main():
    base = '192.168.1.'
    print(f"=== Subnet sweep {base}1-254 (live hosts) ===")
    ips = [base + str(i) for i in range(1, 255)]
    live = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=80) as ex:
        for ip in ex.map(ping, ips):
            if ip:
                live.append(ip)
                print(f"  {ip}")
    print(f"=== {len(live)} live hosts ===")

if __name__ == '__main__':
    main()
