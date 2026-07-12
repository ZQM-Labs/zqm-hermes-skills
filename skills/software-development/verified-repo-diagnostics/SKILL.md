---
name: verified-repo-diagnostics
description: Diagnose a software repo by EXECUTION, replace hardcoded "pass"/"PROMOTABLE"
  stubs with real computed numbers (each explained), fix the bugs that block real
  runs, verify every change with a temp harness, quarantine fiction from engineering,
  and make it CI-ready. Use when the user says "investigate", "diagnostics", "proceed
  properly", "real output not pass", "install properly", "get a CI badge", or "improve
  the codebase".
metadata:
  hermes:
    related_skills:
    - audit-sqlite-sink
    - data-eda
    - skill-publish-atomic
---
# Verified Repo Diagnostics & Rescue

Class of task: take a repo (often borrowed / scaffold / mock) and turn it from
"looks green" into "actually computes and is verified". The user wants REAL
emitted numbers with meaning, never "PASS/PROMOTABLE" stubs as the deliverable.

## When to use
- "full systems diagnostics", "investigate properly", "proceed properly"
- "reflect real numbers, not just pass/promotable", "explain what the numbers mean"
- "install properly", "get a CI badge", "improve the codebase"

## Non-negotiable loop (the user enforces this)
READ -> RUN -> FIX -> VERIFY-BY-EXECUTION -> REPORT-ON-DISK.
Never declare done on compilation success. After EVERY code edit, re-run a real
harness and capture stdout. The "fresh passing verification evidence" gate is
real: if you edited code, run the verification command again before claiming done.

## Steps
1. Map the repo by RUNNING it, not only reading. Use the project venv.
   - `python runner.py all` / `pytest` / boot the server with `uvicorn` and hit
     it with httpx. Capture actual stdout / JSON.
2. For each component label every output REAL-COMPUTED vs HARDCODED-SELF-CHECK.
   The user explicitly wants this split, with a plain-language explanation of
   what each real number means (formula + units + what it would represent).
3. Fix the bugs that block real execution:
   - Cross-user / hardcoded absolute paths -> project-relative
     (`Path(__file__).resolve().parent`).
   - Status/persistence key mismatch (e.g. reading `result.get("pass")` that
     doesn't exist) -> persist the real verdict.
   - Security: CORS `allow_origins=["*"]` + `allow_credentials=True` (invalid +
     insecure) -> env allowlist; `TrustedHostMiddleware` hosts `["*"]` -> env
     list; single hardcoded API key + `==` compare -> env keys +
     `secrets.compare_digest`.
   - Billing/service reading a non-existent source (JSONL never written) ->
     read the real datastore the writer actually populates.
   - Generic endpoints passing a params dict into an `iterations: int` arg ->
     call with `1` and persist params separately.
4. Replace hardcoded pass/stubs with REAL math where feasible. If a heavy lib
   (liboqs) won't build (no cmake), implement the core math in pure Python
   instead of importing it — keep the import OUT of module top level so a missing
   native lib can't crash the runner. Import-safe + genuinely computed beats a
   green-but-fake test.
5. VERIFY by execution in a temp harness:
   - Write to %TEMP% with a `hermes-verify-` filename prefix.
   - Assert REAL behavior (status codes, DB rows, computed values), not just
     "no exception". Clean the script up after.
   - When no canonical suite exists, build a small `tests/` with pytest that
     asserts the fixed behavior; run `pytest -q` and show the count.
6. Separate fiction from engineering: move worldbuilding/narrative markdown into
   a `worldbuilding/` subdir so the repo root is client-presentable. Never let
   speculative narrative sit next to commercial/security claims.
7. CI-ize for a real badge:
   - Real `.github/workflows/ci.yml` using `uv` (not `pip` if pip isn't in the
     venv) + `pytest`.
   - `Dockerfile` with uv install, secure-by-default host env.
   - `pyproject.toml` (PEP 621) with deps + `dev` extra; `testpaths=["tests"]`.
   - A badge markdown is ONLY valid after a real hosted CI run — never fabricate
     a green badge. Init git locally; push is the user's call.
8. Report on-disk as markdown (not chat-only): INVESTIGATION.md,
   SYSTEMS_DIAGNOSTICS.md, CONSULTING_FRAMEWORK.md (only claims backed by
   verified assets), INSTALL.md, README.md with the badge placeholder.

## Pitfalls
- `pip` may be absent from a uv-created venv -> use `uv pip install`.
- liboqs native lib needs cmake; if missing, do pure-Python PQC core math.
- TestClient defaults to `Host: testserver`; if TrustedHost restricts hosts,
  send `headers={"Host":"localhost"}` or the request 400s.
- `monkeypatch.setattr(MOD, "DB_PATH", path)` -> pass a `str`, not a `Path`, to
  match `sqlite3.connect` and avoid subtle failures.
- Don't add a pytest file that collects nothing; ensure `testpaths` and that
  test functions are named `test_*`.

## Verification command (Windows git-bash)
`export VIRTUAL_ENV="$PWD/.venv" && .venv/Scripts/python.exe -m pytest -q`
Pipe through `grep -v StarletteDeprecation | grep -v "from starlette"` to cut
noise; install `httpx2` to silence the StarletteDeprecationWarning entirely.

See references/temp_harness.md and references/report_format.md.
