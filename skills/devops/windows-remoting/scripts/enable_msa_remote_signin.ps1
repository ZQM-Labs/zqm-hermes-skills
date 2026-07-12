<# enable_msa_remote_signin.ps1 — enable Microsoft-account (MSA) remote sign-in for WinRM/RDP/SSH.
   Run ELEVATED. Idempotent + reports state.
   WHY: an MSA (e.g. zqmcomputing@gmail.com) logs in at the console but is rejected by headless
   SSH/WinRM until this is enabled. NOTE: this only helps if the MSA password is CORRECT for the
   Windows login. If LogonUser returns 1326 (bad password) locally, do NOT run this — the password
   is wrong and enabling remote sign-in cannot fix it. See references/msa-auth-diagnostic.md step 5.
#>
$ErrorActionPreference = 'SilentlyContinue'
Write-Host "=== Enable MSA remote sign-in ($(Get-Date)) ==="

# 1) Policy: allow Microsoft accounts to be used for sign-in
$k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$cur = (Get-ItemProperty $k -Name AllowMicrosoftAccountSignin -ErrorAction SilentlyContinue).AllowMicrosoftAccountSignin
Set-ItemProperty $k -Name AllowMicrosoftAccountSignin -Value 1 -Force
Write-Host "AllowMicrosoftAccountSignin: was=$cur now=1"

# 2) WinRM: ensure service + HTTP listener present (Running service with NO listener still rejects)
$svc = Get-Service WinRM
if ($svc.Status -ne 'Running') { Start-Service WinRM; Write-Host "WinRM started" }
if (-not (Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue)) {
  winrm quickconfig -transport:http -q 2>&1 | ForEach-Object { Write-Host "  quickconfig: $_" }
  netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes 2>&1 | Out-Null
  Write-Host "WinRM HTTP listener created"
} else { Write-Host "WinRM listener already present" }

# 3) SSH: ensure password auth enabled
$cfg = 'C:\ProgramData\ssh\sshd_config'
$lines = Get-Content $cfg
$new = $lines | Where-Object { $_ -notmatch '^PasswordAuthentication no' -and $_ -notmatch '^#PasswordAuthentication' }
if ($new -notcontains 'PasswordAuthentication yes') { $new += 'PasswordAuthentication yes' }
$new | Set-Content $cfg -Encoding ascii
Restart-Service sshd -Force
Write-Host "sshd PasswordAuthentication=yes, service restarted"

# 4) Ensure the MSA admin account is in Administrators
$msa = 'zqmco'
if (-not (Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'zqmco|zqmcomputing' })) {
  Add-LocalGroupMember -Group 'Administrators' -Member $msa -ErrorAction SilentlyContinue
  Write-Host "Added $msa to Administrators"
} else { Write-Host "$msa already admin" }

Write-Host "=== Done. MSA remote sign-in enabled. Re-test credential REMOTELY now. ==="
