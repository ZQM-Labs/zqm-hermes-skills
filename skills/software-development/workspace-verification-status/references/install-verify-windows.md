# Install & pytest-collection pitfalls (Windows / uv venv)

Concrete techniques distilled from a real QP-VaaS repo audit where the system
enforced ad-hoc verification after every edit. All reusable beyond that repo.

## 1. `uv`-created venvs have NO `pip` module

`uv venv` does not install pip by default. This fails:

    .venv/Scripts/python.exe -m pip install -e .
    # ModuleNotFoundError: No module named pip

Use `uv pip install` instead, with `VIRTUAL_ENV` set so uv targets the venv:

    export VIRTUAL_ENV="$PWD/.venv"          # bash / git-bash / MSYS
    uv pip install -e ".[dev]"

Powershell: `$env:VIRTUAL_ENV="$PWD\.venv"; uv pip install -e ".[dev]"`.
The system environment note for this host confirms `uv=installed`,
`python3=missing` — so `uv pip` is the canonical installer here.

## 2. `httpx2` is a REAL package — silences StarletteDeprecationWarning

FastAPI's `TestClient` (starlette testclient) emits:
    StarletteDeprecationWarning: Using `httpx` with `starlette.testclient`
    is deprecated; install `httpx2` instead.
`httpx2` (encode-org fork, e.g. 2.5.0) genuinely exists. Installing it makes
starlette's TestClient use it and the warning disappears. It coexists with the
regular `httpx` (separate module, no conflict). Add to dev extras:
    dev = [..., "httpx2>=2.5.0"]   # silences TestClient deprecation warning
Do NOT tell the user "httpx2 doesn't exist" without checking — it does.

## 3. Module-scope `test_*` functions are NOT collected by pytest

A repo had `def test_h8_piezoelectric(): ...` at module scope inside
`api_service.py`. `pytest` found nothing because the default `python_files`
pattern only matches `test_*.py` / `*_test.py` — a plain module named
`api_service.py` is never collected. Symptom: `no tests ran in 0.02s` or
"collected 0 items" even though test functions exist.

Fix: create a real `tests/` package that imports the app and re-runs (or
wraps) those functions. Always use the app's already-instantiated objects
(see pitfall #5). Set `testpaths = ["tests"]` in `[tool.pytest.ini_options]`.

## 4. TrustedHostMiddleware + TestClient masks the real auth assertion

TestClient sends `Host: testserver` by default. If TrustedHostMiddleware
allowlist is `localhost,127.0.0.1`, every request returns 400 BEFORE the auth
dependency runs — so a test expecting 401/403/200 actually sees 400 and fails
misleadingly. Fix: pass an allowed Host header in the test:
    headers={"Authorization": "Bearer ...", "Host": "localhost"}
This is also how you verify the host-validation path itself (bad Host -> 400).

## 5. Bare `import <repo-module>` can shadow stdlib

A test did `import runner` to call `runner.run_hypothesis(...)`. Python
resolved the STDLIB `runpy.runner` (no such attribute) -> AttributeError.
The app already built its runner at import time as `api_service.runner`.
Fix: use the app's object: `api_service.runner.run_hypothesis(...)`, or import
the repo module via a sys.path-guaranteed absolute import, not a bare name
that collides with stdlib (runner, parser, test, etc.).

## 6. SQLite persist functions must self-bootstrap their schema

A Flask/FastAPI service called `init_db()` once at import against the DEFAULT
DB path. On a fresh/relocated DB (e.g. a tmp_path in a test, or a production
path change) the first INSERT threw:
    sqlite3.OperationalError: no such table: usage_events
Fix: make `persist_test_result` / `persist_usage_event` call an idempotent
`init_db()` (CREATE TABLE IF NOT EXISTS) before each write. Then any DB_PATH
self-bootstraps. This also makes the service robust if the DB file is deleted.

## 7. Verify the install actually serves (don't stop at import)

After `uv pip install -e .`, boot the real ASGI server and hit it over HTTP:
    .venv/Scripts/python.exe -m uvicorn api_service:app --host 127.0.0.1 --port 8011 &
    # then httpx GET/POST against http://127.0.0.1:8011/...
Confirm: authed POST 200, no-auth 401, wrong key 403, bad Host 400, CORS no
leak. Then kill the server. Import-success is NOT runtime-success.
