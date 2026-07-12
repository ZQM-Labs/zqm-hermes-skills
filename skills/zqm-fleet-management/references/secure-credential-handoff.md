# Secure Credential Handoff (no secret in chat)

The user will NOT paste passwords into chat. The approved method: the human stores the
secret in an INTERACTIVE PowerShell session (typing hidden via Get-Credential), encrypted
with DPAPI LocalMachine scope, written to a file. The agent's terminal (different account)
decrypts and uses it as a SecureString — password never printed.

## WHY LocalMachine scope (not Export-Clixml / user scope)
- Human desktop PowerShell runs as `zqm-node-1\alexz`; agent terminal runs as `zqmco`.
- User-scoped DPAPI (Export-Clixml) binds ciphertext to the creating user -> the other
  account gets "Key not valid for use in specified state" on import.
- LocalMachine scope = decryptable by ANY local account on THIS PC. Trade-off: any local
  admin could read it (fine for a solo LAN). This is the only way to bridge alexz -> zqmco
  without the password ever touching chat.

## STORE (human runs, interactive; typing hidden)
```powershell
$c=Get-Credential -Message "Synology admin cred (hidden):"; New-Item -ItemType Directory -Force -Path C:\zqm\cred | Out-Null; $p=$c.GetNetworkCredential().Password; $b=[System.Text.Encoding]::UTF8.GetBytes($p); $e=[System.Security.Cryptography.ProtectedData]::Protect($b,$null,'LocalMachine'); [pscustomobject]@{user=$c.UserName;data=[Convert]::ToBase64String($e)} | ConvertTo-Json | Set-Content C:\zqm\cred\zqm-cred-garden-admin.json -Force; if (Test-Path C:\zqm\cred\zqm-cred-garden-admin.json) { Write-Host ("OK WROTE ... user="+$c.UserName) } else { Write-Host "WRITE FAILED" }
```
PITFALL: Set-Content does NOT auto-create parent dirs -> the one-liner must `New-Item -Force`
the dir FIRST or the write silently fails while a trailing Write-Host "WROTE" lies about success.
The Test-Path guard above fixes that.

## USE (agent terminal; never prints plaintext)
```powershell
Add-Type -AssemblyName System.Security   # REQUIRED or [ProtectedData] type not found
$p="C:\zqm\cred\zqm-cred-garden-admin.json"
$o=Get-Content $p -Raw|ConvertFrom-Json
$enc=[Convert]::FromBase64String($o.data)
$pw=[System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($enc,$null,"LocalMachine"))
$sec=ConvertTo-SecureString $pw -AsPlainText -Force
$c=New-Object System.Management.Automation.PSCredential($o.user,$sec)
# pass $c to Invoke-RestMethod / New-SmbMapping / SSH. NEVER $c.GetNetworkCredential().Password in printed output.
```
PITFALL: `[System.Security.Cryptography.ProtectedData]` throws "Unable to find type" unless
`Add-Type -AssemblyName System.Security` runs first in the agent's runspace.

## CLEANUP
```powershell
Remove-Item C:\zqm\cred\zqm-cred-garden-admin.json -Force
```
Also delete any stray user-scope file (e.g. C:\Users\AlexZ\zqm-cred-*.xml) left from failed attempts.
