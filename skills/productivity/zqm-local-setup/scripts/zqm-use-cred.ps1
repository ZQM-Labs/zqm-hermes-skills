# zqm-use-cred.ps1
# RUN BY THE AGENT (terminal) — never prints the plaintext password.
# Loads the DPAPI-encrypted credential and uses it as a SecureString only.
#
# Usage:
#   .\zqm-use-cred.ps1 -Name garden-admin -ComputerName 192.168.1.40
param(
    [string]$Name = "default",
    [string]$Path,
    [string]$ComputerName
)
if (-not $Path) { $Path = Join-Path $env:USERPROFILE ("zqm-cred-{0}.xml" -f $Name) }
if (-not (Test-Path $Path)) { Write-Error "No credential file at $Path — run zqm-store-cred.ps1 first."; exit 1 }

$c = Import-Clixml -Path $Path   # returns PSCredential; password stays SecureString
Write-Host ("Loaded credential for: " + $c.UserName + "  (password NOT printed)")

if ($ComputerName) {
    # Example: map a Garden SMB share using the stored cred (no plaintext ever shown)
    try {
        $map = New-SmbMapping -RemotePath "\\$ComputerName\web" -UserName $c.UserName -Password $c.Password -Persistent $false -ErrorAction Stop
        Write-Host ("SMB map to \\$ComputerName\web : OK")
    } catch {
        Write-Host ("SMB map failed: " + $_.Exception.Message)
    }
}
# For DSM/SSH tasks, pass $c directly to -Credential / Invoke-RestMethod.
# NEVER call $c.GetNetworkCredential().Password in any command you print.
