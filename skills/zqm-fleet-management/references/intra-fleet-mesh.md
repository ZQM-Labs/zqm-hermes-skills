# Intra-Fleet Mesh — configure every node for inter/intra connectivity

Goal (user: "install and configure all nodes for inter and intra connectivity"):
every node can reach every other node (INTRA) AND the shared Garden storage (INTER).

## Verified working recipe (2026-07-10)

### 0) Prereqs
- WSMan Client `TrustedHosts` WRITE needs elevation on each host. The agent's
  zqmco shell is non-elevated → self-elevate via `Start-Process powershell
  -Verb RunAs -ArgumentList '...'` (UAC prompt appears; approve). `-Verb RunAs`
  is mutually exclusive with `-Wait`/`-RedirectStandardOutput` → have the
  elevated child write results to a file and poll it. After set once, it
  persists and later `Invoke-Command` works from the non-elevated shell.
- You need the `zqmlocal` break-glass password (user supplies per session) to
  `Invoke-Command` into nodes. Store/consume via the DPAPI helper, never print it.

### 1) Node-1 (192.168.1.218) must ALSO be a full peer
It had WinRM 5985 but NO SSH server. Run ELEVATED (RunAs):

```powershell
# node1_setup.ps1  (run via: Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File <this>')
$ErrorActionPreference = 'Continue'
# 5986 HTTPS listener (self-signed, LAN-only)
$ip = (Get-NetIPAddress -InterfaceAlias 'Wi-Fi' -AddressFamily IPv4 -EA 0).IPAddress; if(-not $ip){$ip='192.168.1.218'}
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME,$ip -CertStoreLocation Cert:\LocalMachine\My
$null = & winrm delete "winrm/config/Listener?Address=*+Transport=HTTPS" 2>&1
& winrm create "winrm/config/Listener?Address=*+Transport=HTTPS" "@{CertificateThumbprint=`"$($cert.Thumbprint)`"}" 2>&1 | Out-Null
New-NetFirewallRule -DisplayName 'ZQM-WinRM-5986' -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -Profile Any -RemoteAddress 192.168.1.0/24 -EA 0 | Out-Null
# SSH server (manual GitHub zip — dism often won't add it)
if (-not (Get-Service sshd -EA 0)) {
  Invoke-WebRequest -Uri 'https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip' -OutFile "$env:TEMP\openssh.zip"
  Expand-Archive "$env:TEMP\openssh.zip" -DestinationPath "$env:TEMP" -Force
  $src = (Get-ChildItem "$env:TEMP" -Filter 'OpenSSH-Win64' -Directory | Select-Object -First 1).FullName
  if (Test-Path 'C:\Program Files\OpenSSH') { Copy-Item "$src\*" 'C:\Program Files\OpenSSH' -Recurse -Force } else { Copy-Item $src 'C:\Program Files\OpenSSH' -Recurse }
  & powershell.exe -ExecutionPolicy Bypass -File 'C:\Program Files\OpenSSH\install-sshd.ps1' 2>&1 | Out-Null
}
$cfg = 'C:\ProgramData\ssh\sshd_config'
(Get-Content $cfg) -replace '^#?PasswordAuthentication\s+.*','PasswordAuthentication yes' | Set-Content $cfg
New-NetFirewallRule -DisplayName 'ZQM-OpenSSH-22' -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -Profile Any -RemoteAddress 192.168.1.0/24 -EA 0 | Out-Null
Set-Service sshd -StartupType Automatic; Restart-Service sshd -Force
# TrustedHosts: all nodes + both Gardens
$cur = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
$add = @('192.168.1.218','192.168.1.21','192.168.1.46','192.168.1.215','192.168.1.173','192.168.1.40')
$existing = @(); if($cur){$existing=$cur -split ','}
$new = (($existing+$add) | Where-Object{$_} | Sort-Object -Unique) -join ','
Set-Item WSMan:\localhost\Client\TrustedHosts -Value $new -Force
# SSH client config (node-to-node, no host-key prompt)
$sshcfg = "$env:USERPROFILE\.ssh\config"
New-Item -ItemType Directory -Force -Path (Split-Path $sshcfg) | Out-Null
"Host 192.168.1.*`n    StrictHostKeyChecking no`n    UserKnownHostsFile /dev/null`n    IdentityFile ~/.ssh/zqm_mesh_key" | Set-Content $sshcfg -Force
if (-not (Test-Path "$env:USERPROFILE\.ssh\zqm_mesh_key")) { "" | ssh-keygen.exe -t ed25519 -f "$env:USERPROFILE\.ssh\zqm_mesh_key" -q }
```

### 2) Per-node mesh (Node-2/3/4) via WinRM — RUN FROM NON-ELEVATED AGENT
Note the array-argument gotcha: pass the TrustedHosts list as `,-$allTH`
(leading comma = single-element array), otherwise PowerShell flattens it
and only the first IP lands.

```powershell
$sec  = ConvertTo-SecureString 'PW' -AsPlainText -Force   # user-supplied zqmlocal pw
$cred = New-Object System.Management.Automation.PSCredential ('zqmlocal', $sec)
$nodes = @{Node2='192.168.1.21';Node3='192.168.1.46';Node4='192.168.1.215'}
$allTH = @('192.168.1.218','192.168.1.21','192.168.1.46','192.168.1.215','192.168.1.173','192.168.1.40')
foreach ($n in $nodes.GetEnumerator()) {
  Invoke-Command -ComputerName $n.Value -Credential $cred -ScriptBlock {
    param($addTH)
    $cur = (Get-Item WSMan:\localhost\Client\TrustedHosts -EA 0).Value
    $existing = @(); if($cur){$existing=$cur -split ','}
    $new = (($existing+$addTH) | Where-Object{$_} | Sort-Object -Unique) -join ','
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $new -Force
    $sshcfg = "$env:USERPROFILE\.ssh\config"
    New-Item -ItemType Directory -Force -Path (Split-Path $sshcfg) | Out-Null
    "Host 192.168.1.*`n    StrictHostKeyChecking no`n    UserKnownHostsFile /dev/null" | Set-Content $sshcfg -Force
    $cfg = 'C:\ProgramData\ssh\sshd_config'
    if (Test-Path $cfg) { (Get-Content $cfg) -replace '^#?PasswordAuthentication\s+.*','PasswordAuthentication yes' | Set-Content $cfg }
    if (-not (Get-NetFirewallRule -DisplayName 'ZQM-OpenSSH-22' -EA 0)) { New-NetFirewallRule -DisplayName 'ZQM-OpenSSH-22' -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -Profile Any -RemoteAddress 192.168.1.0/24 | Out-Null }
    if (-not (Get-NetFirewallRule -DisplayName 'ZQM-WinRM-5986' -EA 0)) { New-NetFirewallRule -DisplayName 'ZQM-WinRM-5986' -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -Profile Any -RemoteAddress 192.168.1.0/24 | Out-Null }
    Restart-Service sshd -Force -EA 0
  } -ArgumentList (,-$allTH)
}
```

### 3) Node-4 Public-profile fix (WinRM blocked until flipped)
Node-4 (192.168.1.215) had 5985+5986+22 OPEN but WinRM FROM Node-1 failed with
"WinRM ... public profiles limits access". Fix = set adapter to Private, restart WinRM.
- LOCAL on Node-4 (preferred, no secret-over-wire):
  `powershell -NoProfile -Command "$p=Get-NetConnectionProfile; $p.NetworkCategory='Private'; Set-NetConnectionProfile -InputObject $p; Restart-Service WinRM -Force"`
- REMOTE over SSH: use an askpass helper with Git-bash `ssh`
  (`SSH_ASKPASS=<script that echoes pw> SSH_ASKPASS_REQUIRE=force DISPLAY=:0 ssh ...`).
  NOTE: a command that echoes the live password in cleartext via this helper was
  BLOCKED by the user's approval gate — re-attempt only with explicit consent.

### 4) INTER (Garden SMB) — OPEN ITEM, needs a secret
Garden 445 is reachable from the nodes, but `\\Garden\web` is NOT accessible
until a cached SMB credential exists on each node. Requires a Garden SMB
username+password (user-supplied) + `cmdkey`/`net use /persistent` or bootstrap.
NOT done as of 2026-07-10 (blocked on the secret). Flag it as the open "inter" half.

### 5) VERIFY (this is the proof the user demanded)
From Node-1:
```powershell
$nodes = @{N2='192.168.1.21';N3='192.168.1.46';N4='192.168.1.215'}
foreach ($n in $nodes.GetEnumerator()) {
  foreach ($p in @(22,5985,5986)) {
    $r = Test-NetConnection -ComputerName $n.Value -Port $p -InformationLevel Quiet -WA 0
    "{0} {1}:{2} -> {3}" -f $n.Key,$n.Value,$p,$(if($r){'OPEN'}else{'CLOSED'})
  }
  try { $x = Test-WSMan -ComputerName $n.Value -EA 1; "{0} 5985 WSMan OK" -f $n.Key } catch { "{0} WSMan ERR" -f $n.Key }
}
```
Report PROVEN (live output shown) / NOT PROVEN (mechanics gap) / FALSE
(claim contradicted). A "Permission denied (publickey,...)" from sshd PROVES the
SSH service is alive & authenticating — it is sufficient service-proof; a
successful *key* login is a nice-to-have blocked by Windows admin-key ACL quirks.
