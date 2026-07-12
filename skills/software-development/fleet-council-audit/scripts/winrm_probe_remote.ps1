# winrm_probe_remote.ps1 — inspect a peer Windows node from the control plane via WinRM.
# Parameterized for the ZQM fleet (and any WinRM-basic Windows peer). Prompts for the
# remote password securely (Read-Host -AsSecureString) — NEVER embed secrets in this file.
param(
    [string]$ComputerIP = '192.168.1.46',
    [string]$User       = 'Administrator',
    [string]$Probe      = 'ollama'   # 'ollama' = list local bind + process + models; 'ports' = open ports
)
$ErrorActionPreference = 'Stop'
$fq = "$ComputerIP\$User"
$sec = Read-Host -Prompt "Password for $fq" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential($fq, $sec)
$opt  = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
try {
    $sess = New-PSSession -ComputerName $ComputerIP -Credential $cred -Authentication Basic -SessionOption $opt -ErrorAction Stop
    Write-Host "WINRM SESSION OPEN to $ComputerIP"
    $res = Invoke-Command -Session $sess -ScriptBlock {
        param($Probe)
        $o = [ordered]@{}
        $o.Host = $env:COMPUTERNAME
        if ($Probe -eq 'ollama') {
            $tcp = Get-NetTCPConnection -LocalPort 11434 -ErrorAction SilentlyContinue
            $o.OllamaLocalBind = if ($tcp) { ($tcp.LocalAddress | Sort-Object -Unique) -join ',' } else { 'NOT LISTENING LOCALLY' }
            $p = Get-Process ollama -ErrorAction SilentlyContinue
            $o.OllamaProcess = if ($p) { 'RUNNING (PID ' + ($p.Id -join ',') + ')' } else { 'NOT RUNNING' }
            try {
                $tags = Invoke-RestMethod -Uri http://127.0.0.1:11434/api/tags -TimeoutSec 5
                $o.ModelsInstalled = $tags.models.Count
                $o.Models = $tags.models | ForEach-Object { "$($_.name) ($([math]::Round($_.size/1GB,2)) GB)" }
            } catch { $o.ModelsInstalled = 'n/a (localhost API failed: ' + $_.Exception.Message + ')' }
        } elseif ($Probe -eq 'ports') {
            $o.OpenPorts = (Get-NetTCPConnection -State Listen | Select-Object -ExpandProperty LocalPort | Sort-Object -Unique) -join ','
        }
        [pscustomobject]$o
    } -ArgumentList $Probe
    $res | Format-List
    Remove-PSSession $sess
} catch {
    Write-Host ("WINRM FAILED: " + $_.Exception.Message)
    exit 1
}
# Notes: WSMan must be reachable on the peer (Test-WSMan -ComputerName <ip>). The creds in
# inventory.ini use Administrator + basic + ignore-cert, which matches the -Skip* options.
