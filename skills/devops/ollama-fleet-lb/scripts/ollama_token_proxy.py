# ollama_token_proxy.py — stdlib token-gated reverse proxy for Ollama (no deps).
# Gate a single node's Ollama on the LAN: bind the proxy to the LAN IP :11434, rebind Ollama
# to 127.0.0.1:11434. LAN callers need `Authorization: Bearer <token>`; loopback stays open.
# Verified 2026-07-11: no-token=401, with-token=200, loopback=200.
# REVERSIBLE: kill this + unset OLLAMA_HOST + restart ollama serve.
import http.server, socketserver, urllib.request, os, sys

TOKEN = os.environ.get("OLLAMA_PROXY_TOKEN") or ""
TOKEN_FILE = os.environ.get("OLLAMA_PROXY_TOKEN_FILE")
if not TOKEN and TOKEN_FILE and os.path.exists(TOKEN_FILE):
    TOKEN = open(TOKEN_FILE, "r").read().strip()

UPSTREAM = os.environ.get("OLLAMA_PROXY_UPSTREAM", "http://127.0.0.1:11434")
BIND = os.environ.get("OLLAMA_PROXY_BIND", "0.0.0.0")
PORT = int(os.environ.get("OLLAMA_PROXY_PORT", "11434"))

if not TOKEN:
    sys.stderr.write("FATAL: no token set (OLLAMA_PROXY_TOKEN or OLLAMA_PROXY_TOKEN_FILE)\n")
    sys.exit(2)

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def _deny(self):
        body = b'{"error":"unauthorized: missing/invalid Bearer token"}'
        self.send_response(401)
        self.send_header("Content-Type", "application/json")
        self.send_header("WWW-Authenticate", 'Bearer realm="ollama"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def _forward(self):
        if self.headers.get("Authorization", "") != "Bearer " + TOKEN:
            self._deny(); return
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(UPSTREAM + self.path, data=body, method=self.command)
        ct = self.headers.get("Content-Type")
        if ct: req.add_header("Content-Type", ct)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                self.send_response(r.status)
                for h in ("Content-Type", "Transfer-Encoding"):
                    if r.headers.get(h): self.send_header(h, r.headers[h])
                cl = r.headers.get("Content-Length")
                if cl: self.send_header("Content-Length", cl)
                self.end_headers()
                while True:
                    buf = r.read(65536)
                    if not buf: break
                    self.wfile.write(buf)
        except urllib.error.HTTPError as e:
            payload = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers(); self.wfile.write(payload)
        except Exception as e:
            msg = ('{"error":"%s"}' % str(e)).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers(); self.wfile.write(msg)
    do_GET = _forward; do_POST = _forward; do_PUT = _forward
    do_DELETE = _forward; do_HEAD = _forward

class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == "__main__":
    httpd = S((BIND, PORT), H)
    sys.stderr.write("ollama_token_proxy on %s:%d upstream=%s\n" % (BIND, PORT, UPSTREAM))
    sys.stderr.flush()
    httpd.serve_forever()
