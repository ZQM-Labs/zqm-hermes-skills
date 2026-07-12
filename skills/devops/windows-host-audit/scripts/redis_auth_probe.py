#!/usr/bin/env python3
"""Raw Redis AUTH probe (READ-ONLY). Sends a RESP PING; +PONG with no AUTH
negotiation means the instance is UNSECURED / reachable without credentials.

Usage:
  python redis_auth_probe.py 192.168.1.21 6379
  python redis_auth_probe.py 127.0.0.1 6379
Do NOT use httpx/curl for this -- they send HTTP and time out against the RESP
protocol, yielding a false "closed". A raw socket PING is the correct probe.
"""
import socket, sys

host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 6379
try:
    s = socket.create_connection((host, port), timeout=8)
    s.sendall(b"PING\r\n")
    data = s.recv(1024)
    s.close()
    print(f"{host}:{port} RECV: {data!r}")
    if b"+PONG" in data:
        print("RESULT: UNSECURED +PONG (CRITICAL) -- no requirepass / not bound loopback")
    else:
        print("RESULT: got a response but not +PONG (review -- may be AUTH-gated or wrong service)")
except Exception as e:
    print(f"{host}:{port} ERROR: {e!r}")
