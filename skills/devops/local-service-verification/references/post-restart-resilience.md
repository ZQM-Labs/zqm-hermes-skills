# Post-Restart / Reboot Resilience — reference

Reusable recipes for making ZQM local services survive a reboot. This is a recurring class of
work (saw it Jul 5, 11, 12 2026); the fix recipe already exists on disk but was NEVER registered
behind the UAC gate. Capture it so the next session can finish it in one turn.

## 1. The verified-exists supervisor recipe (Node-1 agent stack)
Files already on disk (verified present 2026-07-12):
- `C:\Users\zqmco\ZBit_api\start_zqm_stack.bat` — launches ZBit :8400 + LiteLLM :4001 + Ollama :11434.
- `C:\Users\zqmco\swarm\fleet_endpoint_review\apply_stability.ps1` — registers the supervisor task.

apply_stability.ps1 does:
- `Register-ScheduledTask` named `ZQM-Stack-Autostart`, trigger **AtStartup**, principal **SYSTEM**.
- Action: run `start_zqm_stack.bat`.
- Crash recovery: `RestartCount=3`, `RestartInterval=1min`.
- Configures `sshd` → Automatic + restart-on-failure.

### Register (ELEVATED PowerShell — the agent shell is non-elevated, hand to user)
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\zqmco\swarm\fleet_endpoint_review\apply_stability.ps1"
```

### Verify (re-verify AFTER, do not trust start stdout)
```powershell
Get-ScheduledTask -TaskName "ZQM-Stack-Autostart" | Select TaskName,State
# hard test: Stop-Process the stack PIDs, wait ~60s, confirm they return via netstat :8400/:4001
```

## 2. Logon-only services that already have Startup .lnk (no further action unless pre-boot needed)
- `C:\Users\zqmco\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\ZQM-Node-01-Indexer.lnk`
- `...\Startup\ZQM-Skill-Automation-Center.lnk`
These fire only after a user logs in. If pre-logon boot is required, convert to an AtStartup
scheduled task (same pattern as #1) instead of the .lnk.

## 3. Win11 OpenSSH install (dism.exe fallback)
`Get-WindowsCapability -Online` throws `Class not registered` = broken Dism PS COM registration,
NOT a version gap. Use native `dism.exe` (does not use the broken COM class):
```powershell
dism.exe /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0
Set-Service sshd -StartupType Automatic; Start-Service sshd
New-NetFirewallRule -DisplayName "ZQM-OpenSSH-22" -Direction Inbound -LocalPort 22 -Protocol TCP `
  -Action Allow -Profile Any -RemoteAddress 192.168.1.0/24
```
Bootstrap-script ordering: check `Get-Service sshd` first; only install capability if absent;
try/catch the Dism PS provider → fall back to dism.exe; wrap the whole OpenSSH block in try/catch
so it can't abort the rest of bootstrap (Cert: mount, WinRM).

## 4. Synology Garden SMB write wrapper (write_file/cmd silently fail to //UNC)
Only native PowerShell Copy-Item lands. Wrap as a terminal-run PS command:
```powershell
Copy-Item "C:\Users\zqmco\swarm\fleet_endpoint_review\zqm-bootstrap.ps1" `
  -Destination '\\192.168.1.173\web\zqm-bootstrap.ps1' -Force
# verify:
Get-Content '\\192.168.1.173\web\zqm-bootstrap.ps1' | Select-Object -First 3
```
NOTE: HTTP web root (`http://ZQM-Garden-01/...`) is often DECOUPLED from the SMB `web` share.
SMB-put files may not be what nodes fetch over HTTP — confirm the node's actual fetch store.

## 5. Post-reboot fleet re-probe checklist (run after ANY node restart)
- `netstat -ano | findstr LISTENING` on the node for :8400 :4001 :11434 (agent stack).
- From Node-1: Python socket scan of node :22 :5985 :5986 (ssh/WinRM failover).
- `Test-WSMan -ComputerName <ip>` (HTTP) and `Test-WSMan -UseSSL -ComputerName <ip>` — a TLS
  cert-error (CA unknown / CN mismatch) means the listener is ALIVE; only a connection-refused =
  truly down. (See windows-remoting.)
- Confirm zqmlocal cred still works; if pw drift, re-run bootstrap password-reset one-liner on the
  node console before declaring it "managed."
