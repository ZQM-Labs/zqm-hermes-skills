#!/usr/bin/env python3
"""
api_server.py -- TEMPLATE: serve a live claim attestation over HTTP.

Stdlib-only (no fastapi/uvicorn needed). Imports build_attestation() from
claims_core.py (the shared core) so the API and the offline manifest writer
cannot diverge.

LESSON (2026-07-12): never call the slow probe-driven build_attestation()
more than ONCE per request. The first version called it 3x for /attest/claim/<ID>
and timed out under a 15s-capped curl client (~15s per build from live
curl/redis/powershell probes). Build ONCE into a local var, reuse.

Run:  python api_server.py [--host 127.0.0.1] [--port 8088]
Read-only: never writes to an audit DB or guesses credentials.
"""
import json, sys, argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from claims_core import build_attestation

class H(BaseHTTPRequestHandler):
    server_version = "Attest/1.0"
    def _send(self, code, obj):
        body = json.dumps(obj, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/")
        try:
            att = build_attestation()   # BUILD ONCE per request
            if path in ("", "/"):
                self._send(200, {
                    "service": "claim attestation API", "version": "1.0",
                    "endpoints": ["/attest", "/attest/summary", "/attest/claim/<ID>",
                                  "/attest/chain", "/attest/probes", "/audit/chain"],
                })
            elif path == "/attest":
                self._send(200, att)
            elif path == "/attest/summary":
                self._send(200, {
                    "claim_count": att["claim_count"], "tally": att["tally"],
                    "chain_root": att["chain_root"], "audit_db_chain": att["audit_db_chain"],
                })
            elif path.startswith("/attest/chain"):
                self._send(200, {"chain_root": att["chain_root"], "chain": att["chain"]})
            elif path == "/attest/probes":
                self._send(200, att["probes"])
            elif path.startswith("/attest/claim/"):
                cid = path.rsplit("/", 1)[-1].upper()
                hit = [c for c in att["claims"] if c["id"].upper() == cid]
                if hit:
                    self._send(200, hit[0])
                else:
                    self._send(404, {"error": "unknown claim id", "id": cid,
                                      "known": [c["id"] for c in att["claims"]]})
            elif path == "/audit/chain":
                self._send(200, att["audit_db_chain"])
            else:
                self._send(404, {"error": "unknown endpoint", "path": path})
        except Exception as e:
            self._send(500, {"error": str(e)[:200]})
    def log_message(self, *a):
        pass

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8088)
    args = ap.parse_args()
    srv = ThreadingHTTPServer((args.host, args.port), H)
    print("attestation API on http://%s:%d  (Ctrl-C to stop)" % (args.host, args.port))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")

if __name__ == "__main__":
    main()
