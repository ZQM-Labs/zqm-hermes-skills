# Fleet continuous-monitoring operations (ZQM)

Standing fleet monitors write to `swarm/fleet_endpoint_review/fleet_endpoint_audit.db`.
NEVER delete or rename that DB — the 15-min hash-drift cron recomputes drift from
its tables every tick; breaking the schema or the file breaks the monitor.

## Architecture: two independent 15-min monitors, SEPARATE tables
1. **Claim-drift** (Hermes cron job `d7db290059f7`) -> `hash_drift_check.py` ->
   tables `claim_hash` + `hash_drift_log`. Detects: a recorded claim is no longer
   true (re-probes 7 hashable claims: N2 Redis unauth, N1/N2/N4 Ollama, N1
   LiteLLM/ZBit, active anomalous sessions).
2. **Reachability-drift** (Hermes cron job `2bc934334939`) ->
   `scripts/sa_watchdog.py` -> tables `sa_watchdog_log` + `sa_watchdog_state`.
   Detects: a node went dark / a tracked port opened or closed (infra drift,
   independent of the claim ledger).

KEY RULE — a NEW monitor must write to its OWN table(s). Do NOT append to
`claim_hash` / `hash_drift_log`: the existing cron recomputes STABLE/DRIFT counts
from those exact rows and will miscount or corrupt its own history. Create
`sa_watchdog_log`-style tables instead. This is why the watchdog lives in a
separate table even though both monitors target the same DB.

## Watchdog pattern (silent when stable)
The watchdog stores a last-state signature in `sa_watchdog_state` (k='sig').
Each run: probe -> build signature -> compare to stored. Print a line ONLY on a
state-change; print NOTHING when stable. Result: a healthy fleet produces zero
cron output (no noise), and an alert only appears when something actually moves
(node up/down, Ollama/Redis port flip).

## Add / extend a monitor — steps (verified 2026-07-12)
1. Write a READ-ONLY probe (no writes to the fleet; DB log only). Keep the probe
   idempotent and fast (<30s).
2. Point it at its OWN new table(s) in the audit DB (CREATE TABLE IF NOT EXISTS).
3. Register a Hermes cron: schedule `every 15m`, `enabled_toolsets=["terminal","file"]`,
   `deliver="local"`, read-only prompt: "run <full path to script>; print ONLY on
   state change; if it prints nothing, fleet is stable — say nothing back. Do not
   edit anything, do not source credentials. If it errors, report the error."
4. VERIFY before relying on the cron (don't trust registration alone):
   - run the script from its CANONICAL path (the cron calls the full path) and
     confirm it appends a row + exits 0;
   - `cronjob action=list` to confirm the job is scheduled + enabled and DISTINCT
     from existing jobs (avoid duplicate monitors).
5. Patch this skill's SKILL.md to record the new job id + table.

## Pitfalls
- `deliver="local"` output is SAVED, not delivered to the CLI terminal. Don't
  expect to see watchdog alerts inline — query `sa_watchdog_log` to inspect
  history:
    SELECT ts,note,up_nodes,down_nodes,n2_redis,n1_ollama,n4_ollama
    FROM sa_watchdog_log ORDER BY ts DESC LIMIT 10;
- A host DOWN != port closed. Node-2 (.21) is frequently dark; a CRITICAL claim
  on a down host is NOT PROVEN (evidence gap), not FALSE. Keep the ledger item
  OPEN until the host returns and the watchdog flags the state change — only then
  re-verify live.
- Don't park monitor scripts at the home root; the skill's `scripts/` is the
  canonical home so they survive and stay documented. Delete home-root copies to
  avoid drift between duplicate versions.
