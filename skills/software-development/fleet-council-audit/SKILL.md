---
name: fleet-council-audit
description: Parallel multi-agent council deep-audit of a Windows host or LAN fleet with lead live re-verify and tamper-evident SQLite hash-chain. Triggers investigate fully / audit / council sweep / fix broken automations.
tags: []
---

# Fleet Council Audit

## What this skill is for
A council is N parallel subagents (delegate_task, role=leaf) that each own one slice
of a host/fleet audit (hardware, network/topology, software, running bots), report
back, and the LEAD re-verifies every headline number against LIVE output before
writing the final report. The point of the council is breadth + speed, NOT to trust
the subagents - the lead must re-probe the claims that matter.

Use it when the user says "investigate fully", "audit this box/fleet", "council
sweep", "bots on this node", or "fix the broken automations". It wraps
local-service-verification + windows-powershell-from-bash + audit-sqlite-sink.

## One-line trigger keywords
"investigate fully" - "audit" - "council sweep" - "bots on this node" -
"fix the broken automations" - "what's running on this box" - "profile this host"

## Council shape (the verb)
1. Fan out N leaf agents, each with a self-contained context block (no shared memory;
   pass every path, cred, and assumption explicitly).
2. Each leaf returns VERIFIABLE findings with live evidence (ports, PIDs, hashes),
   not prose summaries.
3. LEAD re-derives the headline claims LIVE (terminal probes, not leaf output) and
   labels each PROVEN / NOT PROVEN / FALSE before reporting.
4. Persist to SQLite (audit-sqlite-sink) so future "hash claims" re-runs can
   recompute and detect drift.

## "investigate fully" = council + lead re-verify + persist
This three-part verb is the user's standing directive for a thorough audit:
- council = parallel slices
- lead re-verify = the LEAD must re-probe headline claims LIVE, not trust leaf text
- persist = write findings to SQLite with PROVEN/NOT PROVEN/FALSE labels

## "hash claims" = tamper-evident, re-computable ledger
Persist each headline claim as a row carrying a SHA-256 of claim + status.
Re-run recomputes every hash from LIVE state and flags DRIFT (state changed) or
recounts STABLE. For a full chain, link each row's prev_hash to the prior
claim_hash so the ledger is a tamper-evident sequence (single chain_root).

### WAL CHECKPOINT PITFALL (verified 2026-07-11)
If the audit DB uses WAL journaling (sqlite3's default in many setups), hashing the
.db file while a -wal/-shm exists gives an UNSTABLE SHA-256 - the bytes on disk
don't include uncheckpointed commits, so the manifest hash never matches a later
re-hash. This silently breaks tamper-evidence.
FIX: before computing the db hash, run PRAGMA wal_checkpoint(TRUNCATE) then
con.close() (folds the WAL into the main file), THEN
hashlib.sha256(open(DB,'rb').read()). Also confirm no -wal/-shm linger after.
(The fleet_swarm.db hash-chain reconciliation hit exactly this - DB re-hash ==
manifest: False until the checkpoint was added. Chain-linkage check: row N's
prev_hash must equal row N-1's claim_hash; a single chain_root across all rows =
intact.)

## "genesis" = root-cause WHY, not just what
When the user says "genesis", they want the WHY of each state: by-design vs
accidental vs OS-default. Enumerate each exposure/surprising-state with its
root-cause class before recommending a fix. (See local-service-verification's
"Exposed on purpose?" split for BY-DESIGN vs UNINTENDED-DEFAULT vs OS-DEFAULT
vocabulary - do NOT overstate "mistake" without evidence the user touched it.)

## Hash-Claim Ledger (drift-detectable findings)
For an "investigate fully" + "hash claims" directive, persist each headline claim
as a row with a SHA-256 of claim + status, recomputed LIVE every re-run:
- Genesis table: root_cause (by-design vs accidental vs os-default) + by_design flag.
- hash_drift_log: each run stores STABLE= / DRIFT= count. A drift = a live re-probe
  no longer matches the stored hash => state changed (or your checker has a bug).
- Pitfall: early drift-check runs showed FALSE drift because (a) socket.recv(200)
  truncated a JSON line so the matcher missed, and (b) "model" in text matched the
  wrong substring. Fix: recv a larger buffer (1024+) and match the exact token
  (e.g. "id":). Re-run until STABLE across consecutive runs before trusting.

## Post-audit port-mesh / collision check
After the slices complete, the LEAD runs one consolidated check: every listening
port across the fleet, mapped to PID + owning service, to catch collisions (two
nodes claiming the same LAN port) and unexpected exposures. This is where
post-restart gaps surface (a service that "should" be up but isn't after a reboot).

## Broken Startup automations
A common fleet-audit finding: a Startup .lnk/.vbs that points at a deleted or
renamed path so the automation silently never runs. Repair = repoint the link's
target to the real current code path. Verify the link actually launches by checking
the process appears post-login / post-reboot.

## Persistence / SQLite sink
Findings go to a SQLite ledger (see audit-sqlite-sink): tables for run_meta,
findings, claim_hashes (chain), hash_drift_log, patterns, reliability, meta. Label
every finding PROVEN / NOT PROVEN / FALSE. Do NOT store secrets (API keys, tokens) -
store only that auth is present/absent.
- If TWO audit DBs exist for the same fleet (e.g. a fragment fleet_endpoint_audit.db
  and a complete fleet_swarm.db), do NOT let them drift. Designate ONE canonical
  (prefer the more complete + chain-intact one) and record the decision in meta.
  The lead must re-verify headline claims live before promoting one over the other
  (approval gate if it flips which DB future sessions trust).

## Reusable assets
- local-service-verification: three-layer process/net/security probe + C2 disproof.
- windows-powershell-from-bash: run PS/CIM from the MSYS terminal without bash
  eating $_ / $var (single-quote inline -Command, or write a .ps1 and -File).
- audit-sqlite-sink: the persistence schema + tamper-evident hash-chain pattern.
- hermes-cron-ops: schedule the drift-watch as a recurring cron (read-only probes)
  that flags NODE-down / claim-hash DRIFT / anomalous sessions as URGENT.

## Two-door reporting habit
When a verification surfaces a decision that changes trust or provenance (canonical
DB swap, promoting a stray DB, flipping which credential is valid), surface TWO
doors (options A/B/C) and let the user pick - do not auto-execute the trust-changing
action. This is the standing approval-gate rule.
