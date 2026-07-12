# fleet-council-audit — Audit Methodology (session-condensed knowledge bank)

Companion to SKILL.md. Carries the durable how-to for the ZQM audit class.
SKILL.md is over the 100K tool-write cap; this file holds the detail so future
agents can find it. When SKILL.md is condensed, add a one-line pointer here.

## TIERS THE USER ACTUALLY INVOKES (map their words to behavior)
- "investigate fully" / "audit"  -> council fan-out + lead sqlite ledger.
- "full scope investigation"      -> RECREATION tier (below). Highest rigor.
- "hash claims"                  -> ledger + tamper-evident SHA-256 claim chain +
                                     external claim_manifest.json + live re-verify.
- "use the councils"             -> parallel subagent fan-out across DOMAINS
                                     (net/exposure, auth/secrets, app/runtime);
                                     lead re-verifies every headline claim.
- "memory to sql vectorization"  -> ingest into ZQM-AI-Council\rag\ ONLY (trap below).
- "what did we learn?"           -> CONSOLIDATED BRIEF (headline + myths busted +
                                     lessons + deliverables + open), not a raw dump.

## RECREATION TIER (user's self-correction mechanism — do NOT skip)
After any audit, independently re-derive every finding from scratch and DIFF vs
the SQLite ledger. A prior claim ("Hermes_Gateway.vbs launches OpenClaw") was
corrected by a council subagent and only confirmed when the LEAD re-read the .vbs
body + schtasks. Rules:
- Lead re-derives headline claims with fresh commands; council subagents REPORT,
  the LEAD PROVES before anything enters the ledger.
- Net change = state drift signal. Flag it (N4 Ollama came UP between sessions;
  N2 Redis still +PONG across the whole session).
- If a subagent refutes a prior claim, treat the refutation as UNVERIFIED until the
  lead reproduces it live. Then RESTATE the finding (do not delete — preserve
  correction lineage).

## TAMPER-EVIDENT CLAIM CHAIN (the "hash claims" deliverable)
1. For each finding compute SHA-256(content) and chain prev->this so altering ANY
   finding breaks the root.
2. Write claim_hashes INSIDE the db + a claim_manifest.json OUTSIDE it
   (db_sha256, chain_root, all claim hashes, live verdicts, correction notes).
   External witness = proof the DB file itself is unaltered.
3. Re-walk the chain on demand to re-prove integrity.
Deliverable = ledger + chain + manifest. Chat summary alone is NOT the deliverable.

## COUNCIL FAN-OUT + LEAD-REVERIFY CONTRACT
- Fan-out is fine for breadth (parallel subagents per domain) BUT each leaf can
  429 / give false negatives / misread. Pass them the hard-won gotchas
  (netstat capture form, regex, redaction, read-only).
- LEAD must independently re-run the headline probes (listener census, Redis PING,
  service reachability) and reconcile vs the council's numbers BEFORE recording.
- Subagent self-reports are NOT facts until lead-reproduced.

## VECTORIZATION BLOCKER TRAP (memory-to-sql / "vectorization systems")
"SQL vectorization system" in this fleet = ZQM-AI-Council\rag\. Reality:
- RAGRetriever is IN-MEMORY only (plain Python lists; no SQLite/Chroma/FAISS sink).
  There is NO persistent vector store.
- Embedding backend is frequently DEAD: LocalAI default :8000 not listening; Ollama
  :11434 returns 404 on /api/embed (no embed model). LocalAIEmbeddings falls back
  to a 384-dim ZERO vector.
- DO NOT ingest when the backend is down — you would write meaningless zero-vectors
  = fabrication. Instead: build the pre-chunked corpus (DocumentLoader schema)
  under data/documents/, write a ready-to-run ingest script, and mark status
  NOT_VECTORIZED with the exact command to finish once the backend is live.
- Hermes_Gateway.vbs is MISLABELED: the Startup .vbs launches the HERMES gateway
  (OneDrive repo), while OpenClaw is launched by Scheduled Task \OpenClaw Gateway
  -> .openclaw\gateway.vbs -> gateway.cmd. Two distinct .vbs; do not conflate.

## AD-HOC VERIFICATION (when no test suite exists)
After any code write, create C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*.py,
run it against the changed behavior, then delete it. Report explicitly as ad-hoc,
NOT suite green. OS-safe tempfile path.

## NETSTAT / PARSING GOTCHAS (burned ~6 turns once — never again)
- subprocess powershell form `subprocess.run(['powershell','-Command',"cmd /c
  netstat...Select-String"])` SILENTLY swallows cmd.exe stdout -> 0 rows.
  RELIABLE: bare terminal
  powershell.exe -NoProfile -Command "cmd.exe /c 'netstat -ano -p TCP' | Select-String 'LISTENING'" > file 2>&1
  then parse the FILE in a second step.
- Parsing regex MUST be `TCP\s+([\d.]+):(\d+)\s+[\d.]+:\d+\s+LISTENING\s+(\d+)`
  — NOT `\S+` for the 2nd column (0.0.0.0:0 spacing breaks it).
- Redis / raw-protocol ports: use Python socket PING, NOT httpx/curl (they speak
  HTTP to a raw socket -> false timeout).

## CONSOLIDATED BRIEF shape ("what did we learn?")
1. Headline (the ONE sentence that matters).
2. Security posture (proven, tiers, RECREATION-verified claims).
3. Myths busted (things that looked bad but weren't — e.g. mislabel, false alarm).
4. Lessons that cost time (now saved so they won't recur).
5. Persistent deliverables (ledger path, manifest, corpus).
6. What's still open / honest unresolved.
7. Biggest takeaway.
