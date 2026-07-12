# Coined-verb SOP + swarm discipline (consolidated 2026-07-11)

The owner issues terse directives that map to STANDING SOPs. Most are established;
a few are COINED VERBS that need a defined framing + a FLAGGED ASSUMPTION before
acting (do not guess wrong on a coined verb — state the assumption, then proceed).

## Standing verb → SOP map (autonomous; lead re-verifies LIVE before reporting)
- `investigate fully` / `full scope investigation` → council + lead → SQLite;
  lead re-derives every headline claim from LIVE state (RECREATION tier) before
  reporting. Retract (don't delete) any superseded finding.
- `hash claims` → SQLite ledger + SHA-256 chained claim hashes + external
  `claim_manifest.json` witness; periodically RECOMPUTE from live state; flag drift
  as tamper-evidence. (Canonical pattern: references/claim-chain-hashing.md.)
- `use the councils` / `swarms of councils` → parallel subagent fan-out (≤3/batch
  via `delegate_task` `tasks` array; runs BACKGROUND, returns ONE combined message
  when all leaves finish — do NOT poll) + lead re-verifies every headline claim.
  Pre-seed each leaf with the hard-won gotchas (netstat capture = bare
  `powershell ... cmd /c 'netstat -ano -p TCP' | Select-String LISTENING` → file,
  parse `[\d.]+:\d+`; reachability = curl HTTP GET not bare `socket.recv()`;
  REDACT credentials; Windows git-bash paths; read-only unless told to apply).
- `memory to sql vectorization` → ingest `ZQM-AI-Council\rag\` (in-memory; if embed
  backend dead, REFUSE zero-vec fabrication — build a real persisted corpus +
  mark NOT_VECTORIZED).
- `genesis` → read-only ROOT-CAUSE dive (by-design vs accidental vs OS-default).
- `what did we learn?` → CONSOLIDATED BRIEF.
- `study patterns` → synthesize recurring motifs across findings/logs (config-drift,
  false-negative-probe, over-reliance, key-attachment-gap); record as pattern
  findings + persist durable lessons to memory.
- `diagnostics and improve systems stability` → read-only stability diagnostic
  (supervision gap, resource pressure, config drift, event-log scan) + STAGED fixes.
- `improve systems integrations` → chain the Ollama fleet into the LiteLLM + Open
  WebUI LB fabric; validate the fuller config against live nodes; fix blockers
  (master_key unset, keep_alive `-1` OOM, cold-load timeouts). (See
  references/fleet-integration-deploy.md.)
- `improve the garden` → COINED VERB → garden fleet audit + hardcoded-secret
  redaction. Framing + redaction SOP live in `zqm-fleet-management`
  (references/garden-secret-redaction.md). Never source garden/Node-4 creds to act.

## Coined verbs that ALWAYS need framing + flagged assumption
`github community review` / `omnimap` / `5d mapping` (and any new noun-verb the
owner coins). On first encounter: state the assumed meaning, flag it as an
assumption, offer the safe scoped option, then proceed if no objection.
`improve the garden` was resolved this session as "apply audit/redaction rigor to
the 12-node Synology/Noon SSH fleet" after a read-only probe confirmed 'garden'
is real infrastructure (not a metaphor).

## Clarify-timeout discipline (standing, reinforced 2026-07-11)
When a `clarify` prompt times out unanswered, do NOT stall and do NOT re-ask.
Proceed with the SAFEST SCOPED option: stage the change (dry-run / `.redacted`
siblings / `-WhatIf`), touch nothing live, report what was staged + the remaining
open choice. The owner prefers autonomous progress with a reversible artifact over
a blocked wait. This is distinct from the BLOCKED/denied gate: a hard user DENY
(approval gate "BLOCKED") means STOP + surface + never retry; a clarify *timeout*
means proceed safely.

## Swarm-of-councils recipe
1. Fan out ≤3 parallel `delegate_task` leaves, each a bounded READ-ONLY workstream
   (e.g. remediation-design / live-validation / patch-diffs), pre-loaded with
   gotchas + the ledger context so they don't repeat traps.
2. Leaves return consolidated reports; treat as SELF-REPORTS, not verified facts.
3. LEAD independently re-verifies every headline claim LIVE (the non-negotiable
   gate) before any of it touches the ledger or the running system.
4. Record validated findings; stage (don't apply) any remediation; re-hash.

## Retract / reframe (honesty)
- A finding superseded by a corrected diagnosis → UPDATE severity='retracted' +
  append the correction (don't silently delete). Seen: F45 "N4 cold" →
  "zbit-heavy cold-load timeout" (log forensics reframe).
- Log forensics reframes misdiagnoses: error-bucket counting + normalized-signature
  `Counter` + live cross-check. (Canonical: references/fleet-log-forensics.md.)
- False-negative probe trap recurred 3× this session (subprocess netstat swallow;
  bare `recv()` timeout; short-timeout TCP ping) — always re-verify a negative with
  the authoritative method before recording it.
- **A COUNCIL can refute the LEAD's OWN prior finding — and be RIGHT.** In the
  2026-07-11 swarm, Council-2 asserted "N1 does NOT require a key", contradicting
  the lead's own F54/F57 ("N1 requires a key / 401 on N1"). The lead re-probed live
  (N1 no-key / sk-na / wrong-key all → HTTP 200) and the COUNCIL WAS CORRECT: the
  lead's earlier `000` was a cold-load timeout misread as "rejected". The lead
  marked F54/F57 CORRECTED and recorded the refutation + re-proof. Lesson: never
  accept a refutation on a subagent's word (re-verify live), but also never defend a
  prior claim reflexively — the swarm's highest value is catching the lead's OWN
  errors. Distinguish from "reframe your own past findings" (lead self-corrects via
  log forensics): this is a PEER (council) catching a lead error, which the lead
  must verify and then adopt, not dismiss.
