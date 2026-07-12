# Garden NAS SMB share reachability probe (from a Windows node, e.g. Node-1)

## Why this exists
Auditing `\\backups` / `\\web` "is it up?" in the ZQM homelab. LEAD's `:445` TCP
probe only proves the SMB port is open — it does NOT prove a given share name
exists or is auth-reachable. This recipe closes that gap from a Windows vantage.

## Gotchas (verified 2026-07-11)
- `backups` / `web` are SHARE names, not hosts. No DNS/NetBIOS resolution.
  Use `\\<ip-or-fqdn>\<share>`: `\\192.168.1.173\backups`,
  `\\ZQM-Garden-01.lan\web`, etc. FQDN `.lan` resolves on the Wi-Fi DNS suffix.
- Stored cmdkey cred `ZQM-Garden-01` / `azelenski` is keyed to a BARE hostname
  that does not resolve (only `.lan` FQDN/IP do) -> never auto-applies to `\\<ip>\...`.
- SMB redirector (LanmanWorkstation) can wedge mid-session: `net view \\127.0.0.1`
  returns "no entries", `\\localhost\IPC$` fails with 67, `net view \\<host>` returns
  1702. This is transient Win10 state, NOT the target being down. Corroborate with
  the independent TCP `:445` / `nbtstat -A` checks before concluding failure.

## net use error codes (diagnostic, not just failures)
- 1223 = server reached + share presented; auth prompt unsatisfied. HOST/SHARE ALIVE.
- 3024 = server reached + share presented; credential rejected (expired/wrong/locked).
- 67  = ambiguous: bad name OR redirector wedged (corroborate with :445 / nbtstat).
- 1702 = redirector (LanmanWorkstation) wedged; even \\localhost\IPC$ fails. Transient.

## Reusable probe (.ps1, ASCII-only, run via: powershell.exe -NoProfile -EP Bypass -File garden-smb-probe.ps1)
```powershell
# garden-smb-probe.ps1
$targets = @(
  '\\192.168.1.173\backups', '\\192.168.1.173\web',
  '\\192.168.1.40\backups',  '\\192.168.1.64\backups'
)
foreach ($t in $targets) {
  $r = net use $t /persistent:no 2>&1
  Write-Output ("{0} -> {1}" -f $t, ($r -join ' '))
  net use $t /delete /yes 2>$null | Out-Null
}
# server-alive: TCP :445 + NetBIOS <20>
foreach ($ip in @('192.168.1.173','192.168.1.40','192.168.1.64')) {
  $tcp = New-Object System.Net.Sockets.TcpClient
  $ar = $tcp.BeginConnect($ip,445,$null,$null)
  if ($ar.AsyncWaitHandle.WaitOne(800,$false) -and $tcp.Connected) { Write-Output ("{0}:445 OPEN" -f $ip) } else { Write-Output ("{0}:445 closed" -f $ip) }
  $tcp.Close()
}
```
Also: `nbtstat -A <ip>` (look for `<20>` Registered) and `Resolve-DnsName <ip>` to
map IP -> `.lan` FQDN for the correct share mount path.

## Closing Q5-style auth failures (human step)
Admin PS or Explorer:
  net use \\ZQM-Garden-01.lan\backups /user:azelenski *
then enter the live NAS password. Re-key cmdkey so it auto-applies:
  cmdkey /add:192.168.1.173 /user:azelenski /pass
