<# tpm-blindspot.ps1 - non-elevated TPM verification via the blindspot pattern.
   When Get-Tpm / CIM Win32_Tpm are DENIED (non-admin), fall back to the
   unprivileged TPM-WMI System events (1041 = attestation, 519 = clear) that
   prove the same facts. Records the exact exception TYPE for honest labeling.
   READ-ONLY. No Admin required. #>
$ErrorActionPreference = 'SilentlyContinue'
$out = New-Object System.Collections.ArrayList
function Add($s){ [void]$out.Add($s); Write-Output $s }

function Probe($name,$sb){
    try { $r = & $sb; Add ("[$name] OK: " + (($r | Out-String).Trim() -split "`n" | Select-Object -First 2) -join " | ") }
    catch { Add ("[$name] EXCEPTION: " + $_.Exception.GetType().Name + ": " + $_.Exception.Message.Trim()) }
}

Add "===== TPM BLINDSPOT RE-PROOF (non-elevated) ====="
Add ("  Generated: " + (Get-Date -Format 'o'))

Add ""
Add "--- PATH 1: privileged reads (expect DENIED non-admin; record exception type) ---"
Probe "Get-Tpm" { Get-Tpm }
Probe "CIM Win32_Tpm" { Get-CimInstance -Namespace root\cimv2\Security\MicrosoftTpm -ClassName Win32_Tpm }

Add ""
Add "--- PATH 2: unprivileged TPM-WMI events (readable unelevated) ---"
$ev1041 = Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-TPM-WMI';Id=1041} -MaxEvents 5 -ErrorAction SilentlyContinue
if ($ev1041) {
    Add ("  Event 1041 (TPM attestation) FOUND x$($ev1041.Count) -> TPM present & attesting unelevated")
    foreach ($e in $ev1041) {
        $hs = ($e.Message | Select-String 'HealthStatus.{0,4}?(\w+)' | ForEach-Object { $_.Matches.Groups[1].Value }) -join ','
        Add ("    $($e.TimeCreated) HealthStatus=$hs")
    }
} else { Add "  Event 1041: none found (TPM may be absent, or no attestation logged)" }

$ev519 = Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-TPM-WMI';Id=519} -MaxEvents 5 -ErrorAction SilentlyContinue
if ($ev519) {
    Add ("  Event 519 (TPM CLEAR) FOUND x$($ev519.Count) -> characterize (notable security event)")
    foreach ($e in $ev519) {
        Add ("    $($e.TimeCreated) | UserId=$($e.UserId) | $($e.Message)")
    }
} else { Add "  Event 519 (TPM clear): none found unelevated - good, no clears recorded" }

Add ""
Add "--- PATH 3: registry (unprivileged) ---"
Probe "TPM\WMI reg" { Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\TPM\WMI' }

Add ""
Add "--- VERDICT ---"
if ($ev1041) {
    Add "  TPM CONFIRMED PRESENT & ATTESTING via unprivileged Event 1041 (independent of admin-blocked Get-Tpm)."
} else {
    Add "  Could not prove TPM via unprivileged event path; admin elevation still required for definitive state."
}
if ($ev519) {
    Add "  NOTE: a TPM clear (519) was logged - characterize before concluding benign (SYSTEM + build timestamp = benign reprovision)."
}

Set-Content -Path ($PSScriptRoot + '\tpm-blindspot.out') -Value $out -Encoding UTF8
Add ""
Add "Wrote: " + $PSScriptRoot + '\tpm-blindspot.out'
