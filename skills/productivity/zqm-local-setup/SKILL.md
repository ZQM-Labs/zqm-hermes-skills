---
name: zqm-local-setup
description: "Use when setting up, repairing, or working inside the ZQM Windows homelab. Entry-point skill for Node-1/Node-2 indexers, localhost services, LAN investigation, GitHub workflow, and repo hygiene. Points to the exact local skills and evidence-based workflows instead of generic advice."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [zqm, windows, homelab, setup, indexer, github, lan]
    related_skills: [python-windows-project-setup, networking-tools, localhost-management, windows-lan-investigator, zqm-github-management, zqm-repo-hygiene, github-pr-workflow]
---

# ZQM Local Setup

## Overview

This skill is the entry point for the actual ZQM Windows homelab. It does not duplicate the specialist skills it references. Instead, it loads them in the right order for common ZQM work on `192.168.1.0/24`.

**Topology:**
- Node-1: `192.168.1.218` / `ZQM-Node-1.lan` / MAC `08:9d:f4:aa:d2:82`
- Node-2: `192.168.1.21` / `ZQM-Node-2.lan` / this host
- Default advertised service: NetBIOS/SMB on 139/445

## When to Use

- Starting new work in a ZQM repo
- Repairing a broken `.venv` or service script on Node-1 or Node-2
- Investigating a LAN host on `192.168.1.0/24`
- Managing GitHub repos under `ZQM-Computing`
- Deciding which local skill to load for a given task

## Skill Routing Table

| Task | Load This |
|---|---|
| Broken `.venv`, Python 3.12 hardcoded paths, service bootstrap scripts, `SKIP_ROOTS` tuning | `python-windows-project-setup` |
| Port scanning, ping sweep, traceroute, DNS, HTTP/TCP probes | `networking-tools` |
| Localhost port conflicts, `ERR_CONNECTION_REFUSED`, local server launch | `localhost-management` |
| Full LAN host investigation: identity, ports, SMB, firewall, owner mapping | `windows-lan-investigator` |
- GitHub auth, `gh` CLI, private repo file edits, credential safety | `zqm-github-management` |
| Repo naming, README template, cleanup, commit discipline | `zqm-repo-hygiene` |
| PR workflow, branch strategy, conventional commits | `github-pr-workflow` |

## Standard Order of Operations

### New repo setup or repair

1. Load `python-windows-project-setup`
2. Recreate `.venv` with `python -m venv .venv`
3. Install deps from `requirements.txt`
4. Harden service/bootstrap scripts for dynamic Python resolution
5. Narrow `DEFAULT_SCAN_ROOTS` and put system roots in `SKIP_ROOTS`
6. Harden `/api/health` or equivalent endpoints
7. Commit and push

### LAN investigation

1. Load `networking-tools` for basic reachability
2. Load `windows-lan-investigator` for the full evidence chain
3. Load `localhost-management` if the investigation is from the target host itself

### GitHub hygiene

1. Load `zqm-github-management` for auth/credentials
2. Load `zqm-repo-hygiene` for cleanup/README/branch standards
3. Load `github-pr-workflow` for the actual PR mechanics

## Environment Facts

- Python: `3.11.15`
- `git`: `2.54.0.windows.1`
- `gh`: `2.96.0` at `C:\Program Files\GitHub CLI\gh.exe`
- `npm`/`uv`/`pip` may have quirks; prefer `python -m venv .venv` then `.venv\Scripts\pip`
- OneDrive can lock `.git/index.lock`; expect occasional resolution
- `Get-NetFirewallRule` is unreliable; prefer `netsh advfirewall`
- `tasklist /FO TSV` is invalid; use `/FO CSV` or `/FO LIST`
- `ripgrep 15.1.0` is installed at the winget path

## Common ZQM Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| Service bootstrap fails on launch | Hardcoded `Python312` path | Dynamic `python.exe` lookup; see `python-windows-project-setup` |
- Index scan skips nearly everything | `DEFAULT_SCAN_ROOTS` includes `C:\Windows` / `C:\PerfLogs` | Narrow roots; move system paths to `SKIP_ROOTS` |
| `/api/health` returns 500 without index | `NoneType` from missing Whoosh index | Harden endpoint to return 200 for absent optional state |
| `git push` exits 128 | Credential helper broken/absent | `gh auth git-credential` + `credential.helper manager-core` |
| Port 5000 refused / no process | Indexer not started or `.venv` broken | Verify `.venv\Scripts\python.exe` exists; rebuild if needed |
| `.git/index.lock` after OneDrive sync | OneDrive file locking | Remove lock, retry git command |

## Notes

- This skill exists to load the right specialist skill faster. It does not replace them.
- If a local skill is missing, check `C:\Users\zqmco\AppData\Local\hermes\skills\`.
- For canonical repo management patterns, also load `github-repo-management`.

## Housekeeping / Archival Policy

These installed skills are not relevant to this Windows/ZQM environment. Prefer not loading them:

- `apple/*` — macOS only
- `social-media/xurl` — X/Twitter CLI workflow; not used here
- `research/research-paper-writing` — academic MLOps workflow; heavy and detached
- `media/*` — GIF, YouTube, audio tools; not part of ZQM work
- `smart-home/*` — no smart-home stack in this environment
- `yuanbao` — unrelated group chat integration
- `creative/*` — design/animation tools; not part of the current workflow
- `mlops/*` — GPU-first model serving/eval; not present on this host

Delete or archive only after confirming they are not referenced by other skills. If unsure, leave them installed but do not load them.
