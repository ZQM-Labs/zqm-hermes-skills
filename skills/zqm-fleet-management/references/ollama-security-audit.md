# Ollama LAN Security & Exposure Audit (ZQM fleet)

Technique for auditing the fleet's Ollama servers (port 11434) for unauthenticated
LAN/WAN exposure. Built from the 2026-07-11 audit of Node-1 (.218), Node-4 (.215),
Node-2 (.21). Re-runnable probe script: `scripts/ollama_security_audit.sh`.

## Why this exists as its own procedure
`references/ollama-inventory-methodology.md` covers WHAT models exist where. This
covers the SECURITY POSTURE of those same endpoints: are they exposed, are they
unauthenticated, are they current, and what is the blast radius. Different class.

## Ollama facts you must know before probing
- **No native auth.** Ollama has no API key/token. Anyone who can reach :11434 can
  list, run (/api/generate, /api/chat), pull (/api/pull), create (/api/create),
  push (/api/push), embed (/api/embed), and DELETE (/api/delete) models.
- **0.31.x quirk — `model` field missing => HTTP 404, NOT 400.** In older Ollama a
  missing `model` returned `400 {"error":"model required"}`. In 0.31.x it returns
  `404`. The security signal is the COMPLETE ABSENCE of any 401/403 on write routes.
  Do not misread a 404 as "endpoint doesn't exist" — it means the route WAS reached
  and the server simply couldn't find the named model. A 401/403 would mean an auth
  gate; we never saw one.
- **`/api/version` no longer returns a build date** in 0.31.x — only `{"version":"x.y.z"}`.
  Don't look for a `build` field; get the release date from GitHub instead.
- **`/api/delete` uses method DELETE** (not POST) with body `{"model":"name"}`.
- `OLLAMA_HOST` / bind address is NOT exposed via any API. LAN exposure is proven by
  the fact that a FOREIGN client on the same segment gets valid JSON — if it were
  bound to 127.0.0.1 only, an off-box request would fail to connect / be refused.

## Audit procedure (6 parts the owner expects)
1. **Version + currency.** GET `/api/version` on every host. Compare to the latest
   GitHub release: `curl -s https://api.github.com/repos/ollama/ollama/releases/latest | grep tag_name`.
   State CURRENT vs OUTDATED per host. Get the published date from `published_at`.
2. **Loaded models.** GET `/api/ps` on each — report what's running RIGHT NOW.
3. **LAN exposure confirmation.** State clearly that since a foreign client got valid
   JSON, Ollama is bound to 0.0.0.0 / LAN-exposed (not 127.0.0.1-only). Restate the
   no-auth fact and enumerate what an unauthenticated LAN attacker can do.
4. **Open API surface.** Confirm /api/show works unauthenticated (test on an EXISTING
   model only — never invent a model name for destructive-ish calls). Then probe the
   dangerous write endpoints with EMPTY/missing-model bodies: expect 400/404, NEVER
   401/403. For definitive proof of execution, run ONE harmless real /api/generate on
   the smallest available model (e.g. deepseek-r1:1.5b) with a trivial prompt and
   `stream:false` — capturing real output ("PONG") is the strongest evidence.
5. **WAN exposure = UNVERIFIED GAP.** You cannot test from inside the LAN. Flag it
   explicitly and tell the user to check the router: port-forwarding / NAT / DMZ on
   11434, UPnP/NAPT-PMP leases, IPv6 firewall, and do an OFF-LAN scan (phone on
   cellular: `curl http://<public-ip>:11434/api/tags`).
6. **Risk assessment + mitigations.** Rank hosts by asset value x exposure. Mitigations
   in order: (a) bind OLLAMA_HOST=127.0.0.1 + reverse proxy with basic-auth/TLS or a
   VPN/tunnel (strongest); (b) firewall 11434 to specific source IPs (fast); (c)
   OLLAMA_ORIGINS allow-list (weak — CORS only, does NOT authenticate non-browser
   callers, defense-in-depth only).

## Non-destructive probing discipline
- Empty-body / missing-model probes for /api/pull, /api/create, /api/delete,
  /api/generate are SAFE — they never actually pull/delete/run anything.
- /api/show on an existing model is read-only (returns license/metadata).
- The ONE real /api/generate is the only "live action"; keep it tiny-model + trivial
  prompt so it loads fast and costs no real compute. It is the proof of execution.

## 2026-07-11 findings (evidence, for re-baseline)
- Hosts: 192.168.1.218 (Node-1, 2 models), .215 (Node-4, 45 models/451.6GB),
  .21 (Node-2, 8 models). All on **0.31.2** = latest (v0.31.2, published 2026-07-06)
  -> ALL CURRENT.
- /api/ps empty on all three at audit time.
- LAN-exposed confirmed: foreign client got valid JSON from all three.
- /api/show unauthenticated: returned real license metadata on all three.
- Real /api/generate on .21 (deepseek-r1:1.5b) -> HTTP 200, `{"response":"PONG"}`
  -> unauthenticated execution PROVEN.
- Write routes: no 401/403 anywhere (404 for missing model in 0.31.x). /api/generate
  with `{}` -> 404; /api/pull `{}` -> 400; /api/create `{}` -> 400; /api/delete (DELETE,
  probe name) -> 404 "model not found".
- WAN: UNVERIFIED — user must check router.

## Risk ranking used (asset-value driven; exposure identical across hosts)
1. **HIGHEST — .215 (Node-4):** 451 GB model hoard = largest delete blast radius,
   biggest free-compute honeypot, biggest WAN-bandwidth sink if /api/pull abused.
2. **HIGH — .218 (Node-1):** only 2 models but the user's daily-driver + LAN control
   plane = pivot point, highest strategic value.
3. **MEDIUM — .21 (Node-2):** 8 models, dedicated server, no personal data.

## Mitigation snippets
nginx basic-auth front (after OLLAMA_HOST=127.0.0.1:11434):
```
location / {
  auth_basic "Ollama";
  auth_basic_user_file /etc/nginx/ollama.htpasswd;
  proxy_pass http://127.0.0.1:11434;
}
```
OLLAMA_ORIGINS is CORS-only — supplement, never primary control.
