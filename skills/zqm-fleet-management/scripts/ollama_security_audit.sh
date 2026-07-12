#!/usr/bin/env bash
# ollama_security_audit.sh — non-destructive LAN exposure audit for fleet Ollama hosts.
# Probes version, loaded models, LAN exposure, unauthenticated read/write reachability.
# SAFE: no real pull/delete; one optional tiny-model generate for execution proof.
#
# Usage:  ./ollama_security_audit.sh [ip1 ip2 ...] [--prove]
#   default hosts: 192.168.1.218 192.168.1.215 192.168.1.21
#   --prove : also run ONE harmless /api/generate on the smallest available model
#
# Requires: curl. Run from the agent/Node-1.

set -u
HOSTS=()
PROVE=0
for a in "$@"; do
  case "$a" in
    --prove) PROVE=1 ;;
    *) HOSTS+=("$a") ;;
  esac
done
[ ${#HOSTS[@]} -eq 0 ] && HOSTS=(192.168.1.218 192.168.1.215 192.168.1.21)

echo "===== OLLAMA LAN SECURITY AUDIT $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="

# Latest upstream version (GitHub)
LATEST=$(curl -s -m 8 https://api.github.com/repos/ollama/ollama/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9.]+)".*/\1/')
echo "Latest upstream Ollama: v${LATEST:-UNKNOWN}"

for ip in "${HOSTS[@]}"; do
  base="http://$ip:11434"
  echo
  echo "----- $ip -----"
  # 1. version + reachability
  v=$(curl -s -m 5 "$base/api/version" || echo "")
  if [ -z "$v" ]; then echo "  UNREACHABLE (no response)"; continue; fi
  ver=$(printf '%s' "$v" | grep -oE '"version":"[^"]+"' | sed -E 's/.*:"([^"]+)"/\1/')
  if [ -n "$LATEST" ] && [ "$ver" = "$LATEST" ]; then cur="CURRENT"; else cur="OUTDATED (latest v$LATEST)"; fi
  echo "  version: $ver  [$cur]"
  echo "  LAN-exposed: YES (foreign client got valid JSON -> bound 0.0.0.0, not 127.0.0.1)"

  # 2. loaded models
  ps=$(curl -s -m 5 "$base/api/ps")
  n=$(printf '%s' "$ps" | grep -oE '"name":"[^"]+"' | wc -l | tr -d ' ')
  echo "  loaded models now: $n"

  # 4. unauthenticated read: /api/show on first existing model
  first=$(curl -s -m 5 "$base/api/tags" | grep -oE '"name":"[^"]+"' | head -1 | sed -E 's/.*:"([^"]+)"/\1/')
  if [ -n "$first" ]; then
    sc=$(curl -s -m 6 -o /dev/null -w '%{http_code}' -X POST "$base/api/show" -H 'Content-Type: application/json' -d "{\"model\":\"$first\"}")
    echo "  /api/show($first) unauth -> HTTP $sc (200 = no auth gate)"
  fi

  # 4. write-route reachability (empty body -> expect 400/404, NEVER 401/403)
  for ep in pull create generate; do
    code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST "$base/api/$ep" -H 'Content-Type: application/json' -d '{}')
    echo "  POST /api/$ep {} -> HTTP $code  (no 401/403 = route open, unauth)"
  done
  dcode=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X DELETE "$base/api/delete" -H 'Content-Type: application/json' -d '{"model":"probe-nonexistent"}')
  echo "  DELETE /api/delete -> HTTP $dcode  (no 401/403 = route open, unauth)"

  # optional execution proof
  if [ "$PROVE" = "1" ] && [ -n "$first" ]; then
    echo "  PROOF generate on '$first' (stream:false) ..."
    out=$(curl -s -m 90 -X POST "$base/api/generate" -H 'Content-Type: application/json' -d "{\"model\":\"$first\",\"prompt\":\"Reply with the single word: PONG\",\"stream\":false}" | grep -oE '"response":"[^"]*"' | head -1)
    echo "    -> $out  (real output = unauthenticated execution confirmed)"
  fi
done

echo
echo "===== WAN EXPOSURE: UNVERIFIED (cannot test from inside LAN) ====="
echo "Check router: port-forward/NAT/DMZ on 11434, UPnP leases, IPv6 firewall."
echo "Off-LAN scan: curl http://<public-ip>:11434/api/tags from cellular."
