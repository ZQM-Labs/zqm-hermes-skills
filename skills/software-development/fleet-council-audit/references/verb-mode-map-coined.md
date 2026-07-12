# Coined verb → mode map (NEW 2026-07-11)
Supplement to the VERB→MODE MAP in SKILL.md. These four verbs were coined by the user mid-session and are NOT yet in the main map. They are typo-tolerant ("investigate fully" etc.) and each maps to a DISTINCT behavior — do NOT ask, just execute the right mode.

## "investigate all three layers"
LEAD-only THREE-LAYER sweep of a known co-located stack on ONE box (≤3 services) — do NOT fan out.
Layers: L1 PROCESS (PID, cmdline, parent-chain, owner via Invoke-CimMethod GetOwner, elevation via C# TokenElevation class 18: 1=admin,0=std,-1=no-access; launch origin explorer→cmd=MANUAL, Get-ScheduledTask=NONE), L2 SERVICE (netstat LISTEN bind, live HTTP auth matrix: open + no-key + bogus-key + valid-key + POST-write-verified-on-disk), L3 SECURITY (C2 egress test scoped by -OwningProcess to the TARGET PIDs, plus source review). Persist ONE consolidated SQLite ledger (run_meta / process_layer / net / service_probe / verdict). Re-verify every claim live before INSERT.
ZBit-stack result (live 2026-07-11): both PIDs elev=1 (admin token), manual desktop launch, loopback-only, zero external egress → C2=FALSE.

## "investigate all possibilities"
REMEDIATION-PATH ENUMERATION. Before applying any fix, list EVERY execution vector and PROVE each viable vs BLOCKED live:
- SSH (filtered=dead), RDP (filtered=dead), WinRM (open + in TrustedHosts = viable w/ cred), mesh-agent (no ref to target = dead), the-vulnerable-service-itself (that IS the RCE — reject, do NOT "fix via the unauth channel"), cached-cred (cmdkey, none = dead), self-run (viable, secret never crosses wire).
End with a 2-door summary (self-run vs credentialed-remote). Do NOT guess passwords or re-loop a rejected one (per-node creds differ).

## "diagnostics and learn more"
SILENT re-sweep + ROOT-CAUSE DEEPEN of an already-surfaced anomaly. Re-confirm state (processes stable? active sessions? hash-drift 0?), then DIG into WHY:
- Shutdown/power-off: EventLog 1074 (winlogon / NT AUTHORITY\SYSTEM / reason 0x500ff / "power off") + 41 (Kernel-Power, dirty-power-off artifact) + 6008 ("was unexpected") = SYSTEM-context HARD POWER-OFF, not BSOD/crash (no bugcheck, no App errors). Security log needs elevation to read the precise initiator — flag UNCONFIRMED, don't guess.
- litellm timeout: config `zbit-heavy` → model on a node; if NO per-deployment `timeout:` set, LiteLLM's DEFAULT 120s applies ("request_timeout: None / timeout: None / time taken=120.0"). Confirm the target model is EVICTED via `/api/ps` (cold-load >120s = the stall). NO fallback ("Model Group Fallbacks=None") → hard fail. Fix = add `timeout:` + a fallback, or pin the model (raise keep_alive).
Persist `root_cause` to the ledger. DISTINCT from "diagnostics and forensic science" (pre-remediation evidence) — this is post-finding learning.

## "hash claims, investigate genesis" / "investigate genesis hash drifts"
GENESIS LENS = classify each anomaly as BY-DESIGN vs ACCIDENTAL-DRIFT. This reframes remediation priority:
- Ollama LAN-exposure = BY-DESIGN (ZBit fleet LB fabric per config: N1/N2/N4 = LAN, N3 = localhost). Not a bug.
- N2 Redis unauth = ACCIDENTAL-DRIFT (default config: no requirepass + bound non-loopback; protected-mode drops its guard once bind-non-loopback+no-pass). The ONE true mistake.
- WinRM-HTTP :5985 = OS default. LiteLLM/ZBit open docs = framework default, loopback-only.
The drift check: recompute SHA-256 of each claim from a FRESH live re-probe (not memory), compare to stored hashes. A false DRIFT flag = checker bug (truncated recv / wrong substring), NOT state change — fix the matcher, re-run. Ledger `claims` table + `hash_drift_log` (timestamped stable/drift counts) = tamper-evident.
Genesis split separates the 1 real error (Redis) from intended/OS-default states → close the drift, draft auth-proxy for the design.
