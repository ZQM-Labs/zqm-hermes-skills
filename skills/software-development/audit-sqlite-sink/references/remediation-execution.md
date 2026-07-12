# Remediation Execution — tiers, clarify-timeout, secret redaction, LiteLLM 401

Patterns hardened during the 2026-07-11 ZQM fleet audit. Use when the user moves
from "audit" to "fix": says `tier 1`, `apply`, `improve the garden`, `remediate`,
or picks from an open-queue.

## 1. TIERED REMEDIATION MODEL (scope before you touch anything)
Sort every staged fix into 3 tiers and only auto-apply Tier 1:

- **Tier 1 — LOCAL, REVERSIBLE, NO CREDS, NO SERVICE RESTART.**
  Pure file/code edits (secret redaction, genesis patches, config text fixes).
  Safe to `--apply` once the user scopes it. Back up originals first
  (`shutil.copy2` to a timestamped `backup_YYYYMMDD_HHMMSS` dir) so it's
  fully reversible. Verify with `py_compile` / re-read, not just "print OK".
- **Tier 2 — LOCAL BUT DISRUPTIVE (restarts a running service).**
  Proxy/Ollama restart, Scheduled-Task changes, retry-config swap. Causes brief
  outage. Apply ONLY on explicit `tier 2` / `apply` say-so. Fold related fixes
  (e.g. integration Q23 + route Q24 + stability Q20–22) into ONE restart, not N.
- **Tier 3 — NEEDS CROSS-NODE CREDS or RISK OF LOCKOUT.**
  Editing another box (N2 Redis lock), disabling sshd password-auth (lockout if
  your pubkey isn't in authorized_keys first), firewall scope-downs that could
  cut your own access. GATED: never source the credential unilaterally; ask,
  or require the user to provide a peer shell / break-glass.

Rule of thumb: **once the user names a tier (`tier 1`), EXECUTE it without
re-confirming.** Staged ≠ applied; applying the scoped tier is the expected
completion, not a new decision point.

## 2. CLARIFY-TIMEOUT → SAFE DEFAULT (user approval-gate signal)
The user's standing gate: if a bundled command is denied, STOP and re-offer a
scoped read-only one; never retry/rephrase the same call. This extends to
clarify/approval PROMPTS: if a clarify times out with no answer, DO NOT loop or
escalate — pick the SAFE, LOCAL, REVERSIBLE default and proceed without
re-asking. Stage (don't apply) anything that touches operational tooling or
needs creds. This session: `improve the garden` clarify timed out → chose
safe-local secret-redaction (staged + backed up, no garden SSH); the user then
implicitly accepted (unbanned the re-hash, said `tier 1`).

## 3. PLAINTEXT-CREDENTIAL REDACTION (the "garden" finding class)
When auditing source/tooling, grep for secrets BEFORE judging security:
  search_files(pattern='PASS|password|secret|token|API_KEY|api_key\s*=\s*["\'][^"\']+["\']')
Real exposure found 2026-07-11: `deploy-garden-keys.py` + 8 sibling scripts
held two shared plaintext passwords sprayed across the fleet, including an
active password-SPRAY list against Node-4. Worse than an unauthenticated
service — real reusable creds at rest.

Redaction recipe (reversible, no service disruption):
1. Enumerate every literal secret + the env var it maps to (one env var per
   distinct secret; cover ALL spray variants, not just the "main" one).
2. Replace `password="X"` / `SSH_PASS = "X"` / bare `"X"` in lists with
   `os.environ["ENV_VAR"]`. Ensure `import os` present.
3. DRY-RUN first → write `.redacted` siblings, assert `literal leaks remaining: 0`.
4. BACK UP originals (timestamped dir), THEN `--apply` overwrite.
5. Report the env vars the user must set once (user env / secrets vault) for the
   scripts to keep working. Scripts then fail SAFE (os.environ KeyError) — no
   secret exposure even if they break.
Never print the recovered secret back into chat/output.

## 4. LiteLLM 401 "missing/invalid Bearer" DIAGNOSTIC
Symptom in litellm.log: `openai.AuthenticationError: 401 - {'error':
'unauthorized: missing/invalid Bea...'}`. Do NOT assume "wrong key" or
"upstream rejects our key". Two distinct failure modes:

- **Key NOT ATTACHED on some routes.** LiteLLM forwarded a request upstream
  WITHOUT the `api_key`, and a key-gated upstream (e.g. N1 Ollama with
  `OLLAMA_API_KEY` set) drops it → LiteLLM wraps the drop as 401. Test: hit
  each node WITH and WITHOUT the configured key.
    - N2/N4: accept both no-key and `sk-na` (200).
    - N1: REQUIRES a key; `sk-na` passes (200), no-key drops (000/connection-reset).
  Fix = ensure EVERY model_list entry carries `api_key` (the fuller Desktop
  config does; the minimal running config's N1 block was commented out).
- **Cold-load timeout mislabeled.** `zbit-heavy` → HTTP 000 isn't a 401 — it's
  the target model not kept warm (keep_alive drift / first-request load >
  proxy timeout). Fix = keep_alive TTL + health-check warmup, not auth changes.

Disambiguate by probing each upstream directly (curl HTTP GET/POST, not
socket.recv) rather than reading the error string alone.
