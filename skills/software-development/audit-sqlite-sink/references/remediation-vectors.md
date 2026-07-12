# Blocked-Action / Remediation-Vector Diagnosis
When a fix can't be applied, ENUMERATE every execution vector and prove viable vs dead before declaring stuck. Used for "investigate all possibilities".

## Vector checklist (remote + local)
1. SSH (:22) — open? creds?
2. RDP (:3389) — open?
3. WinRM (:5985/:5986) — open? in client TrustedHosts? needs cred.
4. Agent mesh (OpenClaw / ZBit) — does any agent already have a foot on the target? grep config for target IP.
5. Service itself as channel — NEVER fix a vuln through the same unauth service (e.g. CONFIG SET on unauth Redis = the RCE you're closing; non-persistent anyway).
6. Cached creds — `cmdkey /list | findstr <ip>`.
7. Self-run — user executes staged script on target (secret stays off wire). CLEANEST when remote blocked.

## Worked example (N2 Redis CRITICAL, 2026-07-11)
- SSH :22 CLOSED → dead.
- RDP :3389 CLOSED → dead.
- WinRM :5985/:5986 OPEN + N2 in N1 TrustedHosts → VIABLE but needs per-node break-glass cred (NOT reused; N2 pw ≠ N4's; don't re-loop a rejected guess).
- OpenClaw mesh on N1: no 192.168.1.21 ref → dead.
- ZBit agent: lists N2 but holds no fleet creds (.env = ZBIT_API_KEY only) → dead.
- cmdkey: no cached N2 cred → dead.
- Self-run on N2: VIABLE (staged n2_redis_fix.ps1, -WhatIf safe).

## Report shape
Two doors: (1) self-run (zero friction, secret off wire) or (2) pass per-session break-glass for remote WinRM + verify + close finding. Plus list dead paths honestly (SSH/RDP/mesh/agent/cmdkey/redis-self).

Pairs with fleet-council-audit ('investigate all possibilities') + audit-sqlite-sink.
