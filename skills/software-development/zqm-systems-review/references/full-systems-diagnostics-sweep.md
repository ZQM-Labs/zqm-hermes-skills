# Full Systems Diagnostics Sweep — reusable template

Use when the user says "full systems diagnostics", "diagnostics on X", or wants a
per-subsystem live checkout of a ZQM repo (e.g. ZQM-Quantum-Automation).

## Procedure
Write ONE temp harness `hermes-verify-diag.py` under `%TEMP%`, run it with the
project `.venv/Scripts/python.exe`, capture stdout, then write
`SYSTEMS_DIAGNOSTICS.md` to the repo root.

## 10 sections (each MUST show real emitted output, not a pass/fail summary)
1. **ENV + DEPS** — `importlib.metadata` version scan of every import the code
   uses. Flag MISSING (esp. console-only scripts like `uvicorn` that may not
   show under that dist name).
2. **MODULE IMPORTS** — import every `.py`; report OK / FAIL with the
   exception type. Also probe phantom deps (`cvg_hive`) the demos need.
3. **HYPOTHESIS / ENGINE** — loop all N units; print REAL vs HARDCODED,
   `pass`, `p_value`; tally computed vs stub and list failures. Do NOT just print
   "all pass" — label each.
4. **SPINE / EVENT WRITE** — count files before/after one run; prove the writer
   no longer crashes on the (formerly cross-user) path.
5. **LIVE API** — `TestClient(app)` (same code path as uvicorn). Hit auth
   (good→200, wrong→403, missing→401), CORS (foreign Origin must NOT leak
   `access-control-allow-origin`), host (bad Host→400).
6. **DB PERSISTENCE** — show table list + row counts; for each persisted verdict
   assert the stored `status` equals the REAL computed verdict, not a hardcoded
   UNKNOWN/FAIL from a status-key mismatch.
7. **BILLING** — generate an invoice covering the real usage window; prove the
   invoice is non-empty and reads the SAME source the API writes (SQLite, not a
   dead JSONL).
8. **ROTATION / CACHE SERVICE** — instantiate, show project-local dirs, run
   one cycle; prove no crash.
9. **REPO HYGIENE** — list root `*.md` vs a `worldbuilding/` (or similar)
   quarantine dir; confirm fiction is separated from engineering.
10. **DEMO SCRIPTS w/ phantom deps** — for each demo, report exists + whether
    it imports a missing package (ImportError at runtime).

## Output artifacts
- `%TEMP%/hermes-verify-diag.py` — delete after the run.
- `<repo>/SYSTEMS_DIAGNOSTICS.md` — the deliverable.
- State explicitly this is ad-hoc verification, not suite green.

## Why this exists
The user repeatedly demanded "real numbers, explain what they mean, label computed
vs hardcoded." A per-subsystem live sweep is the only way to prove a repo's
claimed subsystems actually behave — and to surface the ones that only "pass"
because of a constant, a disconnected data source, or a cross-user hardcoded path.
