# Temp verification harness pattern (Windows / git-bash)

Write to %TEMP% with a `hermes-verify-` prefix. Never put the harness inside
the repo under test (keeps the user's source untouched unless they ask).

Minimal shape:

```python
import sys, os
sys.path.insert(0, r"C:\path\to\repo")
P = lambda *a: print(*a, flush=True)

# 1) import the changed modules
import target_module as t

# 2) exercise REAL behavior, assert it
ev = t.some_call()
P("  some_call ->", ev.field)            # capture actual emitted value
assert ev.field == EXPECTED               # real assertion, not "no error"

# 3) for a server: boot uvicorn in background OR use TestClient
from fastapi.testclient import TestClient
c = TestClient(t.app)
r = c.post("/x", json={...}, headers={"Host": "localhost", "Authorization": "Bearer KEY"})
P("  POST /x ->", r.status_code)
assert r.status_code == 200
```

Run:
```
export VIRTUAL_ENV="$PWD/.venv"
.venv/Scripts/python.exe "C:/Users/<user>/AppData/Local/Temp/hermes-verify-<name>.py" \
  2>&1 | grep -v StarletteDeprecation | grep -v "from starlette"
```
Clean up after: `rm -f "C:/Users/<user>/AppData/Local/Temp/hermes-verify-<name>.py"`.

Gotchas:
- TestClient defaults to Host: testserver -> if TrustedHost restricts, send
  headers={"Host":"localhost"} or you get 400.
- monkeypatch.setattr(MOD, "DB_PATH", db) -> pass a str, not pathlib.Path.
- pip is often absent in a uv venv -> use `uv pip install`.
- liboqs native lib needs cmake; if missing, do pure-Python PQC core math and
  keep the import out of module top level.
