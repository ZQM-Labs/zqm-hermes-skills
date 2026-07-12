# Manual OpenSSH install over WinRM (when Dism refuses the capability)

## When this applies (pitfall #19 superset)
Node-2 (Windows 11) hit `Get-WindowsCapability` -> "Class not registered" (broken Dism PS COM).
The pitfall #19 `dism.exe /online /Add-Capability OpenSSH.Server~~~~0.0.1.0` fallback was tried
REMOTELY over WinRM -- dism.exe ran but the sshd service was STILL absent
(`Service sshd was not found on computer '.'`), and `Get-WindowsCapability` showed
`OpenSSH.Server : NotPresent`. So the node's **Dism/CBS store rejects the capability entirely**
-- not just the PS COM registration. `dism.exe` alone is NOT enough on such a host.

Definitive fix: **manual install of the official OpenSSH-Win64 release zip** (no Dism involved).

## Pre-check (run remote, before installing)
```powershell
$sec  = ConvertTo-SecureString '<zqmlocal-pw>' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ('zqmlocal', $sec)
Invoke-Command -ComputerName 192.168.1.21 -Credential $cred -ScriptBlock {
  (Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where Name -like 'OpenSSH*') | ForEach { "$($_.Name) : $($_.State)" }
  dism.exe /online /Get-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 2>&1 | Select-String 'State|OpenSSH'
  try { Get-Service sshd -ErrorAction Stop | Select Name,Status,StartType } catch { 'no sshd service' }
  try { (Invoke-WebRequest -Uri 'https://github.com' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop).StatusCode } catch { 'github NOT reachable' }
  @('C:\Windows\System32\OpenSSH\ssh.exe','C:\Program Files\OpenSSH\ssh.exe') | ForEach { if (Test-Path $_) { "FOUND $_" } else { "missing $_" } }
}
```
Verified this session: Server=NotPresent, no sshd, **github reachable (200)**, `ssh.exe` already present (Client pkg).
GitHub reachability is the only hard prereq for the manual path.

## Working recipe (ran end-to-end on Node-2 over WinRM 5985 -- SUCCEEDED)
```powershell
$sec  = ConvertTo-SecureString '<zqmlocal-pw>' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ('zqmlocal', $sec)
Invoke-Command -ComputerName 192.168.1.21 -Credential $cred -ScriptBlock {
  $dest = 'C:\Program Files\OpenSSH'
  $zip  = 'C:\zqm\OpenSSH-Win64.zip'
  New-Item -ItemType Directory -Force -Path C:\zqm | Out-Null
  # resolve latest release asset URL (don't hardcode a version)
  $api = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest' -Headers @{ 'User-Agent' = 'zqm' }
  $asset = ($api.assets | Where-Object { $_.name -eq 'OpenSSH-Win64.zip' })[0]
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $dest -Force
  # GitHub zip NESTS under OpenSSH-Win64\ -- locate install-sshd.ps1 and flatten up
  $f = Get-ChildItem -Path $dest -Recurse -Filter 'install-sshd.ps1' | Select-Object -First 1
  if ($f.DirectoryName -ne $dest) { Copy-Item -Path (Join-Path $f.DirectoryName '*') -Destination $dest -Recurse -Force }
  & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $dest 'install-sshd.ps1')
  New-NetFirewallRule -DisplayName 'ZQM-OpenSSH-22' -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -Profile Any -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue | Out-Null
  Set-Service sshd -StartupType Automatic
  Start-Service sshd
  "sshd status=$( (Get-Service sshd).Status ) port22=$( [bool](Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue) )"
}
```
Verified output: `sshd and ssh-agent services successfully installed`, `sshd status=Running startType=Automatic`,
`port22 listening=True`. From Node-1 a TCP probe then showed **:22 OPEN, :5985 OPEN, :5986 OPEN**.

## Agent-side: elevate TrustedHosts via RunAs (no need to hand it to the user)
The agent's zqmco PowerShell is NON-elevated, so `Set-Item WSMan:\localhost\Client\TrustedHosts`
fails "Access is denied". The agent CAN self-elevate with `Start-Process -Verb RunAs` (UAC prompt
appears on the user's desktop -- approve it). GOTCHAS:
- `-Verb RunAs` is in a DIFFERENT parameter set from `-RedirectStandardOutput` and from `-Wait`.
  Combining them throws `AmbiguousParameterSet`. Do NOT use redirection/`-Wait` with `-Verb RunAs`.
- Instead: the ELEVATED child script writes its own result to a file (e.g. `C:\...\ssh_result.txt`);
  the parent launches it, then polls/sleeps and reads the file.
```powershell
# child.ps1 (run elevated via RunAs) writes C:\...\ssh_result.txt itself
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File C:\path\child.ps1'
Start-Sleep 20; Get-Content C:\path\ssh_result.txt
```
After TrustedHosts is set once (persists), subsequent `Invoke-Command` calls run FINE from the
non-elevated agent shell -- the Set-Item WRITE needs admin, but the Invoke-Command auth does not.

## Result (this session)
Node-2 (Win11, 192.168.1.21): 5985 + 5986 + 22 all OPEN and reachable from Node-1 over WinRM.
3/3 nodes (2/3/4) fully failover-capable. The "Node-2 SSH N/A by edition" note elsewhere in the
skill is OVERRIDDEN -- Node-2 is Win11 and OpenSSH is installable via the manual path above.
