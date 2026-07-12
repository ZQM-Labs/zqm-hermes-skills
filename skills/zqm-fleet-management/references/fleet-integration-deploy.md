# Ollama fleet integration — DEPLOYING the fuller config (runtime reality)

The ZQM fleet has a COMPLETE 69-route LiteLLM config on the Desktop
(`C:\Users\zqmco\Desktop\ollama-fleet\litellm_config.yaml`) — every verified
model across N4 (.215) / N2 (.21) / N1 (.218) plus aggregated aliases
(`fast-chat`, `heavy-reasoning`, `embeddings`, `vision`). But the RUNNING proxy
on Node-1 is often NOT that config. This session (2026-07-11) the live proxy
(:4001) served only `zbit-router` / `zbit-fast` / `zbit-heavy` from a minimal
`ZBit_api\litellm_config.yaml`. So "improve integrations" = deploy the fuller
config, corrected — not write one from scratch.

## Step 1 — detect the drift (live)
```
curl -s http://127.0.0.1:4001/v1/models        # what the proxy actually serves
# compare to the 69-route Desktop config on disk
# also note: running port may differ from file `server.port` (CLI --port overrides)
```
If `/v1/models` lists only a few aliases while the Desktop config has 69, the
fuller fabric is NOT deployed.

## Step 2 — the TWO real blockers (verify before deploying)
### Blocker A — `LITELLM_MASTER_KEY` unset → proxy won't start (HIGH)
```
powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('LITELLM_MASTER_KEY','Machine')"
# empty => Desktop config `master_key: ${LITELLM_MASTER_KEY}` aborts startup.
# ALSO means the current proxy has NO auth (see remediation A in audit).
```
Fix: generate a strong key (`secrets.token_hex(24)`), inject it into the config,
persist to machine env + `.env.integrated`. This simultaneously closes the
"no master_key" finding.

### Blocker B — 53× `keep_alive: '-1'` → VRAM OOM (MEDIUM)
The Desktop snapshot pins every model resident forever. On N4 (45 models,
finite VRAM) this exhausts memory. This VIOLATES the standing ZBit policy
"NEVER -1". Fix: rewrite `keep_alive: '-1'` → tiered TTL (`5m` small / `10m`
heavy) before deploy. (See skill pitfall #1 — this is the same OOM risk, caught
at deploy time instead of first boot.)

## Step 3 — the integrator pattern (reusable, dry-run safe)
Generate the target config FROM the Desktop snapshot (don't hand-type 69 routes):
1. Read `Desktop\ollama-fleet\litellm_config.yaml`.
2. Regex-rewrite `keep_alive: '-1'` → TTL (Blocker B fix).
3. Replace `master_key: ${LITELLM_MASTER_KEY}` with the generated key (Blocker A fix).
4. Force `host: 127.0.0.1` (loopback-only — never expose the proxy).
5. Merge router retries (`num_retries: 3`, `retry_after: 2`, `timeout: 60`,
   fallbacks) so a slow N4 heavy route fails over instead of 500-cascading.
6. `yaml.safe_load` the output → FAIL the deploy if it doesn't parse.
7. DEFAULT = dry-run: write `litellm_config.integrated.yaml`, report route count +
   remaining `'-1'` + YAML-OK. `--apply` copies over the running config (backup
   first), sets the machine env, and you restart the proxy (via supervision).

Reusable script: **scripts/integrate_fleet.py** (reads the Desktop snapshot,
applies the above, dry-run by default).

## Step 4 — post-deploy verification
```
curl -s http://127.0.0.1:4001/v1/models     # now shows fast-chat/heavy-reasoning/...
curl -s -H "Authorization: Bearer <key>" http://127.0.0.1:4001/v1/models   # 200
curl -s http://127.0.0.1:4001/v1/models     # without key -> 401 (auth now enforced)
```

## Open WebUI is a SEPARATE layer
This session confirmed NO Open WebUI anywhere (:3000/:8080 dead). The fabric
terminates at the LiteLLM API. Standing one up is a distinct (bigger) task —
container/install + point it at the proxy. Decide separately from the LB
integration. Don't claim "fabric complete" if only the API exists.

## THREE forensic principles that CLOSE "unresolved" audit items WITHOUT peer creds
(These let the lead re-verify headline claims lead-side, honoring the
"investigate fully / verify claims" mandate without sourcing node passwords.)

### P1 — `sshd -G` gives the EFFECTIVE config (resolves commented defaults)
`sshd_config` had `#PasswordAuthentication yes` (commented = default). To PROVE
the effective state, run `sshd -G` (path: `C:\Program Files\OpenSSH\sshd.exe -G`)
and parse the dumped effective lines:
```
passwordauthentication: yes      # PROVEN pw-auth ON
authenticationmethods: any       # any single method = access
pubkeyauthentication: yes        # pubkey also on -> can enforce
```
This turned an INFERENCE ("default = yes") into PROOF. Use it whenever a config
value is commented and you must state the effective behavior.

### P2 — Windows Firewall BLOCK overrides ALLOW on overlapping match
To prove an external block holds WITHOUT a peer-box probe: dump the rules for the
port and apply the deterministic precedence. This session:
```
ZQM-Ollama-LAN-Block      Action=Block  RemoteIP=192.168.1.0/24
Ollama-LAN-only-11434     Action=Allow  RemoteIP=192.168.1.0/24   (STALE)
# BLOCK wins on the overlapping 192.168.1.0/24 match -> LAN peer DENIED.
# Loopback 127.0.0.1 matches only ZQM-Ollama-Loopback-Allow -> ALLOW.
```
So a LAN peer is denied deterministically; the stale Allow rule is superseded
(hygiene-only, safe to delete later). Resolves "is the external block effective?"
as PROVEN-by-precedence, no creds needed.

### P3 — bare `socket.recv()` after `connect()` is a FALSE-NEGATIVE trap
`connect()` can SUCCEED while `recv()` blocks/timeouts — the server sends nothing
unsolicited, so `recv` hangs and you misread "BLOCKED". Hit TWICE this session
(Redis pulse, N1 reachability). Always VERIFY reachability with a real request:
- HTTP services: `curl -s -m 5 -o /dev/null -w "%{http_code}" http://<ip>:<port>/<path>`
  (HTTP 200 = reachable; this corrected a false "TimeoutError" from bare recv).
- Redis: send `PING\r\n` then `recv` (server DOES reply → +PONG).
- Raw protocols: send the expected request before recv, or use a short timeout +
  2-3 retries. NEVER conclude "down" from a single bare-recv timeout.
This is the INVERSE of the known "TCP connect false-positive" trap (a lone
`connect` success can be a scanner reset). Both directions bite; both need a
second confirming method.
