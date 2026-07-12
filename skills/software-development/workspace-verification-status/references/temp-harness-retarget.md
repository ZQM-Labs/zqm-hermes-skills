# Temp Harness — Retarget Hardcoded Absolute Paths

Pattern for running a script that hardcodes a state/output path which does not
exist on the current host (cross-user dirs, stale mounts). Lets you observe the
program's real emitted output without editing the repo.

## When
- Script dies with `FileNotFoundError` / `PermissionError` on first write.
- The bad path is a module-level constant (e.g. `runner.SPINE_LOCAL`,
  `SomeClass.cache_dir`) you can monkeypatch before the code touches it.
- You only need to *see output* (one-off verification), not permanently change config.

## How
1. Create temp dir: `tempfile.mkdtemp(prefix="hermes-<proj>-")`.
2. Insert repo on `sys.path`, `import` the module, overwrite the path constant
   with the temp dir.
3. Import/run the entrypoint, print/capture the real payload.
4. Clean up both the temp harness script and the temp dir afterward.

## Gotchas
- Must monkeypatch BEFORE the module uses the path at import time (functions
  that build the path lazily are fine; ones that run at module top-level need
  the constant set first).
- Windows: run with the explicit project interpreter
  (`<repo>\.venv\Scripts\python.exe`), not global `python` (which may resolve
  to another venv). `python3` is often missing on this Windows host.
- If the script also reads from that path, seed the temp dir with any fixture
  files it expects, or confirm it tolerates an empty dir.
- This is a verification technique, NOT a fix. The real defect (hardcoded
  cross-user path, disconnected data source) should be reported separately and
  fixed in-repo on user approval.
