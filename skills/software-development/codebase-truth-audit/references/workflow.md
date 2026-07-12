# codebase-truth-audit — session workflow & gotchas

## Canonical command sequence (Windows + git-bash, this host)
```
cd C:\Users\zqmco\<repo>
export VIRTUAL_ENV="$PWD/.venv"          # SO uv targets the venv
uv venv --python 3.11 .venv               # create venv (uv is the PM; pip absent)
uv pip install -e ".[dev]"                # editable install; pulls uvicorn + dev
.venv/Scripts/python.exe -m pytest -q     # run suite
```
pip module is NOT in the venv -> use `uv`, never `python -m pip`.

## Real-verification loop (mandatory after any edit)
1. Write a temp harness `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*.py`.
2. Run it; grep out `StarletteDeprecation` / `from starlette` noise.
3. Capture ACTUAL output; assert expectations in the script.
4. Delete the temp file after.
System-reminder "verification unverified" flags = re-run trigger, not optional.

## Verification classes
- Engine/subsystem: import + run; print REAL numbers + what they mean.
- Live API: use `uvicorn api_service:app --host 127.0.0.1 --port 8011` in
  background, then `httpx` GET/POST. Confirm 200/401/403/400 + CORS no-leak.
  Kill the server after. TestClient (no real socket) is fine for pytest but
  boot a real server at least once for "install properly".
- DB: sqlite3 connect; check schema + row statuses are the REAL verdict
  (fixed status-key bug wrote UNKNOWN/FAIL for passing tests before).

## Gotchas fixed this session (ZQM-Quantum-Automation)
- Dead cross-user path `C:\Users\AlexZelenski\...` -> retarget to project-local
  `spine_events/`. Was a FileNotFoundError crash on host zqmco.
- H2 was `sha3("pqc-stub")` (hardcoded). Rewrote to real PQC core math (SHA3-256,
  SHAKE128 XOF prefix-stable, WOTS+ l1/l2/l FIPS-205 check, NTRU ring Z_q[x]/(x^n-1)).
  liboqs native lib won't build (no cmake) -> kept import-safe, no top-level import.
- api_service: CORS `["*"]`+`allow_credentials`, TrustedHost `["*"]`, hardcoded
  key -> env-driven allowlists + `secrets.compare_digest`.
- billing read a non-existent JSONL -> read the real SQLite `usage_events`.
- persist funcs assumed `usage_events` exists -> added idempotent `init_db()`
  call before writes (self-bootstrapping schema) — caught by pytest on tmp DB.
- pytest "no tests ran" -> added `tests/` package + `testpaths=["tests"]`.
- `from cvg_hive import Client` is lazy (inside fn) -> module imports OK, fn
  raises RuntimeError when called; not a blocker, just non-runnable demos.
- StarletteDeprecationWarning ("use httpx2") is bogus/FastAPI-side, harmless.

## Output artifacts written (this repo)
INVESTIGATION.md, SYSTEMS_DIAGNOSTICS.md, CONSULTING_FRAMEWORK.md, INSTALL.md.
Fiction quarantined to worldbuilding/{dark_realm,omnimap,progress_map}.md.
