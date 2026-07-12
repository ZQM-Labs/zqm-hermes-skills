# Blind-Spot Enumeration — classify + quantify (methodology + template)

Use this when the user asks for a "full blind spot enumeration", "verify claims and
quantify", or "review what we tried / full enumeration of attempted solutions". The
deliverable is NOT a flat list — it is a CLASSIFIED, QUANTIFIED enumeration.

## Deliverable schema
1. **Classify** every item into orthogonal buckets. For a fleet/agent audit the proven
   split is:
   - Tooling / Observability blind spots
   - Fleet / System-State blind spots
   - Remediation-Pipeline blind spots (drafts, gated items, dead vectors)
   - Agent Self-Discipline blind spots (its own mis-steps)
2. **Per item**: status (PROVEN / OPEN / UNVERIFIED / GATED) + the LIVE proof source
   (exact command + observed value). No status without a probe this turn.
3. **Quantify**: per-class counts + overall total. When a tool under-reported, compute
   the undercount multiplier = ground_truth_count / tool_reported_count and report both.
4. **Top-3 leverage**: the 3 highest-leverage items to close, each with its exact
   closure path and the gate that blocks it.
5. **Remediation-vector ledger** (when reviewing "what we tried"): enumerate EVERY
   vector and class it (Applied+Verified / Gated-Blocked / Drafted-Open / Rejected-Dead)
   with a count per class. Do NOT report only successes. A "DEAD" vector map prevents
   wasted re-attempts.

## Quantification technique — prove a tooling/observability blind spot empirically
- **Ground truth**: query the authoritative store directly, NOT the tool's capped
  browse/discovery. (e.g. Hermes `state.db`: `SELECT source,COUNT(*) FROM sessions`.)
- **Undercount multiplier** = ground_truth / tool_reported. Report both numbers
  (proven 2026-07-12: tool reported 12 then 16; ground truth 71 → 5.9x / 4.4x).
- **Prove burying/skew via corpus composition** (the mechanism, not "broken index"):
  `SELECT source, COUNT(*) FROM messages GROUP BY source` + avg msgs/session per source.
  A cron/automation-heavy corpus (98% of message volume) out-ranks interactive content
  under per-session BM25, so interactive chats are buried even though the FTS index is
  complete. Pair with a live tool call showing the cap (browse returned 3, all cron;
  discovery capped at 3 results/call).

## Self-correction pitfall (2026-07-12)
Re-verify the EXACT numbers you embed in a deliverable immediately before finalizing it.
A report drafted mid-session ("ZBit+LiteLLM DOWN, 000") was disproven by a final
re-probe ("404 / 200 / 200 — manually up"). Live state moves; the numbers in your doc
must match a probe run in the same breath as the write.

## Condensed proven example (ZQM fleet, 2026-07-12)
15 classified blind spots: 3 tooling (session_search hides 95.7% of chats; monitor
invisible to its own search; consolidation collapses history) · 5 fleet-state (1 CRITICAL:
no autostart task; 4 open/unverified: N2 dark, N3 ambiguous, N4 Ollama LAN-open root
cause unknown, inference SPOF) · 4 remediation-pipeline (16 open questions; 4 gated
reliability items; 8/12 dead/blocked vectors; 13 phantom drafted scripts) · 3 self-
discipline. Top-3: execute apply_stability.ps1 (UAC); get N4 local-admin cred; deliver
operator self-run checklist for N2 Redis. No agent credential-guessing.
