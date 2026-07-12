#!/usr/bin/env python3
# ollama_auth_proxy.py -- stdlib-only token-gated reverse proxy for Ollama.
#
# Closes the "Ollama :11434 no-auth (LAN)" exposure WITHOUT Ollama's native auth:
#   1. rebind Ollama to 127.0.0.1:11434 (local callers stay no-token, unaffected)
#   2. run THIS proxy on the LAN IP :11434 requiring `Bearer <token>` (401 without)
# See references/ollama-lan-auth.md for the full recipe + reversible teardown.
#
# Env:
#   OLLAMA_PROXY_TOKEN        (secret) OR
#   OLLAMA_PROXY_TOKEN_FILE   path to a file holding the token (preferred)
#   OLLAMA_PROXY_UPSTREAM     default http://127.0.0.1:11434
#   OLLAMA_PROXY_BIND         MUST be the LAN IP (e.g. 192.168.1.218) -- NOT 0.0.0.0,
#                             or it also binds loopback and breaks local no-token access.
#   OLLAMA_PROXY_PORT         default 11434
import http.server, socketserver, urllib.request, os, sys

TOKEN = os.environ.get("OLLAMA_PROXY_TOKEN") or ""
TOKEN_FILE = os.environ.get("OLLAMA_PROXY_TOKEN_FILE")
if not TOKEN and TOKEN_FILE and os.path.exists(TOKEN_FILE):
    TOKEN = open(TOKEN_FILE, "r").read().strip()

UPSTREAM = os.environ.get("OLLAMA_PROXY_UPSTREAM", "http://127.0.0.1:11434")
BIND = os.environ.get("OLLAMA_PROXY_BIND", "192.168.1.218")  # LAN IP, never 0.0.0.0
PORT = int(os.environ.get("OLLAMA_PROXY_PORT", "11434"))

if not TOKEN:
    sys.stderr.write("FATAL: no token set (OLLAMA_PROXY_TOKEN or OLLAMA_PROXY_TOKEN_FILE)\n")
    sys.exit(2)

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def _deny(self):
        body = b'{"error":"unauthorized: missing/invalid Bearer token"}'
        self.send_response(401); self.send_header("Content-Type", "application/json")
        self.send_header("WWW-Authenticate", 'Bearer realm="ollama"')
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def _forward(self):
        if self.headers.get("Authorization", "") != "Bearer " + TOKEN:
            self._deny(); return
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(UPSTREAM + self.path, data=body, method=self.command)
        if self.headers.get("Content-Type"):
            req.add_header("Content-Type", self.headers["Content-Type"])
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                self.send_response(r.status)
                for h in ("Content-Type", "Transfer-Encoding"):
                    if r.headers.get(h):
                        self.send_header(h, r.headers[h])
                cl = r.headers.get("Content-Length")
                if cl:
                    self.send_header("Content-Length", cl)
                self.end_headers()
                while True:
                    buf = r.read(65536)
                    if not buf:
                        break
                    self.wfile.write(buf)
        except urllib.error.HTTPError as e:
            payload = e.read()
            self.send_response(e.code); self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload))); self.end_headers(); self.wfile.write(payload)
        except Exception as e:
            msg = ('{"error":"%s"}' % str(e)).encode()
            self.send_response(502); self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(msg))); self.end_headers(); self.wfile.write(msg)
    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = _forward

class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == "__main__":
    httpd = S((BIND, PORT), H)
    sys.stderr.write("ollama_auth_proxy listening on %s:%d (upstream %s)\n" % (BIND, PORT, UPSTREAM))
    sys.stderr.flush()
    httpd.serve_forever()
