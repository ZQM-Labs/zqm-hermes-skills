# Stability diagnostic + safe-remediation staging (the "diagnostics and improve stability" verb)

Read-only health sweep of a running stack, then STAGED (not applied) improvements.

## Read-only diagnostic surface (per subsystem)
1. **Process supervision** -- enumerate Scheduled Tasks (`schtasks /query`) AND
   running PIDs (netstat -ano -> pid -> Get-CimInstance Win32_Process cmdline+parent).
   If a critical service (Ollama/LiteLLM/ZBit API) is a manual foreground spawn with
   no task/service wrapper, it has NO auto-restart -> MEDIUM supervision gap.
2. **Resource pressure** -- `Win32_OperatingSystem` (FreePhysicalMemory/Total),
   `Win32_Processor.LoadPercentage`, `Get-PSDrive C` free. Flag only if RAM free <15%.
3. **Event-log error scan** -- `Get-WinEvent -FilterHashtable @{LogName='Application','System'; Level=2,3; StartTime=(now-2d)} -MaxEvents 40`.
   DCOM 10016 (permission warnings) is benign noise on every Windows box; real
   signal = service crashes / WER failures.
4. **App-log error grep** -- tail 300 lines of each `*.log`, Select-String
   error|exception|traceback|oom|killed|timeout|refused|failed. Timeouts on a model
   group = flaky routing; 500s on an endpoint = error-path exposure.
5. **Config drift** -- env var set but process binds differently. e.g.
   `OLLAMA_HOST=127.0.0.1:11434` present yet `netstat` shows `:::11434` (all
   interfaces) -> the FW rule is the ONLY thing keeping it off-LAN. Fix = relaunch
   the service with the var inherited, not rely on FW alone.

## Safe-remediation staging gate (the "A+B" pattern)
User authorizes STAGING, not applying. Draft each fix as a script that:
- DEFAULTS to --dry-run (prints the diff / writes a draft file, mutates nothing).
- On --apply, performs the edit.
Validate BEFORE apply without touching live files:
1. Copy the target module dir to a temp dir.
2. Run the patch against the COPY in --apply mode.
3. `py_compile.compile()` every .py in the copy. NONE = syntactically valid.
4. Delete the temp copy. Live files stay untouched.

Reference impl: `swarm/zbit-litellm-20260711/patch_invariant.py`, `patch_scanlan.py`,
`patch_paths.py` (genesis-hygiene fixes) validated via temp copy + py_compile NONE.
Stability fixes: `stability_supervise.py` (3 restart-on-failure tasks),
`stability_ollama_bind.py` (sets OLLAMA_HOST + restart),
`stability_litellm_retry.yaml` (router retry/fallback/health-check).

Never auto-apply. Wait for explicit "apply" / "go".
