---
name: homelab-backup
description: Snapshot/restore discipline for the ZQM homelab — the 4 Windows nodes
  (Node-1 .218 / Node-2 .21 / Node-3 .46 / Node-4 .215), the Synology 'Garden' NAS
  (DSM), and the TerraMaster TOS box. Covers what to back up (repos, skills, config
  state, credentials stores), the NAS as the backup target, rotation, and a pre-restore
  verification step. Use when the user wants DR coverage, a scheduled backup, or to
  restore a node/NAS share.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - homelab
    - backup
    - dr
    - synology
    - terraMaster
    - nas
    - restore
    related_skills:
    - fleet-council-audit
    - synology-dsm-management
    - windows-host-audit
    - zqm-fleet-management
    - zqm-local-setup
    - zqm-systems-review
---
# Homelab Backup & Restore (ZQM)

## When to use
- "Back up the fleet", "set up DR", "snapshot the NAS", "what happens if Node-4 dies".
- Restoring a node's repos/config after a failure.
- Scheduling recurring backups (pair with hermes-cron-ops).

## Backup targets (what matters)
- **Repos** — `C:\Users\zqmco\...\repos\*` and `zqm-hermes-skills` (the skill source
  of truth is `AppData\Local\hermes\skills`; the duplicate trees under `.hermes/`,
  `.zqm-auth/`, `zqm-hermes-skills` are NOT authoritative — back the real one, dedup
  the rest).
- **Agent state** — `~/.zqm-auth/` (creds store, DPAPI), `~/.zqm-data/<user>/` (per-user
  state.db WAL), `~/.openclaw/openclaw.json` + `devices/paired.json` (gateway config —
  contains PLAINTEXT tokens; handle as secret, never print).
- **Fleet config** — LiteLLM `litellm_config.yaml`, Ollama `OLLAMA_MODELS`/env,
  firewall rules, Scheduled Tasks (`OpenClaw Gateway`, indexer launchers).
- **NAS** — Synology Garden shares (`web/`, etc.) and TerraMaster TOS volumes.

## Strategy
1. Push important source (repos, skills) to GitHub PRIVATE (zqm-repo-inventory-verification)
   as the off-box copy — cheaper than shipping tarballs.
2. Use the Synology NAS as the on-LAN backup target for node state/creds (DSM shares via
   SMB; see synology-dsm-management for API/auth). TerraMaster as secondary cold copy.
3. Rotation: keep 7 daily / 4 weekly / 3 monthly snapshots. Prune oldest.

## Backup (node → NAS, via SMB)
```powershell
# robust copy to a Garden share — native Copy-Item, NOT agent write_file (which
# SILENTLY FAILS on \\ZQM-Garden-01\web\ — known trap). Hand via -File, not -command.
$src = "C:\Users\zqmco\AppData\Local\hermes\skills"
$dst = "\\ZQM-Garden-01\backups\hermes-skills\$(Get-Date -Format yyyyMMdd)"
Copy-Item -Recurse -Force $src $dst
```
Use `powershell -NoProfile -ExecutionPolicy Bypass -File <script.ps1>` (NOT `-command`)
for any SMB write — the agent's `write_file` can't reach the NAS share.

## Restore (verify before trusting)
1. List the snapshot set on the NAS; pick by date.
2. Restore to a STAGING path first; diff against current to confirm what changed.
3. Only overwrite live state after the user confirms. Re-verify the service boots
   (e.g. restart Ollama / the indexer) and re-probe health.

## Pre-backup verification
- Confirm NAS reachability + share mount BEFORE copying (a silent SMB fail loses the
  backup). `Test-Path \\ZQM-Garden-01\backups` first.
- Confirm creds store is DPAPI-intact (windows-secure-credential-handoff) — a backed-up
  but undecryptable cred is worthless.

## Pitfalls
- Backing the duplicate `.hermes/`/`.zqm-auth/` skill trees instead of the real
  `AppData\Local\hermes\skills` → restoring stale/divergent skills.
- `write_file` to `\\ZQM-Garden-01\web\` SILENTLY FAILS — use native PS Copy-Item.
- Printing `~/.openclaw/*` tokens or `~/.zqm-auth/` contents into a backup report.
- Assuming GitHub is a backup for secrets — it is NOT; creds stay on the NAS/box.

## References
- synology-dsm-management (NAS API/auth)
- windows-secure-credential-handoff (DPAPI cred store)
- zqm-local-setup (what lives where on each node)
