#!/usr/bin/env bash
# ollama-lan-scan.sh — enumerate Ollama servers on 192.168.1.0/24 (or $1 subnet)
# Usage:  ollama-lan-scan.sh                 # scans 192.168.1.0/24
#         ollama-lan-scan.sh 10.0.0.0/24     # custom subnet (CIDR /24 only)
# Prints only hosts that answer /api/tags (HTTP 200). Safe — read-only.
set -u
SUBNET="${1:-192.168.1}"
echo "=== Scanning ${SUBNET}.0/24 on :11434 (Ollama) ==="
for i in $(seq 1 254); do echo "${SUBNET}.$i"; done \
  | xargs -P 80 -I{} curl -s -m 1 --connect-timeout 1 -o /dev/null -w "%{http_code} {}\n" \
    "http://{}:11434/api/tags" 2>/dev/null \
  | grep -v '^000' || echo "no Ollama servers found"

echo
echo "=== Per-host model counts (live /api/tags) ==="
for h in $(curl -s -m 1 --connect-timeout 1 -o /dev/null -w "%{http_code} %{url_effective}\n" \
            "http://${SUBNET}.1:11434/api/tags" 2>/dev/null | grep -v '^000' >/dev/null; \
          seq 1 254 | while read i; do
            code=$(curl -s -m 1 --connect-timeout 1 -o /dev/null -w "%{http_code}" "http://${SUBNET}.$i:11434/api/tags" 2>/dev/null)
            [ "$code" = "200" ] && echo "${SUBNET}.$i"
          done); do
  python3 - "$h" <<'PY'
import json,sys,urllib.request
h=sys.argv[1]
try:
    d=json.load(urllib.request.urlopen(f"http://{h}:11434/api/tags",timeout=5))
    ms=d.get("models",[])
    tot=sum(m.get("size",0) for m in ms)
    print(f"{h}: {len(ms)} models, {tot/1e9:.1f} GB")
except Exception as e:
    print(f"{h}: ERROR {e}")
PY
done
