# disable_winrm_5985_listener.ps1 — Remove ONLY the WinRM HTTP (5985) listener,
# preserving HTTPS (5986). Elevated (RunAs), self-logging.
#
# WHY THIS SCRIPT EXISTS: `Remove-Item WSMan:\localhost\Listener\*` (wildcard) drops BOTH
# the HTTP AND HTTPS listener objects — verified 2026-07-11 (killing 5985 also killed 5986).
# Target the specific HTTP listener PATH instead so HTTPS survives.
#
# If HTTPS still vanishes anyway, re-create it with the CORRECTED command (writes to the log):
#   New-Item WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbprint <thumb> -Force
#   Restart-Service WinRM
# (the bare command WITHOUT -Address * fails: "Cannot validate argument on parameter 'Address'")
$log = "C:\Users\zqmco\swarm\2026-07-11_fleet_audit\disable_winrm_5985_listener.log"
function out($s){ Add-Content -Path $log -Value $s }
out ("=== disable_winrm_5985_listener started " + (Get-Date))
try {
    $listeners = Get-ChildItem WSMan:\localhost\Listener -ErrorAction Stop
    $http = $listeners | Where-Object { ($_.Keys -join ',') -match 'Transport=HTTP' }
    out ("  listeners BEFORE: " + (($listeners | ForEach-Object { $_.Keys -join ',' }) -join ' | '))
    if (-not $http) {
        out "  no HTTP listener present - 5985 already closed."
    } else {
        foreach ($l in $http) {
            $p = $l.PSPath
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
            out ("  removed HTTP listener: " + ($l.Keys -join ','))
        }
    }
    $after = Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue
    $surv = if ($after) { ($after | ForEach-Object { $_.Keys -join ',' }) -join ' | ' } else { '(none)' }
    out ("  listeners AFTER: " + $surv)
    if ($surv -match 'HTTPS') { out "  OK: HTTPS (5986) listener preserved." }
    else { out "  WARN: no HTTPS listener survived. Re-create with -Address * + cert thumbprint, or accept WinRM fully off." }
} catch {
    out ("  FAILED: " + $_.Exception.Message)
}
out ("=== disable_winrm_5985_listener finished " + (Get-Date))
