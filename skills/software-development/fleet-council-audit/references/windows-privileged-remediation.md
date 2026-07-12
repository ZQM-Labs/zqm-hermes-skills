# Windows privileged remediation — elevation patterns (ZQM fleet)
Use when a council/audit finds a fix that needs admin PowerShell on a Windows node
(disk mount, firewall rule, service change). The agent shell here is NON-elevated.

## The RunAs gotcha (learned the hard way)
`Start-Process powershell -Verb RunAs -Wait -ArgumentList "..."` does NOT surface a
UAC denial as an error. If the user clicks No (or UAC is filtered), the call still
returns exit 0 and prints "process returned". The launched script's stdout is NOT
returned to the parent shell. So you CANNOT tell success from denial unless the script
self-logs.

### Safe pattern
1. Write the remediation as a `.ps1` that wraps the real action in try/catch and
   `Set-Content`s a result file (e.g. `mount_result.log` / `rec2_result.log`).
2. Launch: `Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`""`
3. After launch, READ the result log AND independently re-verify the actual system
   state (e.g. `Get-Volume -DriveLetter D`, `Get-NetFirewallRule -DisplayName X`).
   Trust the live state, not the log, not "process returned".

## Reusable templates
- templates/mount_disk.ps1 — mount a partition as a drive letter (Set-Partition;
  handles the [char]0 "no letter" case correctly).
- templates/ollama_fw_rule.ps1 — add a scoped inbound ALLOW for Ollama :11434 from
  the trusted /24 (replaces implicit openness with an explicit, LAN-scoped rule).

## Consent gate
- NEVER auto-elevate without explicit user go-ahead. A clarify timeout -> safe default
  is to NOT elevate and instead hand the command.
- Once the user says 'proceed' / 'B' / 'all of the above', attempt RunAs with the
  self-logging scripts above. The user WILL grant UAC; they want action, not a hand-off.

## Other privilege notes
- `Set-Partition -NewDriveLetter` / `Add-PartitionAccessPath` need admin (throw
  `Access denied` / `CIM resource not available` non-elevated).
- `New-NetFirewallRule` needs admin.
- `Get-Partition.DriveLetter` is `[char]`: unmounted returns `'\\0'` (null), so
  `[string]::IsNullOrEmpty()` mis-fires — test with
  `IsNullOrWhiteSpace($_.DriveLetter.ToString())` or `$_ -eq [char]0`.
