---
name: windows-local-service-restoration
description: >
  Restore and debug local services on Windows under MSYS/git-bash:
  Python apps, Whoosh-backed indexers, LAN rebinding, and process-tree
  launcher quirks. Use when a Windows-hosted service is unhealthy, bound
  to localhost only, or blocked by stale OS locks.
---

# Windows local-service restoration

## Stop / start pattern
- Do NOT rely on non-interactive wrappers.
- Preferred explicit chain: `taskkill /F /PID <worker> /PID <parent>`.
- Confirm no listener remains with `psutil.net_connections(kind='inet')`.
- Restart from the repo/checkout that owns the code, in the venv shell
  you actually intend to run.

## Python index / service quirk to avoid
Some Windows git-bash launches spawn a *second* python process from a
different interpreter path. Killing only the parent does not always
kill the actual listener. Always inspect the full parent/chain before
confirming shutdown.

## LAN rebinding
- `127.0.0.1` hosts need `0.0.0.0` for LAN reachability.
- Patch both the waitress path and the `app.run(..., host=...)` fallback.

## Whoosh rebuild blocker
Stale `MAIN_WRITELOCK`/`MAIN.tmp` prevents `ix.writer(...)` even when
the app has “fresh” runtime. Build script must call
`_clear_whoosh_locks(INDEX_DIR)` unconditionally before opening the
index. On Windows the running process can hold the index open, so
lock cleanup is most reliable under a stopped listener.

## Thread-pool rebuild propagation
Bug pattern: background job dict was constructed without `rebuild`,
then overwritten by a nested function definition, and the caller was
not passing `rebuild` through. Fix:
- `_start_background_update(job_id, rebuild)` stores `rebuild` in the
  job dict before the background thread starts.
- `_run_background_update(job_id)` reads `rebuild` from
  `_UPDATE_JOBS[job_id]`.
- Callers pass `rebuild=` explicitly.
- Rebind both `serve(app, host="0.0.0.0")` and `app.run(host="0.0.0.0")`.

## Verification policy
- Use ad-hoc verification scripts under `AppData\Local\Temp` with
  `hermes-verify-` prefix.
- Treat writer/linter output alone as not-green; validate actual
  runtime behavior instead.
