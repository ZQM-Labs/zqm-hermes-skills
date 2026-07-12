# ollama_fw_rule.ps1 — ADDITIVE, scoped inbound allow for Ollama :11434.
# Stops relying on the default-profile non-block for a LAN-exposed service. Limits access
# to the trusted 192.168.1.0/24 so the endpoint is intentionally scoped, not silently open
# if the box roams onto another network. Additive only — cannot break existing LAN access.
# REQUIRES ELEVATED (admin) PowerShell: powershell -NoProfile -ExecutionPolicy Bypass -File <this>
param(
    [string]$RuleName  = 'Ollama-LAN-only-11434',
    [string]$Subnet    = '192.168.1.0/24',
    [int]   $Port      = 11434
)
$ErrorActionPreference = 'Stop'
$existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Rule '$RuleName' already exists — skipping create."
} else {
    New-NetFirewallRule -DisplayName $RuleName `
        -Direction Inbound -LocalPort $Port -Protocol TCP `
        -RemoteAddress $Subnet -Action Allow -Profile Any -Enabled True
    Write-Host "CREATED rule '$RuleName' (inbound $Port, TCP, remote $Subnet, Allow)."
}
Get-NetFirewallRule -DisplayName $RuleName | Get-NetFirewallAddressFilter | ForEach-Object { Write-Host ("  RemoteAddress: $($_.RemoteAddress)") }
Get-NetFirewallRule -DisplayName $RuleName | Get-NetFirewallPortFilter   | ForEach-Object { Write-Host ("  Port: $($_.LocalPort)  Protocol: $($_.Protocol)") }
# Pre-check before applying: confirm no allow rule for 11434 exists yet, else REC is moot.
#   Get-NetFirewallRule -DisplayName 'Ollama-LAN-only-11434' -ErrorAction SilentlyContinue
