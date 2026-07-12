# Add an EXPLICIT scoped ALLOW for Ollama :11434 from the trusted /24.
# REQUIRES ELEVATED PowerShell. Self-logs to C:\Users\zqmco\rec2_result.log.
# Additive only — does not remove existing LAN access.
param(
    [string]$RuleName = 'Ollama-LAN-only-11434',
    [int]$Port = 11434,
    [string]$Remote = '192.168.1.0/24'
)
$log = "C:\Users\zqmco\rec2_result.log"
try {
    if (-not (Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -LocalPort $Port `
            -Protocol TCP -RemoteAddress $Remote -Action Allow -Profile Any -Enabled True -ErrorAction Stop
        "CREATED" | Set-Content $log
    } else {
        "EXISTS" | Set-Content $log
    }
} catch {
    ("FAILED: " + $_.Exception.Message) | Set-Content $log
}
"RESULT: " + (Get-Content $log)
