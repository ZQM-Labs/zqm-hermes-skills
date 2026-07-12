#!/usr/bin/env python3
"""Timeout-based LAN port probe for ZQM nodes/Gardens.

Why: bash `/dev/tcp` HANGS on unresponsive hosts (cost a 180s timeout in one session).
This uses socket timeouts so dead hosts return instantly.

Usage:  python probe_lan.py
"""
import socket

TARGETS = {
    "Node-1": "192.168.1.218",
    "Node-2": "192.168.1.21",
    "Node-3": "192.168.1.46",
    "Node-4": "192.168.1.215",
    "Garden-01": "192.168.1.173",
    "Garden-02": "192.168.1.40",
    "Garden-03": "192.168.1.64",
    "Garden-04a": "192.168.1.144",
    "Garden-04b": "192.168.1.147",
}
PORTS = [22, 80, 139, 443, 445, 5000, 5001, 5985, 8080]


def is_open(ip, port, timeout=0.6):
    s = socket.socket()
    s.settimeout(timeout)
    try:
        s.connect((ip, port))
        return True
    except Exception:
        return False
    finally:
        s.close()


def main():
    for name, ip in TARGETS.items():
        states = {p: ("OPEN" if is_open(ip, p) else "closed") for p in PORTS}
        line = "  ".join(f"{p}={states[p]}" for p in PORTS)
        print(f"{name:10} {ip:15} {line}")


if __name__ == "__main__":
    main()
