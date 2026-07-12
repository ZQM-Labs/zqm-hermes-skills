# Runtime Codebase Verification — Recipe and Gotchas

Concrete, copy-paste harness used to verify a foreign FastAPI plus QuantumTestRunner
project on a Windows/MSYS host (Python 3.11.15, uv available, python = 3.11,
python3 = missing / MS-Store alias). `pip` is ABSENT in this venv — use `uv pip`.

## 1. Create venv and install (uv, MSYS)
```bash
cd "C:/path/to/project"
uv venv --python 3.11 .venv
# NOTE: must include the .exe suffix or uv errors "No virtual environment found"
export VIRTUAL_ENV="$PWD/.venv"   # so `uv pip` targets the venv
uv pip install -p .venv/Scripts/python.exe -r requirements.txt
# requirements.txt is usually incomplete; add what the code imports:
uv pip install -p .venv/Scripts/python.exe fastapi httpx
```
- Do NOT put uvicorn in the install line. The long-lived-server guardrail can block a
  foreground command containing that token. fastapi.testclient.TestClient only needs
  httpx, so uvicorn is unnecessary for running tests.
- For a proper install, add a pyproject.toml (PEP 621) with [project] deps + optional
  [dev] extras, then: `uv pip install -p .venv/Scripts/python.exe -e ".[dev]"`
  This installs the project editable AND pulls uvicorn (needed for the real server boot).
  Confirm: `uv pip list` should show the project name + uvicorn.

## 2. Temp verification harness (retarget foreign paths, no repo edits)
Save as the local temp dir hermes-verify-<topic>.py and run with the venv python.
```python
import sys, tempfile
from pathlib import Path
PROJ = r"C:\path\to\project"
sys.path.insert(0, PROJ)

# Retarget a hardcoded foreign or cross-user path BEFORE importing behavior.
SPINE = Path(tempfile.mkdtemp(prefix="hermes-verify-spine-"))
import runner
runner.SPINE_Z = SPINE
runner.SPINE_LOCAL = SPINE

rt = runner.QuantumTestRunner()
for hid in [f"H{i}" for i in range(1, 36)]:
    ev = rt.run_hypothesis(hid, 1)
    print(hid, ev["promotion"], ev["passes"], ev["total"])
    # Proof of status-key bug: envelope may have no top-level "pass"
    # -> api_service would persist result.get("pass") as None => FAIL / UNKNOWN
    # print("envelope keys:", list(ev.keys()), "top_pass:", ev.get("pass"))

import api_service
for name, fn in vars(api_service).items():
    if name.startswith("test_") and callable(fn):
        try:
            fn(); print("PASS", name)
        except Exception as e:
            print("FAIL", name, repr(e))
```
Why this shape: the repo hardcoded C:\Users\AlexZelenski\Desktop\spine_local\events (the
original author's machine). On this host that dir cannot be created (PermissionError), so
runner.py crashed at _record write. Overriding SPINE_LOCAL lets the real code run and emit
real results without editing the repo.

## 3. What to check after a green run
- DB rows, not HTTP status. The verified project logged usage to a SQLite usage_events
  table while an adjacent billing_service.py read quantum_automation/usage_events.jsonl (a
  file the API never wrote), so billing would emit empty invoices. Trace producer versus
  consumer data source.
- Status-key mismatch: api_service did result.get("pass") on an envelope with no top-level
  pass (it had per-result pass and a promotion field), so H21-H30 always persisted FAIL;
  H8-H12 used result.get("status","UNKNOWN") and the envelope had no status, so always
  UNKNOWN. Confirmed live in the SQLite test_results table.
- DB self-bootstrap: persist functions that assume init_db() ran at import throw
  "no such table" on a fresh/relocated DB_PATH. Fix: call init_db() (idempotent
  CREATE TABLE IF NOT EXISTS) at the top of each persist fn.

## 4. Real pytest run (after edits)
```bash
cd "C:/path/to/project"
export VIRTUAL_ENV="$PWD/.venv"
.venv/Scripts/python.exe -m pytest -q
```
Gotchas:
- test_* functions inside a non-test_*.py module (e.g. api_service.py) are NOT collected.
  Move them to tests/test_api_service.py or rename the file test_*.py.
- Set `testpaths = ["tests"]` in pyproject [tool.pytest.ini_options]; testpaths=["."]
  won't pick up tests/.
- A bare `import runner` in a test can shadow with stdlib runpy.runner — use the app's
  own instance (api_service.runner) instead.
- TestClient sends Host: testserver; a TrustedHost allowlist (localhost) rejects it -> 400,
  so auth tests must send an allowed Host header to get the expected 401/403/422.

## 5. Server boot = the real install proof
```bash
# background
cd "C:/path/to/project"
export VIRTUAL_ENV="$PWD/.venv"
QP_VAAS_ALLOWED_HOSTS="localhost,127.0.0.1" \
  .venv/Scripts/python.exe -m uvicorn api_service:app --host 127.0.0.1 --port 8011 > /tmp/boot.log 2>&1 &
sleep 4
.venv/Scripts/python.exe -c "
import httpx
h={'Host':'localhost'}
print('root', httpx.get('http://127.0.0.1:8011/', headers=h).status_code)
r=httpx.post('http://127.0.0.1:8011/api/v1/validate/piezoelectric',
  json={'material_id':'PZT-5H','orientation':'001','stress':100.0,'strain':500.0},
  headers={**h,'Authorization':'Bearer example-key-12345'})
print('authed', r.status_code, list(r.json().keys()))
print('noauth', httpx.post('http://127.0.0.1:8011/api/v1/validate/piezoelectric',
  json={'material_id':'PZT-5H'}, headers=h).status_code)
print('badhost', httpx.get('http://127.0.0.1:8011/', headers={'Host':'evil.com'}).status_code)
"
# then kill the server
```
Expect: authed 200, noauth 401, wrong key 403, badhost 400. This exercises the env-driven
CORS/host/auth config over real HTTP, not just TestClient.

## 6. Honest reporting template
- State install and run method (venv path, command).
- Give real pass/fail counts from execution.
- Call out each reproduced bug with file:line.
- Explicitly separate: tests GREEN, but green means the scaffold runs and self-reports
  PASS; it does NOT validate the domain, versus real computation confirmed (e.g. H1 hash
  reproduced; H31-H35 genuine geometry math; H2 real PQC core math).
- Report real numbers WITH meaning (what the metric is, what the value implies).
- Note the fiction/engineering split (worldbuilding/ vs repo root).
