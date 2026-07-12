# ZQM Fleet — Two NEW traps (2026-07-11 addendum)

Appended learnings that the main pitfalls file did not yet cover.
Keep these distinct so they don't collide with zqm-fleet-pitfalls.md edits.

## A. litellm 1.91.2 self-rewrite race
On boot, litellm **rewrites `litellm_config.yaml`** (normalizes/prunes it).
If the proc is SIGTERM'd mid-rewrite (the launching shell/session
exits -> bg procs get reaped, exit 15), the NEXT launch reads a
transient partial file -> `KeyError: 'model'` in `proxy_server.py:load_config`.

Diagnostic order (do NOT blame your own edit):
1. A `KeyError: 'model'` on relaunch is USUALLY not your config edit.
   Validate with `yaml.safe_load` — but note litellm's loader is
   STRICTER than safe_load, so safe_load passing != litellm will load it.
2. Check if a stale instance already holds the port:
   `WinError 10048 only one usage of each socket address` = something IS
   listening on :4001 already. Don't fight it — confirm the live PID.
3. Kill all litellm, confirm port free, relaunch clean.
The 60-line normalized config litellm writes IS valid (4 zbit-* entries);
the KeyError is a transient read of the half-written file, not corruption.

## B. Stray-worktree shadow hazard
Session-created dirs can SHADOW the canonical workspace and silently
break your edits/reads:
- e.g. `C:\Users\zqmco\swarm\zbit-litellm-20260711\` held its OWN
  `litellm_config.integrated.yaml` (350 lines, deepseek/gemma entries),
  `verify_full.py`, `supervise_draft.ps1`, AND a SECOND audit DB
  `fleet_swarm.db` — while the REAL work was in
  `swarm\fleet_endpoint_review\` + `fleet_endpoint_audit.db`.
- A "350-line config" you think you edited may be the WRONG file.
- Two audit DBs drift -> reconcile/dedupe; don't let ledgers diverge.
- Before editing a config, confirm WHICH copy is live (read first lines;
  the canonical zbit config is ~60 lines, zbit-* model_list only).
