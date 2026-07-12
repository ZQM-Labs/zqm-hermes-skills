#!/usr/bin/env python
# zqm-cred-sweep.py - enumerate which (user,password) opens a Windows node.
# TCP port probe + paramiko SSH auth sweep. Run with the ComfyUI venv python:
#   C:\Users\zqmco\Documents\comfy\ComfyUI\.venv\Scripts\python.exe scripts\zqm-cred-sweep.py <host> -c user:pass [-c user:pass ...]
# No secrets are hardcoded; pass candidates on the command line. Reports OPEN / REJECT / ERR per pair.
import sys, socket, argparse, paramiko

def port_open(ip, port, t=1.2):
    s = socket.socket(); s.settimeout(t)
    try:
        s.connect((ip, port)); return True
    except Exception:
        return False
    finally:
        s.close()

def ssh_try(ip, user, pw, t=9):
    try:
        c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(ip, 22, user, pw, timeout=t, look_for_keys=False, allow_agent=False)
        c.exec_command('hostname', timeout=10); c.close(); return 'OPEN'
    except paramiko.AuthenticationException:
        return 'REJECT'
    except Exception as e:
        return 'ERR:' + type(e).__name__

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('host')
    ap.add_argument('-c', action='append', default=[], help='candidate user:pass (repeatable)')
    ap.add_argument('-p', type=int, default=22, help='SSH port (default 22)')
    args = ap.parse_args()
    if not args.c:
        print("usage: zqm-cred-sweep.py <host> -c user:pass [-c user:pass ...]")
        sys.exit(2)
    print(f"host={args.host} ssh{args.p}={'OPEN' if port_open(args.host, args.p) else 'CLOSED'}")
    for pair in args.c:
        if ':' not in pair:
            print(f"  skip (no ':'): {pair}"); continue
        u, p = pair.split(':', 1)
        print(f"  {u}: {ssh_try(args.host, u, p, args.p)}")

if __name__ == '__main__':
    main()
