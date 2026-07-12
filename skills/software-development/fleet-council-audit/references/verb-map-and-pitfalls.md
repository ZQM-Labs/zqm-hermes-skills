# fleet-council-audit — verb map + tooling pitfalls (session-learned)

## Recurring user verbs → method (encode, don't re-derive each session)
The user fires these as standing directives; each maps to the council+lead shape:
- "investigate fully" / "audit this box/fleet" → full 3-layer (process/service/security) + parallel leaves + LEAD re-verify + SQLite persist.
- "investigate all three layers" / "full endpoint review" → the 3-layer sweep specifically (L1 process, L2 service/network, L3 security/C2).
- "hash claims" / "investigate genesis hash drifts" → recompute SHA-256 of every claim from LIVE re-probe, compare to ledger, flag drift. Genesis = root-cause WHY each state exists (by-design vs accidental vs OS-default).
- "diagnostics" → read-only recon for ACTIVE faults (who's connected NOW, not just config state).
- "study patterns" → mine gathered data for RECURRING vs ONE-OFF (timing regularities, clustered failures, drift cadence). Separates "chronic problem" from "one-off event".
- "improve the reliability of the garden" → resilience posture: auto-start on boot, service crash-recovery, SPOF/cross-node dependency, failover. Apply safe local fixes; gate credential/elevation ones.
Map every such verb to a concrete method BEFORE acting.

## Pitfalls: re-verify YOUR OWN tooling, not just the target
The council/ledger discipline only holds if the verifier is correct. This session shipped two self-inflicted false "verified" claims:
1. Hash-drift checker used `b"model" in body` but LiteLLM returns `"id":` → mis-flagged a healthy service as DRIFT. And a summary line did `"FOUND" in "TASK_NOT_FOUND"` (substring) → printed YES when it meant NO. Fix: match on `.startswith()` / exact tokens, never `in` on a negated string.
2. Relaunching a venv console-script EXE: `python.exe litellm.exe` → `ModuleNotFoundError: No module named 'litellm'`. `litellm.exe` is a self-bootstrapping PE — run it DIRECTLY (`start litellm.exe --args`), never as a python arg. And git-bash `start /min "title" "exe" --args` detaches-and-dies (subshell exits). For persistent Windows services from this terminal use `terminal(background=true)`, or PowerShell `Start-Process -FilePath $exe -ArgumentList ... -WorkingDirectory ...`.
Rule: after any edit/relaunch, run a fresh ad-hoc re-probe of the ACTUAL behavior (port listening? endpoint returns? config parses?) before claiming verified. See workspace-verification-status for the hermes-verify- temp-script pattern.

## Elevation gates are BLOCKERS, not failures
Scheduled-task creation, service-recovery changes, and remote-node fixes need elevation (UAC) or per-node break-glass creds. Background shell cannot surface the UAC prompt. When blocked: apply what's local/reversible, stage the gated step as a one-line runnable script, and hand the user the exact command to finish — do NOT loop guessing creds, and do NOT claim the gated item is done. The ZQM break-glass creds are PER-NODE and differ; N2's is NOT the N1 rejected password.
