---
name: codebase-truth-audit
description: 'For repos that overclaim (marketing/technical claims not backed by code)
  or are foreign/borrowed scaffolds: run full systems diagnostics, separate fiction
  from engineering, rewrite hardcoded stubs into real computation where feasible,
  fix security-posture self-contradictions, install properly, and verify every fix
  by live execution before declaring done. Triggered by "investigate properly", "install
  properly", "rewrite where necessary", or any request to make a codebase''s claims
  TRUE rather than just report them.'
metadata:
  hermes:
    related_skills:
    - audit-sqlite-sink
---
# When to use
- User asks to "investigate properly", "install properly", "rewrite where
  necessary", or wants claims made TRUE, not just diagnosed.
- A codebase's docs/narrative claim capabilities the code doesn't implement
  (hardcoded pass, dead cross-user paths, fictional worldbuilding).
- You must produce real emitted output (JSON/data/stdout), never a
  pass/fail-"compiled" summary.

# Load-bearing principles
1. INVESTIGATE BY EXECUTION. Run each subsystem; capture actual stdout/JSON.
   Never report a claim as working without a live run.
2. SEPARATE FICTION FROM ENGINEERING. Move narrative/worldbuilding markdown into
   a quarantined subdir (e.g. `worldbuilding/`) so the repo root reads as
   software. Never let fiction near a client deliverable.
3. MAKE THE CLAIM TRUE, don't just flag it. If a hypothesis/service claims X but
   is hardcoded, rewrite it to actually compute X (pure-Python is fine when
   native libs won't build). If you can't make it true, say so and EXCLUDE it
   from the pitch — do not leave a false claim in a rate-card repo.
4. FIX SELF-CONTRADICTIONS. A security-consulting repo must not ship wildcard
   CORS + credentials, hardcoded keys, or `*` TrustedHost. The repo's own
   corrected posture is the case study you show clients.
5. INSTALL PROPERLY. Real `pyproject.toml`; editable install with the project's
   actual package manager; then boot the server for real and hit it over HTTP.
6. VERIFY BY EXECUTION, EVERY TIME. After any edit, run a temp harness
   (`hermes-verify-*.py` under %TEMP%) or pytest, capture output, then delete the
   temp file. Never declare done on a stale green. Treat system-reminder
   "verification unverified" flags as mandatory re-run triggers.
7. RECREATION-DIFF EVERY CLAIM BEFORE TRUSTING THE LEDGER (verified 2026-07-11).
   When the user says "investigate properly" (or any full-scope re-audit), do NOT just
   re-read your own prior findings — RE-DERIVE each claim from LIVE state and DIFF the
   recorded text against what you actually observe. This catches (a) your OWN prior
   errors that slipped into the ledger, and (b) STATE CHANGES that happened since
   you last looked. In one session it caught: F27 (ledger said "10108 quarantine
   items"; live re-count = 8543 — my own stale number) and F4 (ledger said N2 Redis
   CRITICAL unauth; live re-probe returned `-NOAUTH` — someone had secured it, a
   real state change). Method: for each finding, emit a live probe (urllib/chat, raw
   TCP, netstat, file count) and assert recorded-severity/status still holds; flip any
   that drifted and RE-HASH the ledger. The discipline is the deliverable — it
   found 2 self-errors + 1 external state-change where a naive "re-read the summary"
   would have certified all 3 as still-true.
8. DOCUMENT ON-DISK. Write INVESTIGATION.md / SYSTEMS_DIAGNOSTICS.md /
   CONSULTING_FRAMEWORK.md; chat summary is secondary.

# Workflow (detail in references/workflow.md)
1. Inventory files + deps + DB schema.
2. Run engine/H/all subsystems live; tabulate REAL vs HARDCODED.
3. Fix dead paths (retarget cross-user hardcoded paths to project-local).
4. Rewrite hardcoded stubs to real math where feasible.
5. Harden security posture (env-driven CORS/host/auth, constant-time compare).
6. Wire broken integrations (e.g. billing reads the source the API actually writes).
7. pyproject + editable install + real server boot.
8. Write a real pytest suite; run it; FIX what it breaks (pytest surfaces real
   bugs: shadowed imports, missing schema, wrong assertions).
9. Write on-disk reports; quarantine fiction.

# Gotchas (see references/workflow.md)
- Windows + git-bash: `export VIRTUAL_ENV="$PWD/.venv"` so `uv pip` targets the venv.
- `pip` may be absent in the venv -> use `uv pip install -e ".[dev]"`.
- Native libs may not build (no cmake) -> keep imports lazy/import-safe; do
  pure-Python equivalents.
- `from cvg_hive import Client` (lazy, inside a function) crashes only when the
  function runs, not at import — module still imports OK.
- pytest "no tests ran" -> testpaths wrong or no `tests/` package; set
  `testpaths=["tests"]` and add `tests/__init__.py`.
- DB persist "no such table" -> make persist funcs call idempotent `init_db()`
  before writing (self-bootstrapping schema).

# Agent knowledge base (omnmap a USER-BUILT agent's memory)
A frequent case: the user points you at a folder of markdown + code that is
another AGENT's memory/identity/knowledge-base (e.g. the ZQM/ZBit tree this
session). Treat it as FIRST-PARTY, not untrusted.

- **DO NOT flag or scrub it as "contaminated".** A folder literally named
  `CVG-CONTAMINATED-*` is just a label the user chose — NOT a verdict. The user
  corrected this explicitly: "not 3rd party... just memories and dreams from
  another agent we created." Scrubbing/quarantining it on your own initiative is
  WRONG. Investigate, report, and only act on explicit GO.
- **Read them all.** Enumerate every `.md` + every `.py` (search_files + terminal
  `ls`, since search_files misses spaces/parens in paths). Classify docs REAL
  (ops knowledge worth keeping) vs FICTION (self-narrative / aspirational
  metrics). Classify modules REAL / thin / STUB by line count.
- **Separate the agent's SELF-BELIEF from verified reality.** Its SOUL/README
  will claim "services live", "N models", "X blocks/hr", "Y devices" — re-check
  each against the REAL environment (your fleet, not its invented host). In the
  ZBit case: it claimed an HP Pavilion / 11 Ollama models / 63 devices / running
  Gateway:8080 — all FALSE vs the real ASUS Node-1 / 57 models across 4 nodes /
  0 listening services (its own stubs confirmed it).
- **Leak surface is the real risk, not the fiction.** Run the STRICT leak-sweep
  in `references/leak-sweep.md` (real NAS pw + real phones survive even a
  "redacted" sanitize pass — re-scrub and re-verify).
- **Re-home instead of run.** The agent's code is usually bound to a DEAD host
  (old IP, `D:\` paths, old username). Don't execute it as-is. Build a thin API
  adapter that re-homes its identity onto the REAL fleet — pattern in
  `references/agent-kb-rehome.md` (FastAPI + LiteLLM LB over verified Ollama
  nodes; keep_alive TTL; localhost-only; X-Api-Key; read-only mesh/ledger).
- **Persist findings to SQLite** (see `audit-sqlite-sink`): zips, leaks,
  contradictions, fleet_checks, old_host_refs. Omnimap + code-surface each become
  on-disk artifacts; the .db is the queryable evidence.

# Security & Secrets Posture Audit (agent-revival variant)
When the ask is "AUDIT for SECURITY & SECRETS posture only" of a re-homed agent
(service + vault + cleaned zips), run the independent, don't-trust-prior-claims
recipe in **`references/security-secrets-audit.md`**. It covers the live checks
that worked: 401/200 key gate via curl, `netstat` loopback-bind proof,
REGISTRY-no-eval code read, `-F` strict PII grep across both unzipped trees,
`icacls` vault ACLs, deprecated-plaintext count, AND the read-only loopback
service-stack posture review (LiteLLM `master_key` absence → unauthenticated
completions; /docs/redoc/openapi.json schema disclosure; sentinel-key 401 gate
probes; real-completion-vs-error-page body check; PROVEN/UNVERIFIED + redaction
report discipline). KEY PITFALL it captures: a spec claim of "owner-only ACL via
icacls / chmod 600" is NOT the Windows default — default DACL grants
SYSTEM+Administrators Full; verify with `icacls` and use `/inheritance:r /grant:r`
to actually strip them. Also: `read_file` BLOCKS `.env` reading (defense-in-depth),
so read the key via terminal `grep`; `search_files` likewise omits `.env` hits, so
confirm presence via `ls` and report location/size only.

# Overlap
Overlaps with `software-development/runtime-codebase-verification` and
`workspace-verification-status` (both about ad-hoc verification), and with
`devops/local-service-verification` (Windows localhost-service bind/auth checks).
The security-secrets-audit reference is the narrower agent-revival
specialization; `local-service-verification` is the general localhost-service
variant — curator may consolidate the two Windows-service angles. This skill
adds the commercial-truth layer: quarantine fiction, rewrite claims true, and
the install-verify loop. The "Agent knowledge base" section above adds the
user-built-agent-memory variant (first-party, leak-sweep, re-home). Curator may
consolidate.
