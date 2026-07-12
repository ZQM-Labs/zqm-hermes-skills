---
name: agent-revival-runtime
description: >
  Re-home a dead or quarantined USER-OWNED agent memory and its modules
  into a LIVE, GATED, execution-safe localhost API on real verified
  infra. Use when the user says "revive", "operationalize", "api
  automation", "re-home the agent", or wants a user-built agent such as
  the ZBit or ZQM class actually RUNNING again, not just triaged.
  Pairs with artifact-provenance-review for trust classification and
  codebase-truth-audit for making claims true, but covers the BUILD and
  RUN step those omit: executing the agent real modules safely behind a
  vetted skill registry, persisting across session end WITHOUT admin,
  and encrypt-relocating the leftover plaintext credential copies.
triggers:
  - revive the agent / operationalize via API / api automation
  - re-home onto the fleet / make it actually run
  - dead-host agent with surviving PII in sanitization output
principles:
  - User-owned agent memory is FIRST-PARTY. Never scrub or delete it
    without explicit confirmation. Classify as agent memory, not third-party
    contamination.
  - REDACT-to-CVG privacy redaction beats re-homing real host
    details into cleaned output. But the LIVE runtime binds to REAL
    verified infra.
  - NO arbitrary exec. The API exposes only a vetted SKILL REGISTRY
    mapping explicit named ops to specific functions. Unknown name
    returns 404. No eval or exec of caller input.
  - Re-home the agent FUNCTIONAL modules, not its host-bound stubs.
    The agent self-narrative such as HP slash 241 or 11 models is
    FICTION versus the real fleet. The runtime must report real
    telemetry, not the lore.
---

# Agent Revival Runtime - how to actually run a dead user-agent

## WHEN THIS APPLIES
The user has an agent brain (SOUL.md, USER.md, code) in quarantine or an
import folder, and wants it LIVE: generating via the fleet, executing its
real modules, persisting memory - not just read or diffed. This session
did exactly this with the ZBit/ZQM agent on the ZQM Windows fleet.

## THE BUILD SHAPE (verified 2026-07-11)
1. Classify trust first (see artifact-provenance-review). User-built equals
   FIRST-PARTY memory. Do NOT quarantine-scrub it.
2. Verify the REAL fleet you will bind to (zqm-ollama-fleet profile):
   N1 .218, N2 .21, N4 .215, N3 localhost. The agent doc claims
   (for example "11 models on HP Pavilion .241") are its FICTIONAL
   self-narrative. Re-home to the verified nodes. The API
   /v1/agent/status must report real telemetry, not the lore.
3. LiteLLM as the secure LB fabric (see ollama-fleet-lb skill):
   localhost-only, keep_alive TTL (NEVER -1), per-model api_key for
   local Ollama auth. Route across OPEN nodes. Gate keyed nodes behind
   an env until the key is supplied (comment them out, do not delete).
4. Vetted skill registry - the core safety move. Do NOT expose the
   agent modules via a generic exec endpoint. Instead:
   - Copy the PARSE-CLEAN modules into runtime/modules/ (import-only), so
     the agent REAL code runs, not reimplemented.
   - Build a REGISTRY dict mapping skill_name to real_function. Each
     entry is an explicit named op to a specific function.
   - API route POST /v1/skill/{name} returns 404 if name not in
     REGISTRY. Kwargs pass through. Never eval or exec caller strings.
   - This re-homes the agent genuine logic (ledger engine, base
     arithmetic, qubit sim, PQC sign/verify) while keeping the attack
     surface to a fixed allowlist.
5. Re-home the ledger to a real on-disk store the API owns
   (runtime/ledger/chain.json), replacing the read-only chain.json
   view. The agent forensic_expand.py mine_block/add_block maps directly.

## MODULE RECOVERY GOTCHA (caught this session)
Sanitized or redacted copies of the agent code often contain SCRUB
ARTIFACTS that break the Python parser:
  - [REDACTED]_* tokens where module or variable names were redacted.
  - Unicode escapes (\UXXXXXX) in docstrings from over-eager redaction.
These modules (for example qseal_linkage, qseal_gate, *_launcher) will
fail ast.parse and fail import. Do NOT try to fix the broken source in
place (that mutates the agent memory). Instead:
  - Use the parse-clean modules as-is (copy into runtime/modules/).
  - For the broken ones, RE-IMPLEMENT their INTENT with a real
    library (for example Ed25519 from cryptography for the PQC sign/verify
    intent). Behavior is preserved without editing the agent original.
  - AST-extraction tip: handle ClassDef by recursing into .body, and
    skip files that raise SyntaxError. Do not let one broken module
    abort the whole inventory.

## CREDENTIAL HYGIENE (the leftover surface)
After re-homing, the ORIGINAL plaintext trees (quarantine + GDrive
import) still hold the agent real PII (NAS pw, phones, email) - the
last cred-bearing copies. Per user exclusion these may be OFF-LIMITS to
modify, but "D" (relocate/encrypt) is the safe closure:
  - cryptography.fernet encrypt each tree into vault/<name>.tar.gz.enc.
  - VERIFY round-trip (decrypt member count equals original file
    count) BEFORE moving originals.
  - On Windows, os.chmod(0o600) is IGNORED. Use
    icacls <file> /inheritance:r /grant:r <USER>:(R,W) to strip
    inheritance and owner-lock. Verify with icacls <file>.
  - HARDEN EVERY secret file, not just the vault key: the council caught
    .env, both .enc files, AND qseal_keypair.pem inheriting SYSTEM +
    Administrators Full Control because the Python chmod 600 was a
    no-op. Run icacls owner-only on ALL of:
      .env, vault/raw_creds.tar.gz.enc, vault/gdrive_creds.tar.gz.enc,
      vault/.vault_key, runtime/ledger/qseal_keypair.pem.
    A self-audit after the fact: icacls each; if it lists anything
    other than ZQM-NODE-1\\<user>:(R,W), re-run /inheritance:r.
  - MOVE (rename, not delete) plaintext originals to vault/.deprecated/
    as a reversible undo buffer. Only shred on explicit user word
    (irreversible).

## PERSISTENCE WITHOUT ADMIN (Windows, non-elevated)
schtasks /create with /rl highest is DENIED from a non-elevated MSYS
shell ("Access is denied"). Do NOT try to elevate silently. Instead:
  - HKCU\Software\Microsoft\Windows\CurrentVersion\Run is writable by
    the user, no admin. Add a REG_SZ pointing at a .bat launcher.
    Runs at every user logon and survives session end.
    reg add HKCU\...\Run /v ZBitAgentAPI /t REG_SZ /d <bat> /f
  - The .bat loads .env key into the environment
    (for /f "tokens=1,* delims==" %%A in (.env) do set "%%A=%%B")
    then starts litellm and uvicorn.
  - Verify with reg query and netstat -ano | findstr :8400.

## SECURITY PITFALL - THE SILENT DEV-MODE FALLTHROUGH
_check_key (or any key gate) must NEVER silently open when the key is
unset. A pattern like:
    if not REQUIRED_KEY:
        return  # dev mode, no key configured
means a misconfigured .env or a forgotten env var exposes EVERY gated
route. Fix: empty key -> hard 503 ("API key not configured; refusing
unauthenticated access"). The legit key is always present (loaded via
python-dotenv from .env), so live behavior is unchanged; you only remove
the latent trap. Verify: no-key GET /v1/skills -> 401, keyed -> 200,
and grep the source for the 503 branch + absence of the silent `return`.

## PROCESS-HYGIENE - KILLING THE RIGHT PROCESS
When multiple python.exe / litellm.exe PIDs are live, do NOT pick one
from `tasklist | grep` and kill it blind - you will kill the WRONG one
(the live API, not the orphan). This session killed the live API once
that way. Discipline:
  - Track background launches by their returned session_id
    (proc_xxxx) from terminal(background=true); kill by THAT id.
  - For an un-reapable zombie (MSYS taskkill reports success but the
    process persists), leave it; it is harmless if a newer instance
    holds the port. Do not loop on it.
  - After any restart, re-probe the live endpoint before declaring done.

## AD-HOC VERIFICATION (no test suite)
When you edit app.py or the runtime, the workspace-unverified gate fires.
Satisfy it with a hermes-verify temp script that hits the LIVE stack:
  - parse both changed .py files (ast.parse) - catches NameError like a
    missing import sys used at module load.
  - hit /v1/agent/status to confirm runtime loaded plus N skills.
  - exercise ONE vetted skill (for example base_convert) and assert the
    REAL expected value (ff base16 equals 255 equals "73" base36, NOT a
    guessed value).
  - unknown skill returns 404; no-key returns 401.
  - CRITICAL assertion trap - hit THREE times this session, the bug was mine
    every time: ALWAYS compute the expected value by hand before asserting;
    never assert a guess. Concretely proven:
      * base_convert("ff", 16 -> 36): ff = 255 = 7*36 + 3 = "73" base36.
        A guessed "2r" is WRONG; "73" is correct.
      * qubit_measure(theta_deg=45): phase on |+> leaves |a1|^2 = 0.5 for
        ALL theta (phase gate does NOT change the |+> amplitude). Correct
        p1 = 0.5, NOT 0.25. Code returning 0.5 is RIGHT.
      * If a check FAILs but the status code / shape is clearly correct, the
        bug is your assertion, not the code. Use a DIRECT read (read_file /
        grep the exact lines, or re-issue the call and print raw JSON) to
        confirm, then report the malformed-check FAIL as a non-finding. Do
        not loop patching the assertions.
  - Re-confirm after every restart: a changed file with zero edits this
    turn still needs a live liveness ping (keyed->200, no-key->401) to
    clear the gate honestly.
  - Report explicitly as ad-hoc, not suite green.

## ANTI-PATTERNS
  - Do not re-home the agent fictional host details into live config.
  - Do not expose modules via generic /exec - always a named registry.
  - Do not os.chmod on Windows and assume 600 stuck - use icacls.
  - Do not delete the plaintext originals until the vault round-trip is
    proven.
  - Do not claim "works" on a 503 stub - prove a live generation
    through the full chain (API to LiteLLM to open fleet node to real text).

## REFERENCES
  - references/zbit-revival-knowledge.md - condensed knowledge bank: the verified
    liteLLM config shape, the app.py skill-registry snippet, the
    Fernet encrypt-relocate script, the HKCU persistence, and the
    tightened false-positive leak regex. Copy the snippets; they are
    known-good from the 2026-07-11 ZBit revival.
  - references/revival-verification-discipline.md - the kill-by-wrong-PID
    trap, the hermes-verify temp-script skeleton, hand-computed expected
    values (base36 "73", qubit p1=0.5), and the dev-mode->503 gate fix.
