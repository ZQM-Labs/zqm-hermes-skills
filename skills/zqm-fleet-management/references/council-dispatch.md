# ZQM Deep-Audit Council — dispatch recipe

Use when the user says "investigate fully" / "audit" / "census the fleet" / "with the councils".
Pattern: dispatch 3+ PARALLEL leaf `delegate_task` agents, then the LEAD re-verifies the
headline numbers LIVE before merging. Subagent summaries are SELF-REPORTS, not facts.

## Dispatch (delegate_task, `tasks` array)
The `tasks` batch runs in the BACKGROUND and returns ONE combined message when ALL leaves
finish — do not poll; keep working. Give each leaf a SELF-CONTAINED `context`: pass every
fact it needs (node IPs, cred-handling rules, prior claims to reconcile). The single biggest
failure mode is a leaf repeating the agent's own PowerShell-from-bash pitfalls, so EVERY
leaf `context` MUST open with this preamble verbatim:

> Terminal is bash (MSYS/git-bash), NOT PowerShell/cmd. CRITICAL: MSYS expands `$_` / `$var`
> before PowerShell sees it — inline `powershell -Command "… $_.x …"` becomes garbage. ALWAYS
> write the probe to a `.ps1` and run `powershell -NoProfile -ExecutionPolicy Bypass -File
> <path>` (forward-slash or cmd.exe-wrapped path; see pitfall #6/#20). `wmic` is REMOVED in
> Win11 24H2 (build 26200) — use Get-CimInstance. For real GPU VRAM use `nvidia-smi` (WMI
> AdapterRAM under-reports). The agent sandbox CAN reach 192.168.1.0/24 (curl /api/tags etc.)
> — probe live, don't trust pasted/Cline output. Do NOT use clarify. Return verifiable numbers
> + plain-language meaning; if a probe fails, say so, don't fabricate.

## Suggested 3-slice split for a full fleet/workstation audit
- Agent A — Security & Services: running-service inventory (grouped), WinRM listener config
  + sshd + firewall rule audit (11434/22/5985/5986), startup tasks, Defender + DiagTrack,
  listening-port census (Get-NetTCPConnection / netstat -ano).
- Agent B — Capability/Perf (or fleet service census, e.g. Ollama): reachability + model/size
  + /api/generate health per node; reconcile vs prior claims labeled PROVEN / NOT PROVEN / FALSE.
- Agent C — Storage/Shares/Topology: physical disks + every volume (find unmounted big disks
  like the 4TB SN850X), SMB shares incl. `\\ZQM-Garden-01\web` (native-PS write only), adapters/
  IP/DNS, /24 live-host scan, routing table.

## LEAD re-verification (mandatory quality gate)
Before merging the final report, the lead independently re-probes the headline numbers live
(curl /api/version, /api/ps, version currency via GitHub releases API NOT web_search, a port
scan, a key nvidia-smi). Reject any leaf claim that fails the re-check (stale version,
fabricated size, wrong reachability). Label each headline PROVEN / NOT PROVEN / FALSE.

## Notes
- 3 leaves is the sweet spot; more floods context. Each leaf is isolated (own terminal session).
- Timestamp dynamic state (/api/ps, top-processes) — it changes between probes.
- This recipe complements pitfall #20 (bash `$_` expansion) and the local-host-inventory /
  ollama-* references. The council is the user's stated preferred audit style (2026-07-10).
