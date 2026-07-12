# Council verbs, tamper-evident hash chain, and staging rules

Condensed operating contract for the ZQM fleet-council audit pattern. Companion
to SKILL.md. Loaded 2026-07-11 from a full-scope RECREATION + "swarms of
councils" + "hash claims" session.

## User verb → action map (drive the right scope, don't under/over-shoot)
- "use the councils" / "investigate fully" (fresh system) → parallel council
  fan-out (<=3 leaves) on distinct read-only domains, each pre-seeded with the
  netstat/regex/redaction/loopback-vantage gotchas. Lead re-verifies headline
  claims LIVE before recording.
- "investigate fully" (ALREADY-audited system) → LEAD-ONLY depth/closure pass.
  Re-derive each still-OPEN open_question from live state (sshd -G to close a
  pw-auth question; FW block>allow precedence to close an external-block
  question). Do NOT re-fan out (breadth is mapped; fan-out risks leaf 429 + re-covering
  ground). RECRATION re-derive still applies to every claim.
- "swarms of councils" → MULTIPLE parallel council batches on distinct
  DESIGN/VALIDATE workstreams (one designs remediation A+B, one live-validates a
  config, one drafts code patches). Give each leaf a bounded, READ-ONLY,
  self-contained task (design + validate, NOT live mutation) to dodge the
  leaf-429/silent-fail trap. delegate_task tasks array, max 3 concurrent. Lead
  re-verifies each council's headline claims LIVE on return.
- "hash claims" → see Hash chain below.
- "A+B" / "log + draft" → REMEDIATION STAGING RULE (below).
- "improve systems integrations" → validate + stage fleet fabric
  (LiteLLM<->Ollama<->Open WebUI). This session: a complete 69-route Desktop
  config (Desktop\ollama-fleet\litellm_config.yaml) sat UNUSED while the running
  proxy used a minimal 3-alias config. Fuller config had 2 real blockers: unset
  LITELLM_MASTER_KEY (proxy won't start) + 53 keep_alive: '-1' infinite-VRAM
  pins (violates ZBit "NEVER -1" policy). Fix = generate from fuller config, TTL
  keep_alive, inject key, loopback-only, merge router retries. Pairs with
  ollama-fleet-lb.
- "study patterns" / "diagnostics and learn more" → synthesize recurring MOTIFS
  + fresh pulse + log FORENSICS (not re-state). Log dive this session REFUTED an
  earlier F45 ("N4 cold") -> real cause was zbit-heavy COLD-LOAD TIMEOUT (target
  model on N2 not kept warm). Recurring "401 missing/invalid Bearer" = KEY-ATTACHMENT
  gap (request forwarded upstream without api_key; key-gated N1 drops it), NOT a
  wrong key. Output: per-node capability map (embed/vision/reason counts),
  error-cadence buckets, motif-prevalence.

## Tamper-evident SHA-256 claim chain ("hash claims")
1. Persist findings to SQLite (audit-sqlite-sink schema: findings(fid,title,
   severity,status,evidence) + open_questions + swarm_log + claim_hashes).
2. Chain: chain_root = SHA-256(prev_hash + fid + title + severity + status +
   evidence) walked head->tail over EVERY finding (prev starts as db_sha256+gen+
   all fids). Store per-claim hash + prev_hash + chain_root + generated in
   claim_hashes table.
3. Write EXTERNAL witness claim_manifest.json (OUTSIDE the DB) with db_sha256,
   chain_root, claim_count, live_recreation_verdict, open_questions. DB edits
   can't silently rewrite the witness.
4. RECREATION re-hash: periodically recompute the chain from LIVE state and flag
   any drift as tamper-evidence. RE-VERIFY each PROVEN claim by re-probe:
   raw-TCP PING for Redis, sshd -G for sshd, curl GET for HTTP.
5. Anti-false-negative: this session's auto re-verify threw 2 FALSE FAILs — wrong
   test endpoint (405 not 401) and wrong netstat regex (:::11434 missed
   0.0.0.0:11434). FIX THE TEST, never record a false contradiction. Final
   verdict: 9/9 claims PASS, 0 contradicted.

## Remediation staging rule (standing)
"A+B" / "log + draft" = LOG the item to open_questions AND DRAFT the patch / exact
commands — but DO NOT apply system changes until the user says "apply" / "deploy".
Every staged script defaults to --dry-run; mutates only under --apply. Holds
across security (sshd/Redis/WinRM), genesis-hygiene (Ed25519/scan-scope/
path-relativize), stability (supervision/ollama-bind/retry), integration (deploy
69-route config).

## Durable loopback-vantage + probe traps (cross-ref windows-host-audit)
- FW block>allow precedence resolves an external-block question WITHOUT a peer
  probe (deterministic). Report as "resolved by rule-precedence analysis."
- Self-connect to own LAN IP returns 200 even with a Block rule (loopback-exempt)
  -> NOT proof the block failed. Probe from a DIFFERENT host to prove a LAN block.
- socket.recv() on a fresh connect times out even when connect succeeded -> probe
  with HTTP GET (curl), not bare recv.
- netstat capture = bare powershell ... cmd /c 'netstat -ano -p TCP' | Select-String
  LISTENING -> Windows temp file, then parse [\d.]+:\d+ (NOT \S+).
