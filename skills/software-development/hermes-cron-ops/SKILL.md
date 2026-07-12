---
name: hermes-cron-ops
description: 'Operate Hermes local cron jobs from the agent: list, create, verify,
  and manage scheduled tasks. Covers the local-only delivery caveat (output saved,
  NOT delivered to this CLI session unless deliver targets a gateway platform), the
  watchdog pattern (no_agent=true scripts that stay quiet when nothing to report),
  and the verify-after-create step. Use when scheduling recurring probes, audits,
  or watchdogs, or when the user asks about their cron jobs.'
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - hermes
    - cron
    - scheduler
    - watchdog
    - automation
    related_skills:
    - audit-sqlite-sink
    - fleet-council-audit
    - homelab-backup
    - windows-host-audit
    - zqm-fleet-management
    - zqm-local-setup
    - zqm-ollama-fleet
    - zqm-systems-review
---
# Hermes Cron Ops

## When to use
- Schedule a recurring fleet probe, audit, backup, or watchdog.
- "What cron jobs do I have?", "add a daily Ollama health check", "verify the job ran".
- Reasoning about cron delivery (will I get the output in this terminal?).

## KEY CAVEAT — local-only delivery
Cron jobs scheduled from a CLI session are LOCAL-ONLY. Their output is saved (viewable
via `cronjob action='list'`) but is NOT delivered back into this terminal — there is no
live-delivery channel here. If the user wants to be NOTIFIED when a job runs, the job's
`deliver` must target a gateway-connected platform (e.g. `deliver='telegram'` or `'all'`).
Do NOT promise a `deliver='origin'` / default-deliver job will message them in-session.

## Create pattern
```json
cronjob action='create'
  schedule='0 9 * * *'        // or '30m', 'every 2h', ISO timestamp
  prompt='<self-contained instructions>'   // jobs run with NO current-chat context
  name='daily-ollama-health'  // optional
  deliver='telegram'          // only if cross-platform notify is wanted
```
Prompt MUST be self-contained — it gets no conversation history. If it needs a skill,
pass `skills=['ollama-recovery', ...]`.

## Watchdog pattern (no_agent=true)
For recurring script-only pings (health/watch/threshold): set `no_agent=true` and point
`script` at a file. The script's stdout is delivered verbatim; EMPTY stdout = silent
(nothing sent). Design the script to stay quiet when there's nothing to report:
```bash
# script returns non-zero / prints only on anomaly
python generate_health.py 192.168.1.215 || echo "Node-4 generate HANG — recover"
```
Non-zero exit / timeout sends an error alert so a broken watchdog can't fail silently.

## Verify after create
List to get the `job_id` (never guess IDs), then check it exists and is scheduled:
```json
cronjob action='list'
```
For one-shot verification, `action='run'` forces an immediate execution; then
`action='list'` shows last-run state. Pair with the job's own health output.

## Chaining jobs
`context_from=[job_id,...]` injects a prior job's most recent completed output into the
next job's prompt — e.g. a collector job feeds an analyzer. Injects latest output; does
NOT wait for upstream in the same tick.

## Pitfalls
- Writing a prompt that assumes chat context — jobs are context-free; inline everything.
- Expecting in-terminal delivery from a default-deliver job — it won't arrive here.
- Forgetting `notify_on_complete` only matters for background terminal processes, not
  cron; cron uses `deliver`.
- Recursive scheduling (a cron run scheduling more cron) is HARD-BLOCKED — don't try.

## References
- ollama-recovery (what a health watchdog calls)
- homelab-backup (schedule recurring backups)
- audit-sqlite-sink (a scheduled audit writes to the DB)
