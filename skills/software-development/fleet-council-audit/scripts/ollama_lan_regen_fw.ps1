# ollama_lan_regen_fw.ps1 — RE-GATE an open LAN Ollama by firewall (no restart).
# Complement to ollama_fw_rule.ps1 (which ADDS an allow). This CLOSES the LAN while
# keeping loopback so a LOCAL proxy that routes 127.0.0.1:11434 keeps working.
# Self-logging. REQUIRES ELEVATED (admin) PowerShell:
#   powershell -NoProfile -ExecutionPolicy Bypass -File <this>
# REVERSIBLE: netsh advfirewall firewall delete rule name="ZQM-Ollama-LAN-Block"
#             netsh advfirewall firewall delete rule name="ZQM-Ollama-Loopback-Allow"
$ErrorActionPreference = 'Stop'
$log = "C:\Users\zqmco\ZBit_api\n1_regate_firewall.log"
$lines = @()
try {
    $lines += "=== BASELINE 11434 rules before ==="
    $lines += (netsh advfirewall firewall show rule name=all | Select-String "11434")

    # Block the LAN subnet from reaching 11434 (Block > Allow precedence wins)
    $r1 = netsh advfirewall firewall add rule name="ZQM-Ollama-LAN-Block" `
        dir=in action=block protocol=TCP localport=11434 remoteip=192.168.1.0/24 2>&1
    $lines += "ADD LAN-Block: $r1"

    # Explicitly keep loopback open (proxy N3 -> 127.0.0.1:11434)
    $r2 = netsh advfirewall firewall add rule name="ZQM-Ollama-Loopback-Allow" `
        dir=in action=allow protocol=TCP localport=11434 remoteip=127.0.0.1 2>&1
    $lines += "ADD Loopback-Allow: $r2"

    $lines += "=== RULES AFTER ==="
    $lines += (netsh advfirewall firewall show rule name=all | Select-String "ZQM-Ollama")
    Set-Content -Path $log -Value $lines
} catch {
    Set-Content -Path $log -Value ("ERROR: " + $_.Exception.Message)
}
# VERIFY (loopback must still answer — proves proxy N3 unaffected):
#   curl -s -m 6 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:11434/api/tags  -> 200
# OFF-BOX enforcement can ONLY be proven from a different /24 host (see
# references/windows-firewall-loopback-blindspot.md).
