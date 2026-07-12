---
name: workspace-verification-status
description: "Enforce ad-hoc verification when no canonical test suite exists: create hermes-verify- temp scripts, run them against changed behavior, clean up, and report explicitly as ad-hoc rather than suite green."
version: 0.1.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [verification, testing, smoke, ad-hoc, windows]
    related_skills: [test-driven-development, systematic-debugging]
---

# Workspace Verification Status

## Overview

Many repos lack a canonical test/lint/build command. This skill defines the
fallback verification protocol so changed code is still validated before it is
marked complete.

## When to Use
# Workspace Verification Status

## Overview

Many repos lack a canonical test/lint/build command. This skill defines the
fallback verification protocol so changed code is still validated before it is
marked complete.

## When to Use

- Repository has no `pytest`, `tox`, `make test`, or similar canonical command
- You edited code and the runtime asks for fresh verification evidence
- You just added a smoke/gate script and need independent confirmation
- User asked for "formal suite green" but no suite exists

## Core Rule

**Changed code is unverified until you run a focused verification script and
return the actual output. Never claim suite green without evidence.**

## Protocol

### 1. Create temp verification artifact

Use OS-safe temp location and filename prefix `hermes-verify-`:

```python
import os, tempfile
fd, path = tempfile.mkstemp(prefix="hermes-verify-", suffix=".py", dir=os.environ.get("TEMP", "/tmp"))
os.close(fd)
# write script content to path
```

**Windows caveat:** on some Windows Hermes shells the resolved `TEMP` path can
fail on execution even when write succeeds. Preferred fallback: write
`hermes-verify-*.py` inside the repo or project tree, run it with the explicit
project interpreter, then remove the repo-local copy afterward. Verification
content matters; location is secondary. Always report the actual path used.

### 2. Run against changed behavior only

Execute the temp script with the project's expected interpreter/environment.
Capture stdout/stderr and exit code.

**Windows note:** do not rely on the global `python` if the project uses a
local virtualenv. Use the repo-local interpreter explicitly, e.g.
`.venv/Scripts/python.exe` on Windows.

### 3. Clean up

Delete the temp artifact after the run, regardless of pass/fail. If the user
blocks deletion or cleanup cannot complete, report the cleanup status
explicitly. Do not silently leave verification scripts in the repo tree.

### 4. Report explicitly

State:
- What was checked
- Actual output
- Exit code / assertions
- That this is ad-hoc verification, not suite green
- Whether cleanup succeeded

## Example

```
Ad-hoc verification completed. Temp artifact retained because user blocked
repo-tree deletion; can be removed manually if desired.

Evidence:
- Checks: config path, JSON validity, invalid-escape recovery, get_index_stats()
- Results: 11/11 passed
- Cleanup status: NOT removed from repo tree per user denial
- Note: ad-hoc verification only; no canonical CI command present
```

## Pitfalls

- Do NOT reuse old verification output as fresh evidence
- Do NOT claim suite green when only ad-hoc checks passed
- Do NOT leave temp scripts in place after verification
- Do NOT skip verification because a previous run passed
- Avoid retrying blocked commands unchanged; switch strategy/perm/invocation path
  instead of repeating the same shell call after denial
- On Windows, prefer repo-local temp location when `%TEMP%` execution is
  unreliable; match the project interpreter explicitly
- Windows shell path resolution: absolute Windows-style paths with drive letters,
  MSYS `/c/...`, and mixed backslash/forward-slash forms can all fail in one shell
  pass but succeed in another. After 2 identical-path failures, rerun the runner
  once before changing strategy.
- On Windows, if `python` resolves outside the project venv and raises
  `ModuleNotFoundError`, rerun with the explicit repo interpreter
  `.venv/Scripts/python.exe`
- **Flask blocking route pattern** — if an endpoint like `/api/index` calls a
  long operation such as `build_index` inline, the HTTP request blocks until
  completion. Verify by source inspection or runtime load, not just a happy-path
  `200`. The fix pattern is to enqueue a job, return `202 Accepted` with
  `job_id`, and let a worker thread run the work. Do not swap async load fixes
  without also verifying job submission and status endpoints remain callable.
- **Windows temp-script execution** — writing a temp script can succeed while
  execution fails because the resolved interpreter path is shell-mangled. Preferred
  fallback: copy the temp script into the project tree as `hermes-verify-*.py`,
  run it with the explicit project interpreter, then remove the repo-local copy
  afterward. Only deviate if the user explicitly asks for cleanup differently.
- **Background service duplicates on Windows** — if multiple indexer/server
  processes are launched, kills from older sessions may still show up as
  termination notices later. Always verify with `netstat`/`curl`, not just the
  absence of notices. Prefer one explicit managed background session plus health
  checks instead of many shell background jobs.
- **Live code != running process** — on Flask/Waitress/uvicorn-style services,
  script edits do not automatically reach the active server. After editing
  runtime code, restart or reload the service, then verify with `/health` and
  the exact changed endpoint/callsite. Source-passing checks alone are not
  runtime evidence.
- **Manifest/index desync** — a Whoosh/FAISS/Lucene index can grow while
  `config.json`, manifest rows, or metadata.db stay stale. If `indexed_files`
  is `0` while `document_count` is nonzero, patch `get_index_stats()` to
  fall back to live index counts instead of trusting manifest-only state.
- **Async rebuild job status** — `/api/index` with `rebuild=true` should
  return `202`, and `/api/update/<job_id>` should surface `status`,
  `progress`, and final `indexed_files` once complete. Verify both the queued
  response and the terminal status when testing rebuild paths.
- **PowerShell parser probing from Python/subprocess** — inline PowerShell
  parser calls often fail before running the underlying script because the
  invocation itself is malformed. Separate concerns: use a dedicated helper
  script for parser validation, and/or diagnose PowerShell syntax errors from
  the actual script text before retrying execution.
- **Install & pytest-collection pitfalls (Windows / uv venv)** — new reusable
  techniques captured in `references/install-verify-windows.md`:
  (1) `uv venv` ships NO pip module — use `uv pip install` with `VIRTUAL_ENV`
  set; (2) `httpx2` is a REAL encode fork that silences the Starlette
  deprecation warning in TestClient; (3) module-scope `test_*` funcs are NOT
  collected by pytest — wrap them in a `tests/` package; (4) TrustedHost +
  TestClient masks auth assertions (default Host=testserver -> 400 before auth
  runs) — send an allowed Host header; (5) bare `import runner` shadows stdlib
  `runpy.runner` — use the app's instantiated object; (6) SQLite persist funcs
  must self-bootstrap schema (idempotent `init_db()`) or a fresh DB throws
  "no such table"; (7) verify the real server boots over HTTP, not just import.
- **Report the bare warning text** — when a run shows "N passed, 1 warning",
  do not hand-wave it. Re-run with `-W error::DeprecationWarning` or capture
  the warnings summary and paste the exact `file:line: WarningClass: message`
  line, then decide if it is cosmetic (dependency) or a real signal.
- **Substring-assertion bug in verification SUMMARIES (verified 2026-07-11).**
  When your verify script computes a pass/fail BOOLEAN from a substring test,
  `in` is a SUBSTRING match, not a word match. `"FOUND" in "TASK_NOT_FOUND"`
  returns `True` — so a `log("applied: %s" % ("YES" if "FOUND" in out else "NO"))`
  line printed "YES" for a task that was NOT created. The raw detail line was
  correct (`TASK_NOT_FOUND`); only the derived summary was wrong. FIX: assert on
  an EXACT anchor, e.g. `out.strip().startswith("TASK_FOUND")` or
  `out.strip() == "NOT_FOUND"`, never a bare `in` against a token that appears
  inside a negative string. Re-run the verify script after fixing the summary
  logic and confirm the corrected result — the bug itself is proof you must
  verify the VERIFIER's output, not just the target's.
- **`nul` STRAY-FILE GOTCHA (verified 2026-07-11).** Inside Python `subprocess.run(["cmd","/c","... 2>nul"])`, the `2>nul` is NOT a shell redirect — `cmd /c` is invoked directly, so the literal token `nul` becomes a REAL output file written to the cwd. It then corrupts `git add -A` ("invalid path 'nul'", fatal). FIX: never embed `2>nul` in a list-form subprocess; use `stderr=subprocess.DEVNULL` (Python) or `2>err.log` to a real temp path, or run via a shell string `cmd /c "..."` where `nul` IS a device. After any `cmd /c` call, `if os.path.exists("nul"): os.remove("nul")` defensively before git ops. (This bit a deploy-and-commit flow: the stray `nul` blocked the commit until removed.)
- **VERIFY THE TRANSFORM OUTPUT, not just that the script ran.** When a verification script mutates config/state, re-load the produced artifact and assert the TARGET changed (e.g. `assert "llama3.3:70b" not in str(yaml.safe_load(out))`). A script that prints "dropped X" can silently no-op if its filter targeted the wrong key (see ollama-fleet-lb `litellm_params` nesting). The ad-hoc verify must FAIL when the artifact is unchanged — otherwise it certifies nothing. (Hit 2026-07-11: integrate_fleet.py reported success but left the target entry + `keep_alive -1` untouched because the fields were nested under `litellm_params`; the re-load assertion caught it.)
- **Windows scheduled-task / service live-state check (verified 2026-07-11).**
  After attempting `Register-ScheduledTask` (needs elevation) or a service
  change, do NOT trust exit-code 0 or a "process returned" message — a UAC
  denial returns exit 0 silently (see fleet-council-audit
  `windows-privileged-remediation.md`). INDEPENDENTLY re-verify the actual state:
  `Get-ScheduledTask -TaskName 'X'` → expect the task object or NOT_FOUND;
  re-read the registry key (`Get-ItemProperty ...FailureActions`) to confirm a
  service recovery change landed. Report the live-state read, not the launcher's
  return value. This holds even with `-Wait`: a dismissed UAC prompt still returns 0
  after the `-Wait`, and the elevated process may never have executed the script. The
  only trustworthy signal is the independent live-state re-read (Get-ScheduledTask /
  registry key), never the launcher's return.
- **Windows terminal `$PY`-var-not-persisting / cmd.exe quote-mangling (verified 2026-07-12).** Chaining a Python heredoc via `cmd.exe /c "\"$PY/" script.py` fails: the `$PY` shell var does NOT carry into the `cmd.exe` subshell, and quote-mangling yields `'...python.exe/"' is not recognized` or `line 3: : command not found`. FIX: (1) run Python directly from the MSYS/bash shell with an absolute path (`"C:/Users/zqmco/AppData/Local/Programs/Python/Python312/python.exe" script.py`) — no `cmd.exe /c`; (2) `cd` to the script's dir first so relative imports/paths resolve; (3) never pipe an f-string here-doc through `cmd.exe /c` — bash eats the quoting (syntax errors near `(`). Write the check as a standalone `.py` file, invoke with the explicit interpreter. This bit a session-history enumerator and a fleet ledger merge before the pattern was pinned.

## Show Real Emitted Output

When the user asks to "run" or "test" a script, they want the program's ACTUAL
EMITTED PAYLOAD (stdout JSON / data / results), not a summary of whether it
compiled or how many unit tests passed. A user correction — "run for the output
of the script, not the compilation" — makes this explicit. Always paste the real
output; keep pass/fail counts secondary. If the script writes files, show the
written content or a representative excerpt. Ad-hoc verification (this skill)
still applies: state what was checked and that it is not suite green.

### Explain the numbers; label computed vs hardcoded

For investigation/audit work the user also wants the emitted numbers explained
in plain language (units, what each value means) and — critically — each result
labeled as GENUINELY COMPUTED or HARDCODED-CONSTANT. A "PASS" on a hardcoded
constant compared to itself is self-fulfilling and must NOT be reported as if it
validated anything. Method (see `references/audit-numbers-method.md`):
- Run every hypothesis/function and dump the real payload.
- Mark each as COMPUTED (real formula) or HARDCODED (constant vs threshold).
- Explain what each number means physically/mathematically, with units.
- Call out decorative fields (e.g. fabricated p_values, literal counts) explicitly.
- Separate real engineering from any narrative/fiction files in the same repo;
  do not let worldbuilding markdown be mistaken for evidence of a working system.

## Cross-User / Hardcoded Absolute Path Workaround

Some repos hardcode an absolute state/output path that does not exist on the
current host (e.g. a different user's `C:\Users\OtherUser\...` dir), so the
script crashes at first write. Do NOT edit the repo to "fix" it for a one-off
verification. Instead run it through a temp harness that monkeypatches the path
constant to a writable temp dir before importing/running:

```python
import sys, tempfile, pathlib
sys.path.insert(0, r"<repo>")
SPINE = tempfile.mkdtemp(prefix="hermes-quantum-spine-")
import runner as rm
rm.SPINE_Z = pathlib.Path(SPINE)
rm.SPINE_LOCAL = pathlib.Path(SPINE)
rt = rm.QuantumTestRunner()
print(rt.run_hypothesis("H1", 1))   # real emitted JSON, repo untouched
```

This lets you observe real output and verify behavior without modifying repo
files. Report that the path was retargeted and why. See
`references/temp-harness-retarget.md` for a fuller template.

## Install & pytest-collection pitfalls (Windows / uv venv)

When the verification task also requires making the repo installable and
collectable by pytest, read `references/install-verify-windows.md`. It covers:
`uv pip install` (no pip in uv venvs), `httpx2` silencing the Starlette
deprecation, `tests/` package wrapping, TrustedHost + TestClient masking,
stdlib `import` shadowing, and SQLite schema self-bootstrap.

## Multi-bug fix verification + recurring bug classes

When one pass fixes several real defects across a repo, use ONE consolidated
temp script that compiles every changed file then runs one behavioral check per
changed file, printing per-step PASS/FAIL and an OVERALL line. Five reusable
bug classes with fix+verify patterns (cross-user hardcoded path, status-key
mismatch, producer/consumer source mismatch, tz-aware vs naive datetime,
`KeyError` on undefined aggregation keys) are catalogued in
`references/ad-hoc-verify-multi-bug.md`.
