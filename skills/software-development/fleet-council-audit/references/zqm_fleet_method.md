# ZQM Fleet Audit — Claims, Verification & Reliability (companion to fleet-council-audit)

## Verb→method (user-coined, stable)
- investigate fully → council leaves + LEAD live re-verify → SQLite ledger.
- hash claims → SHA-256(claim+"|"+status) in `claim_hash`; re-probe LIVE, recompute, flag DRIFT. Never trust ledger.
- study patterns → mine RECURRING vs ONE-OFF (timing/frequency/correlation).
- diagnostics and learn more → silent re-sweep + ROOT-CAUSE of each anomaly (WHY).
- improve the reliability of the garden → fault-tolerance/self-heal (autostart, svc recovery, inference failover). "garden"=ZQM fleet N1-N4.

## Ad-hoc verification (MANDATORY after any fleet code/config edit)
- System flags unverified edits. Write `%TEMP%/hermes-verify-*.py`, run vs LIVE behavior, report "ad-hoc, not suite green", then delete.
- Trap avoided: don't claim "applied+verified" until the PROCESS IS LISTENING + endpoint returns expected HTTP code (command-exit-0 ≠ working).
- Re-verify negatives with authoritative method (curl GET not bare socket.recv; HTTP probe not short-timeout ping).

## litellm launch (N1) — gotcha
- `venv\Scripts\litellm.exe` is a SELF-BOOTSTRAPPING PE. RUN DIRECTLY:
  `litellm.exe --config litellm_config.yaml --host 127.0.0.1 --port 4001`
- WRONG (ModuleNotFoundError): `python.exe litellm.exe` or `python -m litellm` (no __main__).
- Persistent launch from this terminal: `terminal(background=true)` with direct exe. `start cmd /c` from git-bash mangles paths/quotes.
- After config edit: relaunch, verify :4001 LISTENING + /v1/models returns virtual models (zbit-router/fast/heavy).

## Garden reliability checklist
- Boot autostart: only Ollama.lnk + OpenClaw task exist; ZBit/LiteLLM DON'T self-heal → add AtStartup scheduled task (NEEDS ELEVATED UAC; bg can't surface prompt).
- Svc recovery: `sc.exe failure <svc> restart=3` (ssh/WinRM/LanmanServer).
- Inference SPOF: LiteLLM routes 3/4 to N2. Add `model_group_fallback:[zbit-fast]` + `timeout:45` to zbit-heavy (avoid 120s default hang on cold load).
- N2 Redis UNAUTH = CRITICAL RCE + reliability hazard (LAN FLUSHALL). Needs N2 break-glass cred.
- N3 Ollama localhost-bound by design (not redundancy unless exposed — sec tradeoff).

## Cred/gate rules
- Per-node break-glass pw DIFFER; don't guess (N2 ≠ N1). One retry proves it.
- Background can't surface UAC → user runs elevated scripts manually.
- Loopback-only svc = low risk; external egress on exposed ports = investigate.
