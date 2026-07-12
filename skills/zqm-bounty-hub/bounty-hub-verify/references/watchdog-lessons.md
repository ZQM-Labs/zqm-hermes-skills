# Watchdog/cron workaround notes

- Hermes cron on this build fails for `repeat: forever` with recurring schedules like `every 60m` / `1h` / `30m`; it raises a string-vs-int comparison error during recurrence validation.
- Workaround: local `hub_verify_watchdog.py` with `time.sleep(3600)` between runs.
- Prefer `C:\\Users\\zqmco\\AppData\\Local\\hermes\\venvs\\bounty-hub-research\\Scripts\\python.exe` for subprocess launches; fall back to `sys.executable`.
- Direct subprocess execution of `main()` times out harnesses; verify `run_once()` behavior instead.
- HackerOne token auth should prefer cached file at `C:\\Users\\zqmco\\.local\\share\\hermes\\h1_token` because env probing can pick up unintended tokens.
- Ad-hoc verifier temp files should live under `C:\\Users\\zqmco\\AppData\\Local\\Temp` and be removed after the run.

# Windows service / process debugging lessons

- `wmic` is unavailable in git-bash on some Hermes shells; fall back to `psutil` via Python to enumerate processes by cwd/cmdline when port-to-pid mapping is insufficient.
- Startup logs alone can lie: a service bound successfully to 8188 may still `refuse` later if its prompt/runtime handler crashes without surfacing to stdout. Always do an HTTP behavior test (`/` plus a minimal application-level probe like `/prompt`) after service start.
- `Error handling request` in ComfyUI logs without a Python traceback usually means prompt validation failure, not process death. To capture the actual exception, run the service in foreground and redirect stdout to a temp log file; do not rely on the rotated `user/comfyui_*.log` alone.
- Empty/minimal prompts in ComfyUI return `prompt_no_outputs`; that is a valid healthy response and not a transport failure. Use it as a transport smoke test, not a workflow execution test.

# Indexer persistence and binding lessons

- The local file-indexer persists state in SQLite and skips roots whose top-level dir mtime has not changed since the last indexed `last_indexed` timestamp. After editing `config.json`, restarting may still report `root_skip_unchanged: 5` because roots were recorded in `root_walk_state`; expect the first post-edit run to show zero counts quickly followed by a real indexing pass once state updates.
- Indexer configs frequently bind to `127.0.0.1` only; remote LAN probes to the host's LAN IP will fail even when `/api/health` returns 200 locally. Rebind/schedule install must be re-run after path changes.
- Node-01/02 indexer recovery from a non-default OneDrive/Desktop path requires updating `install-service.ps1` / scheduled task working directory before reinstalling the task.
