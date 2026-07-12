# LAN Service Inventory & Discovery (whole-subnet sweep)

Companion to the reachability probe. Use when the user asks for a *service inventory*
("what Ollama/HTTP/etc. servers are on the LAN", "any other hosts serving X") rather
than just "is Node-N up". The reachability probe answers one host; this answers the
whole /24.

## When to use
- "Are there other Ollama servers on the LAN?" / "inventory all X endpoints"
- After a sub-agent (Cline, Codex, etc.) hands back a service list — RE-VERIFY independently.
  Sub-agent inventories have shipped with false claims (missing hosts, fabricated alias
  relationships, undercounted totals). Treat them as untrusted until re-scanned.

## Method (proven 2026-07-10, sandbox CAN reach 192.168.1.0/24)
The Hermes sandbox reached the user LAN directly (real HTTP 200s, not simulated), so a
plain `curl` sweep from the terminal works. No need to proxy through Node-1.

1. Control test first — confirm LAN reachability with a known-good host:
   `curl -s -m 4 -o /dev/null -w "%{http_code}\n" http://192.168.1.218:11434/api/tags`
   If that returns 200, the sandbox is on the subnet and the full scan is valid.

2. Full /24 sweep on the service port (parallel, short timeout so dark hosts don't stall):
   ```bash
   for i in $(seq 1 254); do echo "192.168.1.$i"; done \
     | xargs -P 60 -I{} curl -s -m 1 --connect-timeout 1 -o /dev/null -w "%{http_code} {}\n" "http://{}:PORT/path" \
     | grep -v '^000'
   ```
   Any host returning non-000 is serving the service. Count = real host count.

3. Pull the service API from each live host and parse:
   ```bash
   for ip in 192.168.1.218 192.168.1.215 192.168.1.21; do
     curl -s -m 4 "http://$ip:11434/api/tags" -o "/tmp/tags_$ip.json"
   done
   ```
   Then JSON-parse `size` fields for totals (Ollama reports bytes; divide by 1e9 for GB).

4. ALIAS vs DISTINCT HOST check — never assume two IPs are the same box because they
   share a subnet region or a human called one an "alias". Diff the actual payloads:
   ```python
   import json
   a={m['name'] for m in json.load(open('/tmp/tags_192.168.1.215.json'))['models']}
   b={m['name'] for m in json.load(open('/tmp/tags_192.168.1.21.json'))['models']}
   print('identical lists:', a==b)
   print('only in .215:', a-b); print('only in .21:', b-a)
   ```
   Disjoint-but-for-a-few-shared models => two DISTINCT hosts. Same exact list => alias/mirror.

## Worked result (2026-07-10) — Ollama inventory
Three hosts serve Ollama (NOT two, contrary to a prior sub-agent report):
- 192.168.1.218 (Node-1, local) — 2 models, 29.2 GB
- 192.168.1.215 (Node-4) — 45 models, 451.6 GB
- 192.168.1.21  (Node-2) — 8 models, 55.4 GB  <- a SEPARATE host, NOT an alias of .215
No Ollama on Node-3 (.46), GARDEN-01 (.173), GARDEN-02 (.40), or any other /24 host.

Sub-agent (Cline) errors this technique caught and corrected:
- Claimed `.21` was a DNS alias of `.215` -> FALSE (distinct hosts, disjoint model lists).
- Reported 2 hosts -> actual 3.
- Counted Node-4 at "43 models / ~325 GB" -> actual 45 / 451.6 GB (real `size` fields).
- Never inventoried Node-2's unique models (gemma4, deepseek-coder-v2:16b, hermes3, llava:7b, phi3:mini).

## Pitfalls
- A sub-agent's inventory is a CLAIM, not evidence. Re-scan before reporting host counts or
  alias relationships as fact.
- Adjacent IPs != same host. `.21` and `.215` are both real ZQM nodes (see topology in SKILL.md).
- Don't trust "alias" assertions from prior reports — verify by payload diff.
- `grep -v '^000'` is what isolates live hosts; a plaintext `000` means connection failed
  (host down / no service / firewalled on that port).
- Sizes from Ollama `size` are uncompressed blob bytes; "GB" here = size/1e9.
