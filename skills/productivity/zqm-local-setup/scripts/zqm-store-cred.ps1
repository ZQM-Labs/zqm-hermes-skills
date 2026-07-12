# zqm-store-cred.ps1  (LocalMachine-scope version)
# RUN YOURSELF in interactive PowerShell (typing hidden, nothing sent to chat).
# Uses MACHINE-scoped DPAPI so the agent's session (a different local account)
# can decrypt it on the same PC. Decryptable by any local account on THIS machine.
#
# Usage:
#   .\zqm-store-cred.ps1 -Name garden-admin
#   .\zqm-store-cred.ps1 -Name node-local -Path C:\zqm\cred\zqm-cred-node.json
param(
    [string]$Name = "default",
    [string]$Path
)
if (-not $Path) { $Path = "C:\zqm\cred\zqm-cred-$Name.json" }
New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null

$c = Get-Credential -Message "Enter credential to store securely (typing hidden, not sent to chat)."
$plain = $c.GetNetworkCredential().Password
$bytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
$enc   = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
$obj   = [pscustomobject]@{ user = $c.UserName; data = [Convert]::ToBase64String($enc) } | ConvertTo-Json
Set-Content -Path $Path -Value $obj -Force
if (Test-Path $Path) { Write-Host ("Stored (LocalMachine): " + $Path + "  user=" + $c.UserName) }
else { Write-Host "WRITE FAILED" }
