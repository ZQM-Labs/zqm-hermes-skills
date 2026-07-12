# TEMPLATE: remote WinRM probe of a fleet peer from the non-elevated control-plane shell.
# Safe-credential pattern: prompt at runtime, never embed the password.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File probe_remote_winrm.ps1
# Then enter the remote node's Administrator password when prompted.
$ErrorActionPreference = 'Stop'
$nodeIp = '192.168.1.46'          # <-- set target node IP
$user   = "$nodeIp\Administrator"

# 0) Reachability check (no creds needed) — fail fast + clearly if host/WinRM down
try {
    $ws = Test-WSMan -ComputerName $nodeIp -ErrorAction Stop
    Write-Host ("WSMan reachable on $nodeIp ($($ws.ProductVendor))")
} catch {
    Write-Host ("WINRM UNREACHABLE on $nodeIp : " + $_.Exception.Message)
    exit 1
}

# 1) Prompt for the password securely (never stored, never printed)
$sec = Read-Host -Prompt ("$user password") -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($user, $sec)
$opt  = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck

try {
    $sess = New-PSSession -ComputerName $nodeIp -Credential $cred `
        -Authentication Basic -SessionOption $opt -ErrorAction Stop
    Write-Host "SESSION OPEN to $nodeIp"
    $res = Invoke-Command -Session $sess -ScriptBlock {
        $o = [ordered]@{}
        $o.Host = $env:COMPUTERNAME
        # Is Ollama listening locally, and on which address?
        $tcp = Get-NetTCPConnection -LocalPort 11434 -ErrorAction SilentlyContinue
        $o.OllamaLocalBind = if ($tcp) { ($tcp.LocalAddress | Sort-Object -Unique) -join ',' } else { 'NOT LISTENING LOCALLY' }
        $p = Get-Process ollama -ErrorAction SilentlyContinue
        $o.OllamaProcess = if ($p) { 'RUNNING (PID ' + ($p.Id -join ',') + ')' } else { 'NOT RUNNING' }
        try {
            $tags = Invoke-RestMethod -Uri http://127.0.0.1:11434/api/tags -TimeoutSec 5
            $o.ModelsInstalled = $tags.models.Count
            $o.Models = $tags.models | ForEach-Object { "$($_.name) ($([math]::Round($_.size/1GB,2)) GB)" }
        } catch {
            $o.ModelsInstalled = 'n/a (localhost API failed: ' + $_.Exception.Message + ')'
        }
        [pscustomobject]$o
    }
    $res | Format-List
    Remove-PSSession $sess
} catch {
    Write-Host ("REMOTE EXEC FAILED: " + $_.Exception.Message)
    exit 1
}
