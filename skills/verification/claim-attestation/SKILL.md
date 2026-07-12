---
name: claim-attestation
description: CLASS-LEVEL skill — build, hash-anchor, and serve LIVE claim attestations for the ZQM fleet (and any state that must be proven). Covers the full pattern the user keeps requesting under many phrasings ("verify claims and quantify", "full blind spot enumeration", "api driven attestation", "full api driven situational awareness"). Use when asked to (a) verify/investigate claims with PROVEN/NOT PROVEN/FALSE labels, (b) enumerate a blind spot, (c) expose verified state over HTTP, or (d) produce a tamper-evident hash chain over findings. Read-only probes only; never guess credentials.
---

# claim-attestation

The user demands claims be PROVEN with LIVE evidence, then made queryable. The
proven, working implementation from 2026-07-12 lives at:
  - C:\Users\zqmco\swarm\claims_core.py   (probe + claim + hash-chain core)
  - C:\Users\zqmco\swarm\api_server.py     (stdlib HTTP attestation service)
  - C:\Users\zqmco\swarm\verify_claims.py   (offline manifest writer, same core)
  - C:\Users\zqmco\warm\repair_claim_chain.py (repairs a broken audit-DB chain)
  - C:\Users\zqmco\swarm\fleet_endpoint_review\fleet_endpoint_audit.db (ledger)
Reuse these; do NOT reinvent the pattern.

## THE PATTERN (4 steps)
1. GATHER LIVE PROBES — read-only: curl http_code, redis-cli PING, powershell
   Get-ScheduledTask/Get-Service, sqlite3 read on state.db + audit DB.
2. DERIVE CLAIMS — for each claim compute (id, claim, status, evidence) where
   status ∈ PROVEN / NOT PROVEN / PARTIAL / FALSE, evidence = the live probe value.
3. HASH-CHAIN — content = "id|claim|status|evidence|ts"; chain[i] =
   sha256(chain[i-1] || content[i]); root = chain[-1]. Genesis = b"GENESIS".
4. SERVE — stdlib ThreadingHTTPServer (NO fastapi/uvicorn dep; guaranteed to run).
   Endpoints: /attest, /attest/summary, /attest/claim/<ID>, /attest/chain,
   /attest/probes, /audit/chain, /sitrep, /nodes.

## ARCHITECTURE RULES (learned the hard way)
- SEPARATE compute from serving: claims_core.build_attestation() / build_sitrep()
  do pure compute (no file IO). api_server imports them. verify_claims.py wraps
  the same core → the offline manifest and the API CANNOT diverge.
- BUILD ONCE PER REQUEST in the handler (probe-driven builds take ~15s; calling
  build_attestation() 3x per request causes client timeouts).
- sitrep = fleet topology (static NODES list + live reachability) + audit ledger
  (open_questions, reliability, remediations, chain integrity) + Hermes session
  store counts + monitoring health + ranked open gaps. All read-only.
- NARRATIVE BRIEFINGS VIA ollama-bridge: the cleanest way to turn /sitrep into a
  plain-English briefing is `mcp_ollama_bridge_generate` (model qwen3:8b on N1),
  NOT raw curl. ollama-bridge is the MCP front-end to the same N1 Ollama that
  /nodes shows as OPEN (G-A) — it lists 3 models and generated at ~13-17 tok/s.
  Feed it a compact JSON brief (nodes/audit_open/chain_valid/gaps+gate) and ask for
  a <=110-word SRE briefing. Persist the result to sitrep_narrative.md. Verified
  2026-07-12. (Raw curl to :11434 also works but is clumsier to script.)
- GATE-MAP DISCIPLINE: when the user says "explore possibilities with open gates"
  or "investigate fully", produce a GATE INVENTORY (open vs closed) + POSSIBILITY
  MATRIX, not a flat todo. Classify each gate: OPEN (reachable w/o a cred I lack,
  e.g. N1 Ollama G-A, N4 Ollama G-B-exposure, local host G-D), CLOSED (blocked on
  a cred/consent I do NOT have — N2 break-glass, N3, N4 root-cause, B4/UAC). EXERCISE
  the open gates live (run a real probe/generation) and ATTEST the closed ones as
  gated — never guess creds. After an MCP reload, VERIFY each reconnected server
  with a real capability probe, not its "connected" status: zqm-local reported
  connected but its backend refused (WinError 10061); zqm-indexer connected but
  every tool errored with a call_tool() dispatch bug. See references/gate-map.md.

## PITFALLS (each bit us this session — embed, don't rediscover)
- PROCESS TOOL IS UNRELIABLE FOR LONG-LIVED SERVERS — but NOT because the OS
  process survives. CORRECTED (2026-07-12): `process kill <session_id>` DID
  terminate its OS process (taskkill SUCCESS, port freed). The earlier claim
  "the OS process survived across kills" was a MISdiagnosis — each restart spawned
  a NEW PID and only the NEWEST survived (a port can't double-bind, so at most ONE
  server ever ran at a time). What actually re-fired the watch pattern was the
  session record's buffered startup line ("...attestation API on..."), even though
  the OS process was already dead. In this session EIGHT records re-fired:
  proc_1887af582829, proc_6e3f73428cdf, proc_43b9bea051, proc_86e548808ce6,
  proc_1d4736834424, proc_9cd10e3bd50a, proc_d0997b73a17a (dead twins) and
  proc_848bbc1484d2 (the LIVE session re-firing its OWN buffered line). A watch
  re-fire does NOT distinguish live-from-dead — confirm with netstat.
  → ANCHOR server lifecycle on `netstat -ano | grep :<port>` + Get-CimInstance
  (real cmdline) + a live curl probe. NEVER trust session_id/PID labels or a
  watch-pattern match alone. To stop: `taskkill /PID <netstat-PID> /F`.
  Authoritative procedure: hash-claims-verification → references/background-process-lifecycle.md.
- CURL 6-DIGIT DOUBLING TRAP: `curl -w "%{http_code}"` with MSYS `|| echo 000`
  fallback fires on success → "200000"/"000000". Trim to out[:3] always.
- POWERSHELL NESTED QUOTES IN sh(): Python raw string r'...\'X\'...' yields literal
  backslashes that break PowerShell. Use r"outer \"inner 'X'\"..." (double-quote the
  Python raw string, single quotes for the PS string). Test the exact command
  standalone before baking into a probe.
- STALE __pycache__ can shadow edits to imported modules. Clear
  <dir>/__pycache__ before restarting the server after editing the core.
- TUPLE UNPACK: NODES port entries are 3-tuples (name,port,note) — unpack
  `for _name,p,note in ports`, not `for p,note`.
- IMPORT EVERY SYMBOL USED: api_server must `from claims_core import
  build_attestation, build_sitrep` — a missing import surfaces only at request time.

## VERIFICATION DISCIPLINE (user's standing rule)
- Label every claim PROVEN/NOT PROVEN/FALSE with the LIVE probe that proves it.
  Real numbers only; never fabricate or recall.
- "verify claims" = RECREATION tier: re-derive from source of truth (state.db,
  live curl), not from memory or prior output.
- When a live probe contradicts an earlier statement (e.g. stack was "up" now
  "down"), CORRECT the claim text and report the correction. Do not paper over.
- GATED items (UAC, N2/N4 creds) stay OPEN; report the gate, never guess creds.

## SELF-CORRECTION PROTOCOL
If a watch notification or a "killed" report conflicts with a live curl, trust the
live curl + netstat. Kill by real OS PID, restart, re-verify. Report the zombie
session as dismissed-with-evidence rather than acting on it.

## POINTERS
- see references/audit_chain_repair.md for the broken-chain diagnosis + fix.
- see references/working_files.md for the exact endpoint map + probe inventory.
