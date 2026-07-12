# dsm-login-sweep.ps1 — sweep a list of Synology DSM IPs with a stored credential.
# Uses the windows-secure-credential-handoff consumer pattern (machine-scope DPAPI).
# Password never printed. Reports LOGIN OK / REJECTED error=N / NO DSM PORT.
param(
    [string]$CredName = "garden-admin",
    [string[]]$IPs = @("192.168.1.40","192.168.1.64","192.168.1.173")
)
Add-Type -AssemblyName System.Security
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
$p = "C:\zqm\cred\zqm-cred-$CredName.json"
if (-not (Test-Path $p)) { Write-Error "No credential file at $p — run the STORE one-liner first."; exit 1 }
$o = Get-Content $p -Raw | ConvertFrom-Json
$enc = [Convert]::FromBase64String($o.data)
$pw = [System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, "LocalMachine"))
Write-Host ("DSM login sweep as $($o.user) against $($IPs.Count) IPs:`n")
foreach ($ip in $IPs) {
    foreach ($port in @(5001, 5000)) {
        try {
            $r = Invoke-RestMethod -Uri "https://$ip`:$port/webapi/auth.cgi" -Method Post -TimeoutSec 5 `
                -Body @{api="SYNO.API.Auth";version=6;method="login";account=$o.user;passwd=$pw;session="FileStation";format="sid"}
            if ($r.success) { Write-Host ("  $ip : LOGIN OK  sid=" + $r.data.sid.Substring(0,10) + "..."); break }
            else { Write-Host ("  $ip : REJECTED error=" + $r.error.code); break }
        } catch { Write-Host ("  $ip : NO DSM PORT (5001/5000)"); break }
    }
}
