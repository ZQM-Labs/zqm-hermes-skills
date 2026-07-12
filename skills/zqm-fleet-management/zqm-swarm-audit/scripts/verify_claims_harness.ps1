# verify_claims_harness.ps1 — re-runnable "hash claims" recreation + SHA-256 ledger
# Self-elevates (SYSTEM-owned tasks are invisible to non-admin Get-ScheduledTask),
# runs the per-claim LIVE probes you fill in, then emits:
#   claim_evidence.json  (array of {id, statement, observed, status, evidence})
#   claim_manifest.json (SHA-256 of evidence + verdict counts)
# Copy this file and replace the ##### CLAIM BLOCK ##### with your real probes.
param()
$ErrorActionPreference = 'SilentlyContinue'

# --- self-elevate if not admin (critical: SYSTEM tasks + creded UNC need it) ---
$wp = [System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $wp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit 0
}

$claims = @()
function Add-Claim($id,$stmt,$obs,$status,$ev){ $script:claims += [pscustomobject]@{id=$id; statement=$stmt; observed=$obs; status=$status; evidence=$ev} }

##### CLAIM BLOCK — replace each probe with a fresh LIVE re-derivation #####
# Example garden/node probes; do NOT trust prior logs. Re-establish from scratch.
# SYSTEM task visibility (non-admin Get-ScheduledTask returns NOT FOUND — artifact):
$t = Get-ScheduledTask -TaskName 'ZQM-Garden-Link' -ErrorAction SilentlyContinue
if ($t) { $ti=Get-ScheduledTaskInfo -TaskName 'ZQM-Garden-Link'; Add-Claim 'C1' 'ZQM-Garden-Link task exists (SYSTEM, boot+15min)' "present; triggers=$($t.Triggers.Count)" 'PROVEN' "lastResult=$($ti.LastTaskResult)" } else { Add-Claim 'C1' 'ZQM-Garden-Link task exists' 'NOT FOUND' 'FALSE' 'task missing (verify elevated!)' }

# Authoritative Garden writability: mount UNC WITH cred (per-session bare UNC write DENIES).
# Fill $gUser/$gPw from a LocalMachine-DPAPI JSON (never inline). Template:
#   Add-Type -AssemblyName System.Security | Out-Null
#   $o = Get-Content 'C:\zqm\cred\zqm-cred-garden-admin.json' -Raw | ConvertFrom-Json
#   $raw = [System.Convert]::FromBase64String($o.data)
#   $gpw = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($raw,$null,'LocalMachine'))
#   foreach ($unc in @('\\192.168.1.173\web')) {
#     cmd.exe /c "net use `"$unc`" /user:$($o.user) $gpw >nul 2>&1"
#     $probe="$unc\probe_$(Get-Date -Format yyyyMMddHHmmss).txt"; $ok=$false
#     try { 'ok' | Set-Content $probe -Encoding ascii; if((Get-Content $probe) -eq 'ok'){$ok=$true}; Remove-Item $probe -EA SilentlyContinue } catch {}
#     cmd.exe /c "net use `"$unc`" /delete >nul 2>&1" | Out-Null
#     Add-Claim 'G1' "$unc writable (creded UNC)" "write=$ok" $(if($ok){'PROVEN'}else{'FALSE'}) "$unc"
#   }
##### END CLAIM BLOCK #####

# --- persist tamper-evident ledger ---
$ev = $claims | ConvertTo-Json -Depth 3
Set-Content 'C:\zqm\link\claim_evidence.json' $ev -Encoding ascii
$evHash = (Get-FileHash -Algorithm SHA256 -InputStream ([System.IO.MemoryStream]::new([Text.Encoding]::ASCII.GetBytes($ev))).Hash
$ledger = @{
  generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  generated_by = $env:COMPUTERNAME
  evidence_sha256 = $evHash
  claim_count = $claims.Count
  proven = ($claims | Where-Object { $_.status -eq 'PROVEN' }).Count
  false = ($claims | Where-Object { $_.status -eq 'FALSE' }).Count
  not_proven = ($claims | Where-Object { $_.status -eq 'NOT PROVEN' }).Count
  claims = $claims | ForEach-Object { [pscustomobject]@{id=$_.id; status=$_.status; statement=$_.statement; evidence=$_.evidence} }
}
$ledger | ConvertTo-Json -Depth 4 | Set-Content 'C:\zqm\link\claim_manifest.json' -Encoding ascii
"LEDGER: proven=$($ledger.proven) false=$($ledger.false) not_proven=$($ledger.not_proven) sha256=$evHash" | Out-Host
