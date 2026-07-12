# read_system_file.ps1 — elevated reader for SYSTEM-owned files the non-elevated shell can't read.
# Usage (elevated):  .\read_system_file.ps1 -File "C:\ProgramData\ssh\ssh_host_ed25519_key.pub" -Log "out.log"
# Copy the target's content into a user-readable .log so the agent can read_file it after RunAs.
param(
    [Parameter(Mandatory=$true)]  [string] $File,
    [Parameter(Mandatory=$false)] [string] $Log = "C:\Users\zqmco\swarm\read_system_file.log"
)
function out($s){ Add-Content -Path $Log -Value $s }
out ("=== read_system_file started " + (Get-Date) + " ===")
out ("TARGET: $File")
try {
    if (-not (Test-Path $File)) { out "  NOT FOUND"; out ("=== finished " + (Get-Date) + " ==="); exit 0 }
    $c = Get-Content $File -ErrorAction Stop
    foreach ($l in $c) { out $l }
    out ("=== finished " + (Get-Date) + " (lines=" + $c.Count + ") ===")
} catch {
    out ("  DENIED: " + $_.Exception.Message)
    out ("=== finished " + (Get-Date) + " ===")
}
