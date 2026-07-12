# firewall_lan_ollama.ps1 (TEMPLATE)
# Locks Ollama :11434 on each Ollama host so ONLY the LiteLLM proxy IP can reach it.
# This is the REAL fix for Ollama's "no native auth" exposure. Run on EACH Ollama host
# (Node-4 .215, Node-2 .21, Node-1 .218), as Admin:
#   powershell -NoProfile -ExecutionPolicy Bypass -File firewall_lan_ollama.ps1
$ProxyIP = "192.168.1.215"   # <-- IP of the LiteLLM proxy host
$Port   = 11434
Remove-NetFirewallRule -DisplayName "Ollama-Allow-ProxyOnly" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Ollama-Block-All" -Direction Inbound -Action Block -Protocol TCP -LocalPort $Port -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Ollama-Allow-ProxyOnly" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress $ProxyIP
Write-Host "Locked Ollama :$Port to proxy $ProxyIP only."
