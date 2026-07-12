# silent_recon_skeleton.ps1 — FULL PASSIVE read-only recon. No Set/New/Disable/Stop anywhere.
# Outputs everything to a single .txt. Safe to run non-elevated (elevated only needed for a few
# reads that will DENY — those are wrapped in try/catch and reported as DENIED, never fatal).
# Uses the -f format operator everywhere so a literal "[" bracket never aborts the script (P7).
# Copy + extend per host; do not add mutating cmdlets.
param(
  [string]$Out = "C:\Users\zqmco\swarm\recon_silent.txt"
)
$ErrorActionPreference = 'SilentlyContinue'
function w([string]$s){ Add-Content -Path $Out -Value $s }
$runtime = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
w ("SILENT RECON runtime={0} host={1} user={2}" -f $runtime,$env:COMPUTERNAME,$env:USERNAME)

w "`n[1] SYSTEM"
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$mem = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
w ("OS: {0} Build {1} ({2})" -f $os.Caption,$os.BuildNumber,$os.OSArchitecture)
w ("Install: {0}  LastBoot: {1}" -f $os.InstallDate,$os.LastBootUpTime)
w ("CPU: {0} Cores={1} Logical={2}" -f $cpu.Name,$cpu.NumberOfCores,$cpu.NumberOfLogicalProcessors)
w ("RAM total: {0} GB" -f [math]::Round($mem.Sum/1GB,1))
Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Used -gt 0} | ForEach-Object { w ("DISK {0}: used={1}GB free={2}GB" -f $_.Name,[math]::Round($_.Used/1GB,1),[math]::Round($_.Free/1GB,1)) }

w "`n[2] LISTENING + ESTABLISHED SOCKETS"
Get-NetTCPConnection | Where-Object {$_.State -in @('Listen','Established')} | Sort-Object State,LocalPort | ForEach-Object {
  $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name
  w ("{0} {1}:{2} -> {3}:{4} [{5} PID={6}]" -f $_.State,$_.LocalAddress,$_.LocalPort,$_.RemoteAddress,$_.RemotePort,$p,$_.OwningProcess)
}

w "`n[3] FIREWALL (all rules, port+address filter — never by DisplayName alone)"
Get-NetFirewallRule | ForEach-Object {
  $pf = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
  $af = $_ | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
  $mark = if ($_.Enabled -eq $true) {'ON '} else {'off'}
  w ("[{0}] {1} {2} port={3}/{4} remote={5}" -f $mark,$_.Direction,$_.DisplayName,$pf.LocalPort,$pf.Protocol,$af.RemoteAddress)
}

w "`n[4] LOCAL USERS + ADMIN GROUP"
Get-LocalUser | ForEach-Object { w ("USER {0} Enabled={1} LastLogon={2} SID={3}" -f $_.Name,$_.Enabled,$_.LastLogon,$_.SID.Value) }
(Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue) | ForEach-Object { w ("ADMIN: {0} ({1})" -f $_.Name,$_.PrincipalSource) }

w "`n[5] SMB SHARES"
Get-SmbShare | ForEach-Object { w ("SHARE \\{0}\{1} path={2}" -f $env:COMPUTERNAME,$_.Name,$_.Path) }

w "`n[6] INSTALLED SOFTWARE (registry)"
$keys = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*","HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
$apps = @()
foreach ($k in $keys) { $apps += Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName} | Select-Object DisplayName,DisplayVersion,Publisher }
$apps | Sort-Object DisplayName -Unique | Select-Object -First 80 | ForEach-Object { w ("APP {0} v{1} [{2}]" -f $_.DisplayName,$_.DisplayVersion,$_.Publisher) }
w ("APP COUNT: {0}" -f $apps.Count)

w "`n[7] DEFENDER (elevated-only fields may DENY — reported, not fatal)"
try { Get-MpComputerStatus | ForEach-Object { w ("Defender: AM={0} AS={1} AV={2} RT={3} Tamper={4}" -f $_.AMServiceEnabled,$_.AntispywareEnabled,$_.AntivirusEnabled,$_.RealTimeProtectionEnabled,$_.IsTamperProtected) } } catch { w "Defender status: DENIED (needs elevation)" }

w "`n[8] QUICK SECURITY POSTURE"
$rdb = (Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
w ("RDP enabled: {0}" -f ($rdb -eq 0))
w ("WinRM service: {0}" -f (Get-Service WinRM).Status)
w ("sshd service: {0}" -f (Get-Service sshd).Status)
w ("Ollama listening sockets: {0}" -f (Get-NetTCPConnection -LocalPort 11434 -State Listen -ErrorAction SilentlyContinue).Count)
w ("authorized_keys present: {0}" -f (Test-Path "$env:USERPROFILE\.ssh\authorized_keys"))

w "`nEND SILENT RECON"
