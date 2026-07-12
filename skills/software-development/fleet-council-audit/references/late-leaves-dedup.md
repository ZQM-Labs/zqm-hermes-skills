# Council orchestration: late-arriving leaves + re-verify discipline
## Late-arriving async leaves
A `delegate_task` background batch can return AFTER the lead has moved on (one leaf took 840s on a
firewall-query quirk). When results re-enter late:
1. RE-READ the blackboard first — sibling leaves modified it; your last read is stale (the skill warns
   "subagent modified files the parent previously read — re-read before editing").
2. If you ran a SYNCHRONOUS FALLBACK for a missing leaf, the async leaf may carry RICHER data (it caught
   `LocalAddress=Any` and `:18789 = FALSE` the fallback missed). REDACT the duplicate fallback, keep the
   better async version, merge deltas into the convergence summary.
3. Dedup: never let two `LEAF A` blocks coexist. Mark the fallback REDACTED with a one-line pointer.

## Cold probe != HANG (re-verify gate)
A single `POST /api/generate` timeout is NOT proof of a hang. Distinguish:
- SLOW COLD-LOAD: first request times out (model not in VRAM); a WARM retry returns 200 in ~13s. NOT a fault.
- PERMANENT HANG: retries at 30/60/90s all return HTTP 000 (curl exit 28). REAL fault -> ollama-recovery.
False positive caught in practice: lead flagged "N4 HANG CONFIRMED" from one cold probe; leaf retries proved
N4 healthy — the actual hard hang was Node-2. Always retry (warm + escalating timeouts) before tagging HANG.

## Honest claim reconciliation
Flag prior topology claims FALSE when live evidence contradicts them, and surface prominently:
- "OpenClaw gateway :18789 loopback" -> FALSE (no listener on 18789; scheduled task exists but not bound).
- "Ollama LAN-exposed" -> TRUE but mislabeled: firewall rule `LocalAddress=Any` (all-interfaces), not LAN-scoped.
- "Hosts Ollama :11434" -> TRUE as a port/process, FALSE as a Windows service (runs as a user process).
The user rewards catching these; they are first-class audit findings, not footnotes.
