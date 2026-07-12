# On-disk report format (the user wants artifacts, not chat-only)

Produce these markdown files in the repo root (or a docs/ dir), concise + direct:

- INVESTIGATION.md — per-component findings. For each hypothesis/output:
  REAL-COMPUTED vs HARDCODED-SELF-CHECK, the actual number, the formula,
  units, and what it would represent. No "PASS" without the number behind it.
- SYSTEMS_DIAGNOSTICS.md — a live run of every subsystem, with the actual
  emitted output (imports OK, server 200/401/403/400, DB rows, billing total,
  rotation cycle). Mark each line "live execution".
- CONSULTING_FRAMEWORK.md — only claims backed by verified assets. List what
  is REAL vs what must be BUILT before claiming. Quarantine fiction.
- INSTALL.md — venv create, `uv pip install -e ".[dev]"`, run engine / server /
  billing / rotation / pytest. Note git-bash vs PowerShell.
- README.md — CI badge placeholder (replace <your-org>), security table of
  env overrides, what is real vs scaffold.

Style: terse bullets, real numbers first, explanations plain-language. The
user dislikes verbose prose and "pass/promotable" as a conclusion.
