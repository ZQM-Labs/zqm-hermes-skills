# Stability Diagnostic & Hardening (ZQM Windows fleet)
Read-only first; stage fixes; apply only on explicit consent / elevation.

## Read-only diagnostic probes
- Crash/reboot: `Get-EventLog -LogName System -EntryType Error -Newest 10` → "was unexpected" + "Service ... terminated unexpectedly".
- Service flapping: same log, filter sshd/OpenSSH.
- Restart-loop: `Get-CimInstance Win32_Process -Filter "ProcessId=..."` → StartTime.
- Disk headroom: `Get-PSDrive C | Select Used,Free`.
- App errors: tail service log (litellm.log); `grep -cEi "traceback|exception|error"`.
- Live sessions on exposed ports: `netstat -ano | grep ESTABLISHED | grep -E ":11434|:4001|:8400|:5985|:445|:135|:6379"`.

## Fixes applied (reusable shapes)
1. sshd auto-restart on crash (no security change): `sc.exe failure sshd reset= 86400 actions= restart/1000/restart/1000/restart/1000`. Verify: `(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\sshd' -Name FailureActions).FailureActions -ne $null`.
2. Stack autostart on boot (self-heal after crash/reboot): scheduled task AtStartup running a .bat that starts litellm then zbit (loopback). `Register-ScheduledTask` NEEDS ELEVATION. Self-elevate wrapper:
   `if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')){ Start-Process powershell -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File \`"$script\`""); exit }`
   Background/non-stealing mode cannot surface the UAC prompt → task creation silently fails ("Access is denied"). Fallback: user runs script As Administrator.
3. Monitoring cron (read-only, no elevation): `cronjob` every 15m running hash_drift_check.py + diagnostics.py; flag URGENT on any DRIFT / new external session. (local-only; output to cron log.)
4. litellm timeout loop (zbit-heavy 120s APITimeoutError, no fallback): add fallback deployment + lower timeout in litellm_config.yaml, restart litellm. Needs consent (behavior change + brief interrupt).

## Pitfalls
- `Get-EventLog -LogName System,Application` (array) → ParameterBinding error; loop per-log.
- bash `$_` in `Where-Object { $_.X -match ... }` expanded by git-bash before PowerShell → write a .ps1 and run `-File`.
- `Register-ScheduledTask` from non-elevated shell → "Access is denied" though processes run elevated; use UAC self-elevate or run As Admin.
- Ad-hoc verifier substring trap: `"FOUND" in "TASK_NOT_FOUND"` → True (false positive). Use `.startswith("TASK_FOUND")` / exact match.

Pairs with audit-sqlite-sink (persist F-findings + re-hash) and windows-host-audit §2d. Pairs with fleet-council-audit for the "diagnostics / improve systems stability" directive.
