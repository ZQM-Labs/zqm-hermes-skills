# use-cred-consumer.ps1 — run by the AGENT (terminal). Never prints plaintext.
# Loads a machine-scope DPAPI credential stored by the human, prints only the
# username, then is a starting point for using it (SMB map shown; adapt for
# DSM/SSH/WinRM by passing $c to -Credential / Invoke-RestMethod).
param([string]$Name="garden-admin", [string]$ComputerName)
Add-Type -AssemblyName System.Security   # REQUIRED before [ProtectedData] in a fresh runspace
$p = "C:\zqm\cred\zqm-cred-$Name.json"
if (-not (Test-Path $p)) { Write-Error "No credential file at $p — run the STORE one-liner first."; exit 1 }
$o   = Get-Content $p -Raw | ConvertFrom-Json
$enc = [Convert]::FromBase64String($o.data)
$pw  = [System.Text.Encoding]::UTF8.GetString(
        [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, "LocalMachine"))
$sec = ConvertTo-SecureString $pw -AsPlainText -Force
$c   = New-Object System.Management.Automation.PSCredential($o.user, $sec)
Write-Host ("LOADED user: " + $c.UserName + "  (password NOT printed)")

if ($ComputerName) {
    try {
        New-SmbMapping -RemotePath "\\$ComputerName\web" -UserName $c.UserName -Password $c.Password -Persistent $false -ErrorAction Stop
        Write-Host ("SMB map to \\$ComputerName\web : OK")
    } catch { Write-Host ("SMB map failed: " + $_.Exception.Message) }
}
# For DSM/SSH: pass $c to Invoke-RestMethod -Credential $c, or build a plink/ssh
# call. NEVER Write-Host $pw or $c.GetNetworkCredential().Password.
