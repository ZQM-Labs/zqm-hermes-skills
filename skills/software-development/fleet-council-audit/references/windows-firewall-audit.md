# Windows Firewall audit — fast + correct method (learned 2026-07-11)

## The trap (do NOT do this)
Enumerating firewall rules by piping the rule cmdlet into the port-filter cmdlet is
pathologically slow on a box with hundreds of rules, and a naive port join produces
**FALSE "no rule" results**:

```powershell
# SLOW (timed out at 120s on Node-1) + buggy:
Get-NetFirewallRule | Where-Object {
    (Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_).LocalPort -contains $p
}
```
Root causes:
- `Get-NetFirewallPortFilter -AssociatedNetFirewallRule` re-opens per rule → O(rules²)-ish.
  Node-1 has thousands of FW rules; this hangs.
- Building a `$byPort` map by iterating every port-filter and doing `-contains`
  produced an empty join for ports that DO have rules → my first audit wrongly said
  "Port 22/5985/5986/11434: NO firewall rule". The netsh parse below proved those
  rules exist. **Never trust a PowerShell "no rule" from this pattern.**

## The fix — `netsh` dump + parse (fast, ~5-10s, authoritative)
```powershell
netsh advfirewall firewall show rule name=all dir=in verbose > fw.txt
```
Then parse blocks in PowerShell (the canonical block split):
```powershell
$blocks = (Get-Content fw.txt -Raw) -split '(?m)^Rule Name:\s*'
foreach ($b in $blocks) {
    $lines = $b -split "`r?`n"
    $name = $lines[0].Trim()
    $port = ($lines | Where-Object { $_ -match 'LocalPort\s*:\s*(.+)' } |
             ForEach-Object { $Matches[1].Trim() }) -join ','
    $action  = if ($b -match 'Action\s*:\s*(.+)')    { $Matches[1].Trim() }
    $enabled = if ($b -match 'Enabled\s*:\s*(.+)')   { $Matches[1].Trim() }   # Yes/No
    $dir     = if ($b -match 'Direction\s*:\s*(.+)') { $Matches[1].Trim() }
    $profile = if ($b -match 'Profiles\s*:\s*(.+)')  { $Matches[1].Trim() }
}
```
Then for each audit port, an ALLOW rule = `Action=Allow` AND `Enabled=Yes`.

## Port-presence summary idiom
```powershell
foreach ($p in @(22,5985,5986,11434,18789,5000,9000)) {
    $hits = $rules | Where-Object { ($_.Ports -split ',' | % Trim) -contains "$p" }
    $allow = $hits | Where-Object { $_.Action -eq 'Allow' -and $_.Enabled -eq 'Yes' }
    if ($allow) { "Port $p : ALLOW/Enabled ($($allow.Name -join ' | '))" }
    elseif ($hits) { "Port $p : rule exists but NOT Allow+Enabled ($($hits.Name -join ' | '))" }
    else { "Port $p : NO inbound rule" }
}
```

## Node-1 findings this pattern surfaced (real, 2026-07-11)
- Port 22   -> `ZQM-OpenSSH-22` ALLOW/Enabled (Domain,Private,Public). OK
- Port 5985 -> rule `Windows Remote Management (HTTP-In)` EXISTS but `Enabled=No`
  => inbound 5985 BLOCKED despite the socket being bound (only 5986 reachable).
- Port 5986 -> `ZQM-WinRM-5986` ALLOW/Enabled. OK
- Port 11434 -> `Ollama-LAN-only-11434` ALLOW/Enabled (LAN-scoped). OK
- Ports 18789 / 5000 / 9000 -> NO inbound rule at all (5000 only has an unrelated
  UDP 5000-5020 Media Foundation rule).
- All 3 profiles Enabled; default inbound action `NotConfigured` (= Block).

## WinRM listener provider quirk
`Get-ChildItem WSMan:\localhost\Listener` returned "No WSMan listeners" on Node-1 even
though `Get-NetTCPConnection -State Listen` showed `:::5985` and `:::5986` BOUND.
Treat the TCP socket state as authoritative for "is it listening"; the PS WSMan
provider can misreport under non-elevated runs. (For SSL cert detail use
`netsh http show sslcert` — `winrm enumerate` is denied non-elevated.)

## sshd password-auth default (hardening note)
In `C:\ProgramData\ssh\sshd_config`, a commented `#PasswordAuthentication yes` means
the default is enabled => password auth is ON. If key-only is intended, this is a gap.
`#PubkeyAuthentication yes` (default = yes) and `#PermitRootLogin prohibit-password`
(default = prohibit-password) are fine. Confirm by reading the file, not assuming.

## Ollama is a PROCESS, not a service
`Get-Service` will NOT list Ollama. It runs as a user process (owner `ollama`/`python`)
bound to `127.0.0.1:11434` + `192.168.1.218:11434`. Do not invent an "AI" service group
from a keyword scan — it will false-positive on NVDisplay/SysMain/etc.
