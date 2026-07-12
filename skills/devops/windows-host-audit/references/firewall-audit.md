# Firewall & WinRM/sshd audit recipe (proven live on ZQM-NODE-1, 2026-07-11)

## A2. RELIABLE netstat listener capture from Hermes terminal (HARD-WON, 2026-07-11)
`subprocess.run(['powershell.exe','-NoProfile','-Command',"cmd.exe /c 'netstat ...' | Select-String ..."])`
SILENTLY SWALLOWS `cmd.exe` stdout in many runs (returns 0 rows) — flaky in both
`-Command` inline AND `-File`. The ONLY form 100% reliable is a BARE terminal
redirect to a file, then parse the file in a SEPARATE step (never pipe netstat
through python's subprocess):
```bash
powershell.exe -NoProfile -Command "cmd.exe /c 'netstat -ano -p TCP' | Select-String 'LISTENING'" > "/c/Users/zqmco/AppData/Local/Temp/net.txt" 2>&1
# THEN (separate command) read+parse the file in python
```
CRITICAL REGEX GOTCHA: netstat columns have variable spacing. The naive
`TCP\s+(\S+):(\d+)\s+\S+\s+(\d+)` FAILS (the 2nd `\S+` never matches the
spaced `0.0.0.0:0` column). Use:
```python
re.search(r'TCP\s+([\d.]+):(\d+)\s+[\d.]+:\d+\s+LISTENING\s+(\d+)', line)
# groups: (localaddr, port, pid)
```
Also: `Get-NetTCPConnection -State Listen` serializes OwningProcessId as null in
JSON, and the `WSMan:` provider path is gated — so netstat-to-file + this regex is
the authoritative listener→PID map. Do NOT trust a "0 listeners" parse result:
hexdump the file (`open(path,'rb').read()[:300]`) to confirm data is present
before blaming the box. (This bug burned ~6 failed turns in one audit — don't repeat.)

The per-rule PowerShell pipeline is SLOW on this host (a `Get-NetFirewallRule |
Get-NetFirewallPortFilter` loop + `schtasks /query /fo LIST` ran past a 120s
timeout). One `netsh` dump parsed once completes in <30s.

```powershell
# Single enumeration, parse once.
$netshRaw = (netsh advfirewall firewall show rule name=all dir=in) -join "`n"
$blocks = $netshRaw -split "(?=Rule Name\s*:)" | Where-Object { $_ -match 'Rule Name' }
function ParsePort($port){
  Write-Output ("--- port $port ---")
  $found = $false
  foreach ($b in $blocks){
    if ($b -match "LocalPort\s*:\s*$port\b" -or $b -match "localport\s*=\s*$port\b"){
      $found = $true
      $rn   = if ($b -match 'Rule Name\s*:\s*(.+)') { $matches[1].Trim() } else { '?' }
      $en   = if ($b -match 'Enabled\s*:\s*(.+)') { $matches[1].Trim() } else { '?' }
      $act  = if ($b -match 'Action\s*:\s*(.+)') { $matches[1].Trim() } else { '?' }
      $la   = if ($b -match 'LocalAddress\s*:\s*(.+)') { $matches[1].Trim() } else { '?' }
      $ra   = if ($b -match 'RemoteAddress\s*:\s*(.+)') { $matches[1].Trim() } else { '?' }
      Write-Output ("  Rule: $rn | Enabled=$en | Action=$act | LocalAddr=$la | RemoteAddr=$ra")
    }
  }
  if (-not $found){ Write-Output ("  NO inbound rule for port $port") }
}
'22','5985','5986','11434','18789' | ForEach-Object { ParsePort $_ }
```

Profile state (fast, no hang):
```powershell
netsh advfirewall show allprofiles state
```

Per-rule detail (for scope) — note BOTH LocalIP and RemoteIP:
```powershell
netsh advfirewall firewall show rule name="Ollama-LAN-only-11434" dir=in
# LocalIP: Any ; RemoteIP: 192.168.1.0/24  => correctly LAN-scoped
```

## B. Listener state = socket census, NOT the WSMan PS provider
The `WSMan:` PSDrive `Listener` path returned "Cannot find path" (provider
quirk) even though the listener was bound. Use `Get-NetTCPConnection` as the
authoritative source for what is actually listening:

```powershell
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in 22,5985,5986,11434,18789 } |
  Sort-Object LocalPort | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort) pid=$($_.OwningProcess)" }
```

Confirmed result this run: 5986 IS bound (`:::5986`/`0.0.0.0:5986`, pid 4) but
**5985 is NOT** — WinRM is HTTPS-only. A prior audit claiming "5985 listening"
was overstated.

## C. Loopback probes must run ON the target host
If you need to know whether `127.0.0.1:<port>` is listening, the probe must
execute on that host. A remote vantage (e.g. the agent sandbox `exec
3<>/dev/tcp/127.0.0.1/18789`) tests the *sandbox's own* loopback and returns
false negatives. Correct vantage here: `:18789` OpenClaw gateway IS listening
on Node-1's loopback (pid 23208) — a "dormant" conclusion from the remote probe
was stale.

## E. sshd effective-config proof via `sshd -G` (resolves password-auth, NON-elevated)
To close "is password-auth on?" definitively without elevated file reads, dump the
EFFECTIVE config (resolves commented defaults): `C:\Program Files\OpenSSH\sshd.exe`
(full Program Files path — `C:\Windows\System32\OpenSSH\` does NOT exist on this
fleet). `Start-Process -FilePath 'C:\Program Files\OpenSSH\sshd.exe' -ArgumentList @('-G')`
redirects stdout to a file; parse lines like `passwordauthentication: yes`,
`authenticationmethods: any`, `pubkeyauthentication: yes`. This session proved
N1 sshd accepts password logins from the LAN (closed Q10). Config file is
`C:\ProgramData\ssh\sshd_config` (the `#PasswordAuthentication yes` comment = ON).
`sshd -t` is the syntax gate before any edit; the `Match Group administrators`
block at EOF means appending directives there scopes them to admins and no-ops —
edit the commented lines IN PLACE.

## F. Windows FW BLOCK-over-ALLOW precedence can RESOLVE an external-block question
If a `Block` rule shares LocalPort+RemoteIP with a stale `Allow` rule, the block
wins deterministically — no peer probe needed. This session closed Q8 this way
(ZQM-Ollama-LAN-Block beats stale Ollama-LAN-only-11434). Report as "resolved by
rule-precedence analysis" (a proof, not an assumption); a live peer curl stays
gold-standard IF a credential exists. Note: FW rules do NOT filter loopback/self-to-
own-IP, so a same-host `curl http://<own-LAN-IP>:<port>` returning 200 is NOT proof
the block failed — probe from a different host.

## G. FALSE-FAIL in automated re-verify — fix the TEST, not the ledger
When a claim-chain re-verify (the "investigate fully" step) returns FAIL, check for
a TEST ARTIFACT before recording a contradiction: wrong HTTP method (GET on a
POST-only endpoint → 404/405, mis-read as "auth broken"), wrong regex (scanning
`:::11434` misses the actual `0.0.0.0:11434` line), or transient timeout. Re-run
with a corrected probe; only record a contradiction if it STILL fails. This session
had 2 false FAILs (both test bugs) — fixed the tests, got PASS, did NOT flip any
finding. Inverse of RETRACT: don't retract OR contradict on a flaky test.
