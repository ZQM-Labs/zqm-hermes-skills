# Evolving-state re-probe (already-audited stack)

When the user asks for the CURRENT state of a stack you already investigated
(e.g. "evolving state of the zbit stack"), this is a LIGHTWEIGHT re-baseline,
NOT a re-investigation. Re-run the headline live probes and report the DELTA
against the last ledger row. Do not re-derive identity/auth posture from scratch —
those are standing facts now; confirm they still hold, then surface what CHANGED.

## Re-baseline probe set (cheap, ~10 calls)
- `netstat -ano | grep -E ":<port>" | grep LISTENING` — confirm each known port
  still bound by the SAME PID.
- `Get-CimInstance Win32_Process -Filter "ProcessId=<pid>"` `.CreationDate` — confirm
  the process did NOT restart since the last pass (a changed CreationDate = silent
  crash+respawn you'd otherwise miss).
- `/health` (open) — confirms process responsive + reports fleet/litellm flags.
- ONE 401 check on a key-gated route (e.g. `GET /v1/agent/status` no key) — confirms
  the auth gate is still enforced (not silently dropped).
- Read the backing store directly to confirm ledger length / persisted state
  (e.g. `ZBit_runtime/ledger/chain.json` block count) — NOT just an HTTP 200.
- `/v1/models` on the proxy — confirm the virtual-model set is unchanged.
- Tail the service logs (`*.log`) for RECENT activity since the last pass.

## DECISIVE NEW SIGNAL: cross-service 404 noise
On a re-probe, watch the service logs for 404s on paths that belong to a DIFFERENT
co-located service. Live case this session: the LiteLLM proxy (`:4001`) logged
404s on `/v1/agent/status`, `/v1/mesh/scan`, `/agent/status`, `/status`, `/mesh/scan`
— all ZBit-Agent-API (`:8400`) route names that LiteLLM does NOT implement.
- Interpretation: a LOCAL caller (loopback) is hitting the WRONG service's route
  namespace — e.g. a client/skill built for the agent API is pointed at the proxy.
  This is NOT an attack (loopback, no such route exists). It FLAGS a config/path
  mismatch in the caller.
- Action: surface it as its own finding ("misrouted client: X-style paths hitting
  :4001"), low impact, and offer to trace the calling process (the client port in
  the litellm log, e.g. `127.0.0.1:65170`, is the loopback peer — read its owner via
  `Get-CimInstance Win32_Process` on that PID once identified).
- Do NOT mistake it for a new vulnerability. It's a routing/namespace confusion
  signal, valuable precisely because it reveals which client is talking to the stack.

## How it differs from the other read-only verbs
- vs silent recon: that's a fleet-wide tags-only pulse across peers. This is a
  per-STACK current-state delta on the hosts already in the ledger.
- vs investigate further: that DEEPENS on a specific anomaly/dependency. This
  re-baselines the WHOLE stack and reports what moved. A follow-on request can be
  either shape — read the user's intent: "what changed / current state" = re-baseline;
  "why is X" = deepen.
- vs endpoint review: that's a fresh port-matrix classification. This re-confirms
  known ports/processes and reports drift.

## Ledger handling
EXTEND the PRIMARY service's existing .db (do NOT spin a new one). Add a state-check
probe row or bump run_meta with a fresh timestamp + a one-line delta summary
("processes stable; ledger 5 blocks unchanged; cross-service 404 noise on :4001 =
misrouted client"). Keep the multi-pass story in the primary ledger's growing probe
count + open_questions resolutions.
