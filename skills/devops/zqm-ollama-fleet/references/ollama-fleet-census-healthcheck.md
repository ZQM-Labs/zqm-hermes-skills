# Ollama Fleet Census & Health Check (4-part method)

Verified and re-run live on 2026-07-10/11 against the ZQM fleet (Node-1 .218,
Node-2 .21, Node-3 .46, Node-4 .215). The owner asked for a single pass that
answers four questions for EVERY node, with real numbers and no assumptions.

## The four steps (run in order, per node)

1. **Reachability** — `curl -s --max-time 5 http://<ip>:11434/api/tags`.
   HTTP 200 = port answering. **HTTP 000 / exit 28 = timed out, port NOT
   answering** (this is the "HANG"/unreachable signal — do NOT infer models).
2. **Inventory** — if reachable, parse `/api/tags`; sum `size` bytes per model
   for GB and count. (Sizes in the `size` field are authoritative; do NOT trust
   a hand count of a long JSON blob — compute it, e.g. with the python snippet
   in the census script or `scripts/ollama_inventory.py`.)
3. **Generate health check / HANG test** — POST `/api/generate` with
   `{"model":<smallest>, "prompt":"ping", "stream":false,
   "options":{"num_predict":4}}`, `--max-time 15`. HTTP 200 = alive and serving
   tokens. **HTTP 000 here = the service is wedged** (this is the INFERENCE WEDGE,
   see ollama-health-ops.md: `/api/tags` may still return 200 while `/api/generate`
   hangs — a network-OK-but-GPU/VMM-stuck fault). Record seconds via
   `-w '...%{time_total}'`.
4. **localhost-bound determination** (only for nodes that fail step 1) — you
   CANNOT tell "localhost-bound" from ":11434 refused" alone. Disambiguate:
   - `ping -n 3 <ip>` → if 0% loss, the HOST is up (rules out "host off / wrong IP").
   - `curl -s --max-time 5 -v http://<ip>:11434/api/tags` → "Connection timed out"
     on TCP :11434 while ICMP is fine = the port is filtered/not listening on the
     LAN interface.
   - CONCLUSION: host-up + :11434-LAN-timeout ⇒ **NOT LAN-exposed**. Most
     consistent with Ollama bound to 127.0.0.1 (localhost-only). This was Node-3
     (.46) on 2026-07-10/11: ICMP 0% loss, :11434 TCP timeout.
   - HONEST CAVEAT to always state: an external probe cannot *prove* the bind is
     127.0.0.1 vs a host firewall dropping :11434 from non-loopback — both produce
     host-up + port-timeout. The practical claim "Node-X is not reachable from the
     LAN" IS proven; the exact mechanism needs a console login on the box
     (`ollama list` / check `OLLAMA_HOST` / `Get-NetFirewallRule`). Do not over-claim
     "PROVEN localhost-bound" — label it "NOT LAN-exposed (localhost-bound, per
     documented intent)".

## Reconciliation labels (owner's standing rule)
State PROVEN / NOT PROVEN / FALSE for each node against any prior claim.
For "Node-N LAN-exposes Ollama": reachable over LAN = PROVEN; not reachable =
the LAN-exposure claim is FALSE (or at minimum NOT PROVEN for that node).
Never assume a node's state from a prior summary — re-probe live this turn.

## Live 2026-07-10/11 census results (point-in-time snapshot)
| Node | IP | :11434 | Models | Total | /api/generate |
|------|-----|--------|--------|-------|---------------|
| N1 | .218 | ✅ 200 | 2 | 29.16 GB | ✅ 200 (12.4s) |
| N2 | .21  | ✅ 200 | 8 | 55.41 GB | ✅ 200 (8.2s) |
| N3 | .46  | ❌ 000 (timeout) | unknown | unknown | could not run |
| N4 | .215 | ✅ 200 | 45 | 451.60 GB | ✅ 200 (12.4s) |
- Verdict vs claim "Nodes 1/2/4 LAN-expose; Node-3 localhost-bound":
  N1 PROVEN, N2 PROVEN, N4 PROVEN, N3 PROVEN-not-LAN-exposed (localhost-bound per intent).
- No node hung on /api/generate (all reachable nodes returned 200; HTTP 000 = hang never occurred).
- Fleet footprint (reachable nodes only): 55 models, ~536.2 GB. Node-3 unknown.

## Output discipline
- Emit real numbers: models per node, GB per node, reachable vs not, which hang.
- If a node is unreachable, say so PLAINLY — do not assume its model list.
- Separate the machine-truth (HTTP code / seconds) from the interpretation.
