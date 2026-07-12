# Runtime Bring-Up and Config Recovery Notes

These are patterns observed while correlating ZQM-Computing repos with live local
services, Use when `json.load()` fails on an apparently valid config file, especially
after state changes or cross-host file transfers.

## Invalid JSON Escape Sequences in Checked-Out Config Files

Signals:
- `JSONDecodeError: Invalid \escape`
- File appears valid in tree/editor but Python rejects it
- Works after manual re-serialization with escaped backslashes

Causes:
- Checked-out runtime state rather than canonical source config
- Paths stored without JSON-compatible escaping

Fixes:
- Re-overwrite from upstream with properly escaped paths
- Normalize contents before parse: escape lone/non-JSON backslashes, then `json.loads()`
- Write cleaned form back on success so next run is parseable
- Make the rewrite idempotent; avoid mutating the repo tree when possible

## Config Path Hygiene on Windows

Signal:
- Config writes succeed once but reruns fail
- Shell expanduser behaves differently than Python expanduser across invocations
- Path shows up as `C:Users...` rather than `C:\Users...`

Fixes:
- Store mutable runtime config under the user-profile data dir
- Use `os.path.expanduser("~")` in code rather than relying on shell expansion
- Prefer user-data-dir config over repo-tree config for runtime state

## Windows Service Launch Caveats

- Background console sessions in mixed bash/PowerShell environments can surface control errors; prefer direct interpreter/project launcher over raw shell job-control wrappers
- Poisoned `python=` env or shell defaults can launch the wrong interpreter; use the project-local `.venv/Scripts/python.exe` explicitly
