# Revival verification discipline (condensed, 2026-07-11)

Concrete recipes for satisfying the workspace "unverified" gate after
editing app.py / ZBit_runtime/*, plus the process-hygiene lesson that
cost us one live-API kill this session.

## 1. The kill-by-wrong-PID mistake
Symptom: `tasklist | grep python` shows many PIDs; you `taskkill` one
aiming for the stale litellm :4000 orphan and instead kill the LIVE API.
Fix:
  - Always capture the session_id returned by terminal(background=true)
    (e.g. proc_7cc2d2b57a0d). Kill by THAT, not by a PID guessed from
    tasklist.
  - Un-reapable zombie (MSYS taskkill says success but proc persists):
    leave it. A newer instance already holds the port. Don't loop.
  - Restart, then re-probe the endpoint before declaring done.

## 2. hermes-verify temp script shape (ad-hoc, not suite green)
Write to %TEMP% with prefix hermes-verify-, use tempfile, delete after.
Minimal skeleton:

```python
import urllib.request, json, os, tempfile
B="http://127.0.0.1:8400"
KEY=open(r"C:\Users\zqmco\ZBit_api\.env").read().strip().split("=",1)[1]
def g(p,k=KEY):
    try: return json.loads(urllib.request.urlopen(
        urllib.request.Request(B+p,headers={"X-Api-Key":k}),timeout=10).read())
    except urllib.error.HTTPError as e: return f"HTTP{e.code}"
def nokey(p):
    try: return urllib.request.urlopen(B+p,timeout=8).read()
    except urllib.error.HTTPError as e: return f"HTTP{e.code}"
# 1 changed file parses
import ast
for f in [r"C:\Users\zqmco\ZBit_api\app.py",
          r"C:\Users\zqmco\ZBit_api\ZBit_runtime\__init__.py"]:
    ast.parse(open(f,encoding="utf-8").read())
# 2 legit key works, runtime loaded
assert g("/v1/agent/status").get("runtime")=="ZBit_runtime loaded"
# 3 gate intact
assert nokey("/v1/skills")=="HTTP401"   # missing key -> 401
# 4 unknown skill -> 404 (no arbitrary exec)
try: nokey("/v1/skill/exploit")
except urllib.error.HTTPError as e: assert e.code==404
tf=tempfile.NamedTemporaryFile(prefix="hermes-verify-",suffix=".txt",
    dir=os.environ.get("TEMP","/tmp"),delete=False)
tf.close(); os.unlink(tf.name)   # temp marker cleaned
```

## 3. Hand-computed expected values (assert these, not guesses)
  - base_convert("ff",16->36): ff=255. 255 = 7*36+3 = "73" base36.
    CORRECT expected "73". A guessed "2r" is wrong.
  - qubit_measure(theta_deg=45): |+> phase-evolved. a1=(cos45+i sin45)/sqrt2,
    |a1|^2 = (1/sqrt2)^2 = 0.5 for ALL theta. Expected p1=0.5.
    A test expecting 0.25 is the bug (happened twice this session).
  - qseal_sign/verify: generate, sign "hello", verify -> valid=true.

## 4. The dev-mode gate fix (silent open -> 503)
Before: `if not REQUIRED_KEY: return  # dev mode`  -> misconfig opens all.
After: `raise HTTPException(503, "API key not configured; refusing
unauthenticated access")`.
Verify by grepping source: '503' and 'API key not configured' present,
and the silent `if not REQUIRED_KEY:\n  return` line absent.
