# User Command-Gating & Operating Protocol (ZQM fleet audits)

Operating rules confirmed with this user during "investigate fully" / remediation
passes (2026-07-11). Companion to windows-privileged-remediation.md.

## 1. The user ACTIVELY GATES commands — STOP on BLOCKED
- If a tool call returns `BLOCKED: User denied` (or any denial), STOP the
  workflow immediately. Do NOT retry, rephrase, or reach the same outcome
  via a different command. Surface the gate and wait for direction.
- Seen: a `netstat` + `Get-CimInstance` + `curl` re-probe sweep was
  denied. Correct response = halt, state what was blocked, offer the user
  a choice (re-approve / new scope / different target). NOT a workaround.

## 2. Defeatism reframe
- If the user says "we're dead in the water" (or similar), do NOT agree.
  Split the picture: (a) DONE deliverables that are persisted/verified,
  vs (b) the SINGLE gated blocker. State both explicitly.
- The investigation is rarely actually blocked — only one optional apply-step
  is. Reframing shows the user the work that IS finished.

## 3. Apply-safe vs Gate split ("improve / remediate")
Autonomously APPLY (local, reversible, no exposure change, no creds):
- Service recovery actions (`sc.exe failure <svc> actions=restart/...`).
- Read-only monitoring (cron jobs that probe + log, never modify).
- Launcher / config scripts written to disk (not yet invoked).
GATE (explicit user action required): creds (per-node break-glass),
elevation (scheduled-task creation, service creation), exposure-changing
(firewall, bind changes, port open/close to LAN). See
windows-privileged-remediation.md for the UAC blind-spot.

## 4. Substring-assertion bug in verify summaries
- `"FOUND" in "TASK_NOT_FOUND"` is True (substring, not word match).
  A summary line `log("applied: %s" % ("YES" if "FOUND" in out else "NO"))`
  printed "YES" for a task that was NOT created.
- FIX: assert on EXACT anchors — `out.strip().startswith("TASK_FOUND")`
  or `out.strip() == "NOT_FOUND"`. Re-run the verify after fixing and
  confirm the corrected result. (workspace-verification-status covers this too.)
