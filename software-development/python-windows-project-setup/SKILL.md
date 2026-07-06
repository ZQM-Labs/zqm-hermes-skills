---
name: python-windows-project-setup
description: Use when setting up, repairing, or validating a local Python project on Windows. Covers broken venv recovery, dependency installation, Windows service/scheduled-task script hardening, narrowing scan/scrape defaults that otherwise blow up skip counts, and lightweight ad-hoc verification workflows.
---

# Python Windows Project Setup

## Trigger
- The project has no runnable `.venv/Scripts/python.exe` or `pip` is unavailable
- Windows launchers assume a specific Python install path and need to be portable
- Local indexers/scanners default to system paths that inflate skip ratios
- Health endpoints or background jobs need graceful behavior when backend state is absent
- User wants evidence, not speculation, for root causes
- Multiple sibling repos under the same account need the same hardening pass

## Required behavior
1. Recover broken environments by removing and recreating `.venv` with `python -m venv .venv`, not `uv venv .venv`, on Windows.
2. After venv creation, install deps with `.venv\Scripts\pip install -r requirements.txt` and verify `.venv\Scripts\python.exe` imports key dependencies.
3. For Windows service/scheduled-task/bootstrap scripts:
   - never hardcode Python minor-version paths like `Python312`
   - prefer `python.exe` / `pythonw.exe` from PATH, with fallbacks
4. Narrow scan roots to useful coverage and place system/system-like roots into `SKIP_ROOTS` rather than scanning and skipping later.
5. Harden health endpoints to return 200 when backend index/state is missing; never expose server faults for absent optional state.
6. Keep todo items aligned to actual verification state: only mark verification complete after the script exits 0.
7. When the same repo contains mirrored script trees, such as `skills/skills/...` and `skills/...`, harden both trees or they will fail silently on the next launch.

## Verification workflow
- Do not use inline assertion scripts that hit SYNTAX problems; write the verifier to `TEMP` via `tempfile.NamedTemporaryFile` with prefix `hermes-verify-`.
- Run it with the project-local `.venv\Scripts\python.exe`.
- Clean up the temp script after success or failure.
- Label results as ad-hoc verification, not canonical test suite results.

## Pitfalls
- `.venv` created by tools other than `python -m venv` may lack `python.exe` or `pip` on Windows
- Absolute `pythonw.exe` paths in `.ps1`/`.cmd`/`.bat` are unportable and often wrong after installs or migrations
- Default scan roots that include `C:\Windows` or `C:\PerfLogs` guarantee large skip counts with low-value coverage
- `/api/health` and similar endpoints must protect against `NoneType` returns when indexers/backends are absent
- `Get-NetFirewallRule` often returns empty or exit 1 on Windows 10 build 26200 git-bash/ps. Prefer `netsh advfirewall`, `netstat`, or `Get-NetTCPConnection` for firewall/port state.
- Write non-trivial verifiers to TEMP via `tempfile.NamedTemporaryFile` with prefix `hermes-verify-`; do not run large inline Python in shells where quoting expands paths unpredictably.

## Support files
- `references/windows-project-repair.md`: broken-venv recovery, Windows launcher hardening, health fixes, OneDrive/GitHub quirks
