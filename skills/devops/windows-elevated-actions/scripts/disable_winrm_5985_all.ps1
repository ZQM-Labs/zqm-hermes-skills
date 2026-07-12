# disable_winrm_5985_all.ps1 — disable EVERY inbound WinRM 5985 rule (handles DUPLICATE rules
# sharing the same DisplayName, e.g. two "Windows Remote Management (HTTP-In)" entries).
# Elevated, self-logging. Keeps 5986 (TLS) untouched.
$log = Join-Path $PSScriptRoot "disable_winrm_5985_all.log"
function out($s){ Add-Content -Path $log -Value $s }
out ("=== disable_winrm_5985_all started " + (Get-Date) + " ===")
Get-NetFirewallRule | Where-Object { $_.Direction -eq "Inbound" } | ForEach-Object {
    $pf = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    if ($pf -and $pf.LocalPort -eq 5985 -and $pf.Protocol -eq "TCP") {
        try {
            $_ | Disable-NetFirewallRule -ErrorAction Stop
            $af = $_ | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
            out ("  DISABLED: $($_.DisplayName) [remote=$($af.RemoteAddress)]")
        } catch {
            out ("  FAIL disabling $($_.DisplayName): " + $_.Exception.Message)
        }
    }
}
out ("=== finished " + (Get-Date) + " ===")
$still = Get-NetFirewallRule | Where-Object { $_.Direction -eq "Inbound" } | ForEach-Object {
    $pf = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    if ($pf -and $pf.LocalPort -eq 5985 -and $_.Enabled) { $_ }
}
if ($still) { out ("  WARN: still Enabled: " + ($still.DisplayName -join ", ")) } else { out "  VERIFY: no Enabled inbound 5985 rules remain" }
