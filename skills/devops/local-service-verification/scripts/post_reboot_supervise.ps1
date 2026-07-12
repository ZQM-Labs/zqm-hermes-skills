# post_reboot_supervise.ps1 — make a localhost service stack survive reboots/crashes.
# CLASS-LEVEL TEMPLATE. Run ONCE elevated (Administrator). Idempotent (Register-ScheduledTask -Force).
# Edit $Launcher to point at your stack starter (.bat/.ps1) per host.
$ErrorActionPreference = "Stop"

# === 1. AtStartup scheduled task: launches the stack on every boot (self-heal) ===
$Launcher = "C:\Users\zqmco\ZBit_api\start_zqm_stack.bat"   # <-- EDIT per host/stack
$action   = New-ScheduledTaskAction -Execute "cmd.exe" -Argument ("/c " + $Launcher)
$trigger  = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
              -ExecutionTimeLimit (New-TimeSpan -Hours 0)
# PITFALL: -LogonType ServiceAccount requires a BUILT-IN account (SYSTEM/NetworkService),
# NOT a regular domain/user account. Use SYSTEM so the task runs at boot with no logged-in
# user and no stored password. (Do NOT use -LogonType Password + a plaintext -Password.)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Limited
Register-ScheduledTask -TaskName "ZQM-Stack-Autostart" -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force
Write-Output "[+] Scheduled task 'ZQM-Stack-Autostart' registered (AtStartup, restart x3)."

# === 2. sshd auto-recover on crash (post-boot race mitigation) ===
Set-Service sshd -StartupType Automatic
& sc.exe failure sshd reset= 86400 actions= restart/1000/restart/1000/restart/1000 | Out-Null
$svc = Get-Service sshd
if ($svc.Status -ne 'Running') { Start-Service sshd; Write-Output "[+] sshd was stopped -> started" }
else { Write-Output "[+] sshd already Running" }

Write-Output "POST-REBOOT SUPERVISION APPLIED (local, reversible)."
