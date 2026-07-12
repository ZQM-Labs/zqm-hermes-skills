# Agent Revival — condensed knowledge bank (2026-07-11, ZBit/ZQM case)

## REAL FLEET THIS WAS BUILT ON (verified)
- N1 192.168.1.218  Ollama, 2 models (qwen3:8b). AUTH 401 at service level.
- N2 192.168.1.21   Ollama, 8 models. OPEN (no auth).
- N4 192.168.1.215  Ollama, 45 models. OPEN but deepseek-r1:70b COLD (120s timeout).
- N3 127.0.0.1     Ollama, 2 models. OPEN (localhost).
LB strategy that worked: route zbit-router across N2+N3 (open, fast);
zbit-fast -> N2; zbit-heavy -> N2 hermes3. AVOID N4 70B in hot path.
N1 left commented in litellm_config.yaml (api_key env) until its Ollama key is supplied.

## LITELLM CONFIG SHAPE (localhost, mixed-auth)
```yaml
model_list:
  - model_name: zbit-router          # LB across open fleet
    litellm_params:
      model: openai/deepseek-r1:1.5b   # N2, open
      api_base: http://192.168.1.21:11434/v1
      api_key: "sk-na"            # dummy REQUIRED for openai/ provider
      keep_alive: 5m
  - model_name: zbit-fast
    litellm_params: { model: openai/deepseek-r1:1.5b, api_base: http://192.168.1.21:11434/v1, api_key: "sk-na", keep_alive: 5m }
  - model_name: zbit-heavy
    litellm_params: { model: openai/hermes3:latest, api_base: http://192.168.1.21:11434/v1, api_key: "sk-na", keep_alive: 10m }
  # N1 (.218) key-gated — uncomment + set api_key once Ollama key known
  # - model_name: zbit-router
  #   litellm_params: { model: openai/qwen3:8b, api_base: http://192.168.1.218:11434/v1, api_key: "<OLLAMA_KEY>", keep_alive: 5m }
router_settings: { routing_strategy: simple-shuffle, num_retries: 2, timeout: 60 }
```
Launch: `litellm.exe --config litellm_config.yaml --host 127.0.0.1 --port 4001`
Verify: `GET /v1/models` lists the 3 groups (no master key needed localhost).
NEVER -1 keep_alive.

## APP.PY SKILL REGISTRY (the safety core)
```python
import ZBit_runtime   # dir with __init__.py defining REGISTRY
@app.post("/v1/skill/{name}")
def run_skill(name: str, payload: Optional[dict] = None, x_api_key=Header(None)):
    _check_key(x_api_key)
    if name not in ZBit_runtime.REGISTRY:
        raise HTTPException(404, f"unknown skill: {name}")
    kwargs = {k:v for k,v in (payload or {}).items() if not k.startswith("_")}
    return {"skill": name, "result": ZBit_runtime.run(name, **kwargs)}
```
ZBit_runtime/__init__.py:
```python
REGISTRY = {
  "ledger_append": ledger_append, "ledger_status": ledger_status,
  "mesh_scan": mesh_scan, "base_convert": base_convert,
  "qubit_measure": qubit_measure,
  "qseal_keygen": qseal_keygen, "qseal_sign": qseal_sign,
  "qseal_verify": qseal_verify, "qseal_enroll": qseal_enroll,
}
def run(skill, **kw):
    if skill not in REGISTRY: raise KeyError
    return REGISTRY[skill](**kw)
```
Skills that worked re-homed: forensic_expand (ledger), hive_base
(BaseConverter/BaseArithmetic), zbit_engine (ZBitState), beacon (mesh_scan),
qseal_recruitment (sign/verify re-implemented with cryptography.Ed25519
because the original qseal_*.py were scrub-broken).

## ENCRYPT-RELOCATE CRED TREES (Fernet, reversible)
```python
from cryptography.fernet import Fernet
key = Fernet.generate_key()
# tar each tree, encrypt, write chmod600, then icacls owner-lock
ct = Fernet(key).encrypt(tar_bytes)
out.write_bytes(ct); os.chmod(out, 0o600)
# Windows: os.chmod is IGNORED — owner-lock via:
#   icacls file /inheritance:r /grant:r ZQM-NODE-1\zqmco:(R,W)
# VERIFY round-trip BEFORE moving: decrypt member count == original file count
# Then shutil.move plaintext -> vault/.deprecated/  (reversible, not shred)
```
Key stored at vault/.vault_key (chmod600 + icacls owner-only).

## HKCU PERSISTENCE (no admin)
```
reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v ZBitAgentAPI /t REG_SZ /d "C:\Users\zqmco\ZBit_api\start_zbit.bat" /f
```
start_zbit.bat: `for /f "tokens=1,* delims==" %%A in (.env) do set "%%A=%%B"`
then launches litellm.exe + `python -m uvicorn app:app --host 127.0.0.1 --port 8400`.
schtasks /create /rl highest is DENIED non-elevated — use HKCU Run instead.

## FALSE-POSITIVE LEAK REGEX
SHA256 hashes contain "386" (e.g. `00ceab...9386210547...`). test@test.com
fixtures. Tighten: exclude `[a-z0-9._%+-]+@(?!redacted|test@|example\.|localhost)`.
