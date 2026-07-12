---
name: bounty-hub-verify
description: "Ad-hoc verification workflow for zqm-bounty-hub bounty automation: compiles, imports, runs scorer/opportunity alerts/pipeline against mock cache, watches HackerOne auth, and self-reschedules on Windows."
version: 0.4.0
author: ZQM Computing
license: MIT
category: zqm-bounty-hub
tags: [bounty, verification, h1, cache, watchdog, upstream]
metadata:
  hermes:
    tags: [bounty, verification, h1, cache, watchdog, upstream]
required_commands: []
required_environment_variables: []
missing_required_environment_variables: []
missing_required_commands: []
setup_needed: false
setup_skipped: false
readiness_status: available
linked_files:
  - references/watchdog-lessons.md
  - references/cron-repeat-bug.md
  - references/verification-checklist.md
  - references/upstream-state.md
  - scripts/verify_upstream.py
---

# bounty-hub-verify

Ad-hoc verification workflow for `zqm-bounty-hub`.

## Usage

Run watchdog locally from git-bash:

```bash
cd /c/Users/zqmco/AppData/Local/hermes/skills/zqm-bounty-hub/scripts
python hub_verify_watchdog.py
```

Run upstream probe:

```bash
cd /c/Users/zqmco/AppData/Local/hermes/skills/zqm-bounty-hub
python scripts/verify_upstream.py
```

Supporting material:
- `references/watchdog-lessons.md` — cron recurrence bug, preferred Python path, verifier cleanup rules.
- `references/cron-repeat-bug.md` — exact traceback and fix.
- `references/verification-checklist.md` — canonical list-style checklist.
- `references/upstream-state.md` — exact 2026-07-09 upstream diagnosis.
- `references/node-01-rebuild-fix.md` — rebuild flag fix, stale Whoosh lock path, safe cleanup and retry steps.
- `scripts/verify_upstream.py` — deterministic one-shot probe for local + remote indexers, ComfyUI, FastAPI, Ollama.

## Upstream state probe

Run `python scripts/verify_upstream.py` from the skill directory. This is the authoritative check for whether `zqm-bounty-hub` can actually fetch or score live data.

Important interpretation rules:
- TCP open + HTTP 200 on `/` or `/api/health` => service up.
- For `192.168.1.218:5000`: even when reachable, the indexer may bind to `127.0.0.1:5000` only. A remote LAN probe returning "down" while localhost returns 200 means bound-local, not offline.
- `ConnectionRefused` on a known port means no listener; it is not a firewall-blocked-but-running service.
- A first-run indexer config with `total_files: 0` and `root_skip_unchanged` > 0 means literally no content indexed yet; treat as data-empty, not service-down.
- Node-02 at `192.168.1.21:5000` 100% packet loss = host offline, not just service down.
- ComfyUI logs may show "Starting server" followed by `Error handling request` with no Python traceback; treat that as listener down / runtime hook failure, not a normal degraded mode.
- The Node-01 indexer config path is `C:\Users\zqmco\.zqm-node-01-indexer\config.json`; `.venv` may not exist there. The active checked-out indexer may live under `C:\Users\zqmco\Documents\zqm-node-01-indexer\`.

## Lessons learned

- Cron recurrence on this Hermes build fails when `repeat: forever` is paired with `schedule: "every 60m"` or `every ...`
- Verify `run_once()` directly; running watchdog `main()` in harnesses causes timeout behavior
- HackerOne auth should prefer cached token file at `~/.local/share/hermes/h1_token`
- Ad-hoc verifier temp files should be created under `C:\Users\zqmco\AppData\Local\Temp` and cleaned up
- `/health` is the canonical FastAPI health path; `/` often 404s.
- Debug upstream with ping / port probes / HTTP health checks only; don't infer remote LAN state from local TCP scans.
- When distilling triage conclusions, always quote the exact symptom string from logs or config, not an inference (e.g., `root_skip_unchanged: 4`, not stale timeout).
