# Node Login Failover Setup (zqm-bootstrap.ps1 v2 + zqm-fleet.ps1)

## Goal
Give the Windows nodes real login redundancy so a WinRM failure doesn't require physical access. Delivered scripts (staged at `\\192.168.1.40\web\`, hash-matched to `C:\Users\zqmco\`):

### zqm-bootstrap.ps1 (run LOCALLY on a node, Admin PS)
Does in order:
1. Sets the 192.168.x adapter to `Private`.
2. `Enable-PSRemoting -Force`; sets `LocalAccountTokenFilterPolicy=1` (workgroup NTLM).
3. Resolves the `zqmlocal` password: if `C:\zqm\cred\zqm-cred-node-local.json` exists it is DPAPI-decrypted (non-interactive); otherwise prompts (hidden).
4. Creates `zqmlocal`, adds to `Administrators` + `Remote Management Users`.
5. **Auto-stores the password to LocalMachine-DPAPI JSON** (`C:\zqm\cred\zqm-cred-node-local.json`) so the agent can re-auth without the secret in chat.
6. Opens the indexer port (default 5000) LAN-scoped.
7. **FAILVOER A:** WinRM-HTTPS listener on 5986 (self-signed cert + firewall rule, LAN-scoped).
8. **FAILVOER B:** installs/enables OpenSSH Server (22) + firewall rule. Skips gracefully if the OpenSSH.Server capability is absent (Home editions).

### zqm-fleet.ps1 (run from Node-1)
Reads `C:\zqm\cred\zqm-cred-node-local.json`, builds a `PSCredential`, and for each node (default 21/46/215) tries **5985 then 5986 (UseSSL)**, then `Invoke-Command` reports Host / Windows version / uptime / sshd status / WinRM-HTTPS listener. This is the live failover proof.

## Exact user steps to finish the mesh (agent cannot do these alone)
1. On Node-2 (or any node where `zqmlocal`'s password is known), run the store-cred one-liner:
   ```powershell
   $c=Get-Credential -Message "Enter the zqmlocal cred (hidden):"; New-Item -ItemType Directory -Force -Path C:\zqm\cred | Out-Null; $p=$c.GetNetworkCredential().Password; $b=[System.Text.Encoding]::UTF8.GetBytes($p); $e=[System.Security.Cryptography.ProtectedData]::Protect($b,$null,'LocalMachine'); [pscustomobject]@{user=$c.UserName;data=[Convert]::ToBase64String($e)} | ConvertTo-Json | Set-Content C:\zqm\cred\zqm-cred-node-local.json -Force; if (Test-Path C:\zqm\cred\zqm-cred-node-local.json) { Write-Host ("OK WROTE user="+$c.UserName) } else { Write-Host "WRITE FAILED" }
   ```
   Ensure the username is `zqmlocal`. Then copy it to Node-1:
   `Copy-Item C:\zqm\cred\zqm-cred-node-local.json \\192.168.1.218\C$\zqm\cred\zqm-cred-node-local.json`
2. On Node-3 (.46) and Node-4 (.215), Admin PS:
   `powershell -ExecutionPolicy Bypass -File \\192.168.1.40\web\zqm-bootstrap.ps1`
   (or copy it locally first if the share isn't reachable).
3. On Node-1: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force`
4. Tell the agent "done" → it runs `zqm-fleet.ps1` and reports per-node failover status.

## Pitfall: Set-Content "WROTE" but file missing
`Set-Content` to a non-existent parent dir FAILS silently, but an unconditional `Write-Host "WROTE"` lies. Always `New-Item -ItemType Directory -Force -Path (Split-Path $Path)` first and gate the success message behind `Test-Path` (the one-liner above does both).

## Pitfall: DPAPI in Python
Do not decrypt DPAPI from Python (`CryptUnprotectData` ctypes → WinError 87). Decrypt in PowerShell (`ProtectedData::Unprotect(...,"LocalMachine")`) and pass the clear password as argv to the python script.
