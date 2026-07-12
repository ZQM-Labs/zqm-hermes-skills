# Genesis + Hash-Drift Investigation Sequence (HIT 2026-07-11)

The user runs a recurring three-beat investigation over findings. Encode it as a repeatable pass,
distinct from the "hash claims" verb (which only mints the hashes — this adds genesis + drift).

## Beat 1 — HASH CLAIMS
Mint SHA-256 over each load-bearing claim (`status‡claim‡evidence`, U+241F separator — see
`references/hashed-claim-manifest.md`). Persist a `claim_hash` table. Tag PROVEN / NOT PROVEN / FALSE.
(For the fleet audit, the `fleet_endpoint_audit.db` already has `claim_hash`.)

## Beat 2 — INVESTIGATE GENESIS (root cause + intent)
For each anomalous / exposed finding, trace WHY it exists and classify:

- **ACCIDENTAL (default-config drift).** Example: N2 Redis `:6379` unauth. `bind 0.0.0.0` was set
  for convenience WITHOUT `requirepass`. Redis `protected-mode` (default-on since 3.2) ONLY guards
  you when you leave it unbound + no-pass; the moment someone sets `bind 0.0.0.0` without a password,
  the guard drops and the instance is world-open. No design intent → the only TRUE mistake →
  prioritise for fix.
- **BY DESIGN (intentional architecture).** Example: Ollama `:11434` LAN-exposed on N1/N2/N4. ZBit
  `config.yaml` explicitly enumerates `N1/N2/N4:11434` (LAN) + `N3:127.0.0.1` (localhost) as the Ollama
  fleet; `litellm_config.yaml` comments "secure LB fabric ... open nodes N2/N3 live". `OLLAMA_HOST=0.0.0.0`
  was set deliberately so the mesh reaches each node's models. NOT a bug — it's the inference fabric.
  Fix = add auth at the proxy (see `scripts/ollama_auth_proxy.py`), do NOT yank the LAN bind apart.
- **OS DEFAULT.** Example: WinRM-HTTP `:5985` open fleet-wide. Standard Windows management listener,
  not a custom exposure.

Persist a `genesis` table: finding / root_cause / by_design / evidence / confidence.
DECISIVE VALUE: this split separates the 1 real error (Redis) from 5 intended/OS states. Closing
Redis closes the only unforced mistake; everything else is accepted-by-design or OS-default.

## Beat 3 — HASH DRIFT CHECK (tamper-evidence + stability)
Re-probe EVERY hashed claim LIVE (never from memory), recompute SHA-256, compare to stored `claim_hash`.
Any mismatch = drift. Persist a `hash_drift_log` (ts, stable, drift, note).

- **FALSE-POSITIVE DRIFT IS A FEATURE, NOT A BUG.** A mismatch forces you to re-verify the live state
  rather than trust storage. This session a truncated `recv(200)` + wrong substring (`"model"` vs
  LiteLLM's `"id":`) mis-flagged a HEALTHY service as drift. Fixing the recv size (to 1024) + matching on
  `"id":` confirmed STABLE. LESSON: size your socket reads to capture the body, and match on field names
  actually present in the protocol's response shape.
- A clean `STABLE=N / DRIFT=0` = the ledger is tamper-evident and the fleet state has NOT changed since
  write. That is the deliverable for "hash drifts."

## BLOCKER FRAMING + "INVESTIGATE ALL POSSIBILITIES" (HIT 2026-07-11)
When an action is gated on a missing external input (node break-glass cred, API key, per-session secret),
do NOT dramatize ("dead in the water"). The user pushed back on a stalled posture by invoking
"investigate all possibilities" — that maps to:
1. Lead with what IS done/persisted (audit, ledger, omnimap complete regardless of the blocked fix).
2. Frame the blocker as a NARROW single gate, not a systemic failure.
3. Enumerate EVERY execution vector, classified:
   - VIABLE-BLOCKED (WinRM remote apply — needs cred)
   - VIABLE-SELF-RUN (operator runs the staged script locally — cleanest, secret never crosses wire)
   - DEAD (SSH/RDP closed, no mesh foot, no cached cred, no agent channel)
   - REJECTED (fixing via the vulnerable channel itself — e.g. writing Redis conf through unauth Redis
     is the RCE we're closing, and non-persistent across restart)
4. Persist the vector map (`remediations` table: vector/status/blocker).
5. Offer the open doors (self-run vs hand-cred). Never guess/re-loop a rejected per-node password.
A single credential gate is one door, not a dead end.

## Reusable scripts (shape to recreate under scripts/)
- `hash_drift_check.py`: for each claim, live re-probe → recompute SHA-256(`status‡claim‡evidence`) →
  diff vs stored row → print STABLE/DRIFT → append `hash_drift_log`. Socket reads must be >=1024 bytes
  to capture HTTP bodies; match LiteLLM responses on `"id":` not `"model"`.
- `analyze_remediations.py`: build the vector table (viable/self-run/dead/rejected) for a blocked fix.
