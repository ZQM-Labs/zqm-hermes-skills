# Windows Python Project Repair Notes

This reference tracks evidence from a Windows 10 workgroup project (`zqm-node-02-indexer`) where repair and hardening were needed before reliable local development could continue.

## Environment
- Windows 10 Pro build 26200, WORKGROUP
- Username: zqmco
- Home: `C:\Users\zqmco`
- Project: `C:\Users\zqmco\OneDrive\Desktop\zqm-node-02-indexer`
- Python: 3.11.15 with `uv`; separate Hermes venv under `AppData\Local\hermes\hermes-agent\venv`

## Broken venv evidence
- `.venv/pyvenv.cfg` pointed to Hermes’ own venv
- No `python.exe` or `python.exe` in `.venv\Scripts`
- `.venv/pythonservice.exe` existed but could not execute Python code
- `uv venv .venv` refused because a venv already existed; `--clear` / `UV_VENV_CLEAR=1` forced replacement but produced a relocatable venv without `pip`
- Recovery: `rm -rf .venv`, then `python -m venv .venv`, then `.venv\Scripts\pip install -r requirements.txt`

## Windows path-hardening patterns
- Remove hardcoded Python minor-version paths (`Python312`, `AppData\Local\Programs\Python`) from `.bat`, `.cmd`, `.ps1`
- Prefer PATH lookup with fallback:
  - `.cmd` / `.bat`: try `pythonw.exe`, fall back to `python.exe`
  - `.ps1`: `(Get-Command pythonw -ErrorAction SilentlyContinue).Source`, fall back to `python`
- `service-install.bat` and `install_service.bat` require quoting in `sc create`; verify exact spaces around `=` in `binPath= "..."`
- `zqm_node_service.py` remove handler needs `sys.argv[1] = "remove"` before `HandleCommandLine`, not a no-op

## Verification workflow
- Do not run verifiers inline if shell quoting will fight you
- Write the verifier to TEMP with `tempfile.NamedTemporaryFile(..., prefix='hermes-verify-', delete=False)`
- Execute via `.venv\Scripts\python.exe <tempfile>`
- Delete temp file on completion; label the result as ad-hoc verification, not canonical tests

## Health endpoint hardening
- `/api/health` and similar status endpoints must tolerate missing backend index/state
- Use `get_index_stats() or {}`, not `get_index_stats()` alone, to avoid `NoneType` crashes

## Repo/CD state
- OneDrive directory used as project root; `.git/index.lock` may appear during parallel operations
- `.gitignore` should cover `__pycache__`, `.venv`, `.env`, `*.pyc`, `*.log`, and `node_modules`
- GitHub HTTPS + credential-manager-core issues may require switching to SSH remote or GitHub CLI auth
