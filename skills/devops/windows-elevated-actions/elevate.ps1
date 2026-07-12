# Reusable elevated-launch helper for windows-elevated-actions.
# USAGE: powershell -NoProfile -ExecutionPolicy Bypass -File elevate.ps1 "<target.ps1>"
# The target script MUST self-log its result to a .log file (see SKILL.md).
param(
    [Parameter(Mandatory=$true)]
    [string]$TargetScript
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $TargetScript)) {
    Write-Host ("TARGET MISSING: " + $TargetScript); exit 1
}
Write-Host ("ELEVATED LAUNCH: " + $TargetScript + "  (UAC prompt appears on desktop)")
try {
    Start-Process powershell -Verb RunAs -Wait `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$TargetScript`""
    Write-Host "process returned — READ THE SCRIPT'S .log TO CONFIRM (do not trust this message)."
} catch {
    Write-Host ("LAUNCH ERROR: " + $_.Exception.Message)
}
