# Ollama LAN Endpoint Audit — reusable probe recipe

Use when the user asks to inventory, locate, or assess Ollama model servers on the
ZQM LAN (or any LAN). This is a class-level technique, not a one-off. The agent's
sandbox has repeatedly been able to reach 192.168.1.0/24, so these curl checks run
from `terminal()` directly — no need to drive a node console.

## 1. Discover every Ollama endpoint (full /24 scan)
Ollama listens on TCP 11434. Scan the whole subnet in parallel; anything returning
HTTP 200 on `/api/tags` is a live server.

```bash
for i in $(seq 1 254); do echo "192.168.1.$i"; done \
  | xargs -P 60 -I{} curl -s -m 1 --connect-timeout 1 -o /dev/null -w "%{http_code} {}\n" "http://{}:11434/api/tags" 2>/dev/null \
  | grep -v '^000'
```
A `000` = host down or no Ollama. Any non-000 response = a server. (Do NOT trust a
prior inventory's IP list — rescan fresh; nodes reboot and IPs shift, see
zqm-fleet-management Node-4 reboot pitfall.)

## 2. Enumerate models + real sizes per host
```bash
curl -s -m 4 "http://<ip>:11434/api/tags" -o /tmp/tags_<ip>.json
python -c "import json; d=json.load(open('/tmp/tags_<ip>.json')); ms=d['models']; print(len(ms),'models', round(sum(m.get('size',0) for m in ms)/1e9,1),'GB')"
```

## 3. Version currency — use the GitHub releases API, NOT web_search
web_search results for "latest Ollama version" are stale/inaccurate (one pass returned
0.30.10 as latest when 0.31.2 was current). The authoritative source is the releases API:
```bash
curl -s -m 8 "https://api.github.com/repos/ollama/ollama/releases?per_page=8" \
  | python -c "import json,sys; [print(r['tag_name'], r.get('published_at')) for r in json.load(sys.stdin)]"
```
- Latest STABLE = highest non-`-rc` tag. A `v0.x.0-rcN` is a pre-release; do not call
  a host "outdated" just because it's below an -rc.
- Compare each host's `GET /api/version` against that latest stable tag.

## 4. What is loaded RIGHT NOW
```bash
curl -s -m 4 "http://<ip>:11434/api/ps"
```
Real detail example from a 32b model: `size_vram`, `quantization_level` (e.g. Q4_K_M),
`context_length`. Empty `{"models":[]}` = nothing running.

## 5. Unauthenticated-exposure check (Ollama ships NO native auth)
Confirm the gap empirically, don't just assert it:
- `POST /api/show` with an existing model, no creds -> expect HTTP 200 (metadata leaks).
- `POST /api/generate` with a BOGUS model name, no creds -> expect HTTP 404 (Ollama
  tried to run it and failed on "model not found"), NOT 401/403. A 404 vs 401 is the
  proof that the endpoint is open without credentials. Anyone on the LAN can
  list/run/pull/delete models.
Mitigations to recommend: firewall 11434 to specific source IPs, bind Ollama to
127.0.0.1 behind an nginx reverse proxy with basic-auth/tunnel, or set
`OLLAMA_ORIGINS` allow-list.

## 6. Latency sampling
```bash
for n in 1 2 3; do curl -s -o /dev/null -w "%{time_connect} %{time_total}\n" "http://<ip>:11434/api/tags"; done
```
Empty `/api/tags` does not touch VRAM, so variance here is network, not model load.

## 7. Alias vs DISTINCT host disambiguation (the trap this session)
A prior agent reported 192.168.1.21 as a "DNS alias of 192.168.1.215". FALSE. Disambiguate
by diffing the model-name SETS from `/api/tags`:
```bash
python -c "import json; a={m['name'] for m in json.load(open('/tmp/tags_215.json'))['models']}; b={m['name'] for m in json.load(open('/tmp/tags_21.json'))['models']}; print('identical:',a==b); print('only in .215:',a-b); print('only in .21:',b-a)"
```
- Identical lists = alias/proxy to the same backend.
- Disjoint or partially overlapping = DISTINCT hosts. (Overlap on a few models like
  `qwen3.6:latest` is normal cross-node co-residency, not proof of aliasing.)

## 8. WAN exposure is UNVERIFIABLE from inside the LAN
The agent's checks run from within 192.168.1.0/24, so they CANNOT see whether 11434 is
open on the router/WAN side. Explicitly FLAG this as an unverified gap and tell the user
to check their router for port-forwarding / an exposed 11434. Do not claim "safe" or
"exposed" on the WAN — you cannot measure it from here.

## Worked example (2026-07-10)
- 3 hosts found: .218 (Node-1, 2 models/29.2 GB), .215 (Node-4, 45 models/451.6 GB),
  .21 (Node-2, 8 models/55.4 GB). No Ollama on Node-3 (.46), Gardens (.173/.40), or anywhere else.
- All three at Ollama 0.31.2 = CURRENT (latest stable v0.31.2; v0.32.0-rc0 pre-release).
- Node-4 had `qwq:32b` loaded: 14.86 GB VRAM, Q4_K_M, 40960 ctx.
- A prior agent's inventory was FALSE on 3 points (claimed .21 was .215's alias; counted
  43 not 45 models; stated ~325 GB not 451.6 GB). Corrected by re-scan + live pulls.
