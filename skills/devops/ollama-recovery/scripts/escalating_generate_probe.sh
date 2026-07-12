#!/usr/bin/env bash
# ESCALATING-TIMEOUT Ollama generate probe — distinguish SLOW COLD-LOAD from PERMANENT HANG.
# For each node: GET /api/tags (5s) -> first model; POST /api/generate @20s -> if 000, @45s.
#   20s=200       -> HEALTHY
#   20s=000,45s=200 -> SLOW COLD-LOAD (not hung)
#   20s=000,45s=000 -> PERMANENT HANG (recover)
#   400 in <0.1s  -> malformed payload (CRLF bug), NOT a hang
# CRLF-safe: model name passed through tr -d '\r' before building JSON.
set -u
PORT=11434
NODES="N1:192.168.1.218 N2:192.168.1.21 N3:192.168.1.46 N4:192.168.1.215"

for n in $NODES; do
  node=${n%%:*}; ip=${n##*:}
  echo "================ $node ($ip) ================"
  tb=$(curl -s -m 5 -w $'\n__HTTP__%{http_code}' "http://$ip:$PORT/api/tags")
  code=$(printf '%s' "$tb" | sed -n 's/.*__HTTP__//p'); tb=$(printf '%s' "$tb" | sed '/__HTTP__/d')
  if [ "$code" != "200" ]; then
    [ "$node" = "N3" ] && { sleep 10; tb=$(curl -s -m 5 -w $'\n__HTTP__%{http_code}' "http://$ip:$PORT/api/tags"); code=$(printf '%s' "$tb" | sed -n 's/.*__HTTP__//p'); tb=$(printf '%s' "$tb" | sed '/__HTTP__/d'); }
  fi
  if [ "$code" != "200" ]; then
    echo "  tags=$code -> not reachable from sandbox; $([ "$node" = N3 ] && echo UNRESOLVED-not-down || echo service/port down)"; echo; continue
  fi
  M=$(printf '%s' "$tb" | python -c "import json,sys;print(json.load(sys.stdin)['models'][0]['name'])" 2>/dev/null | tr -d '\r')
  [ -z "$M" ] && { echo "  tags=200 but no models; skip"; echo; continue; }
  echo "  tags=200 first_model=$M"
  out=$(curl -s -m 20 -o /dev/null -w '%{http_code} %{time_total}' -X POST "http://$ip:$PORT/api/generate" -H 'Content-Type: application/json' -d "{\"model\":\"$M\",\"prompt\":\"ping\",\"stream\":false}")
  g20=$(printf '%s' "$out" | awk '{print $1}'); t20=$(printf '%s' "$out" | awk '{print $2}')
  if [ "$g20" = "000" ]; then
    echo "  gen20=000 ${t20}s -> TIMEOUT, escalate 45s"
    out=$(curl -s -m 45 -o /dev/null -w '%{http_code} %{time_total}' -X POST "http://$ip:$PORT/api/generate" -H 'Content-Type: application/json' -d "{\"model\":\"$M\",\"prompt\":\"ping\",\"stream\":false}")
    g45=$(printf '%s' "$out" | awk '{print $1}'); t45=$(printf '%s' "$out" | awk '{print $2}')
    if [ "$g45" = "000" ]; then echo "  gen45=000 ${t45}s -> PERMANENT HANG (recover)"; else echo "  gen45=$g45 ${t45}s -> SLOW COLD-LOAD (not hung)"; fi
  else
    if [ "$g20" = "200" ]; then echo "  gen20=200 ${t20}s -> HEALTHY"; elif [ "$g20" = "400" ]; then echo "  gen20=400 ${t20}s -> MALFORMED PAYLOAD (CRLF bug?), not hang"; else echo "  gen20=$g20 ${t20}s -> HTTP $g20 (not a hang)"; fi
  fi
  echo
done
echo "PROBE COMPLETE"
