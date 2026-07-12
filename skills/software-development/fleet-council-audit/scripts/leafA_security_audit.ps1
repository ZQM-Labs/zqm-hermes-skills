# LEAF A — Node-1 Security & Services audit (CANONICAL, fast + correct)
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File leafA_security_audit.ps1 > leafA_raw.txt 2>&1
# Fixes vs first attempt: firewall uses netsh dump+parse (the Get-NetFirewallPortFilter
# per-rule loop timed out + lied); service classifier uses EXACT name sets (no loose
# substrings => no Power/PcaSvc false positives); Ollama reported as a PROCESS.
$ErrorActionPreference = 'SilentlyContinue'
function H($t){ Write-Output ""; Write-Output "===== $t =====" }

H "HOST"
Write-Output ("ComputerName : " + $env:COMPUTERNAME)
Write-Output ("Timestamp    : " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

H "RUNNING SERVICES (grouped, exact-name classification)"
$svc = Get-Service | Where-Object { $_.Status -eq 'Running' } | Sort-Object Name
Write-Output ("Total running: " + $svc.Count)
$ASUS   = @('AsusAppService','ASUSOptimization','ASUSSoftwareManager','ASUSSwitch','ASUSSystemAnalysis','ASUSSystemDiagnosis')
$REMOTE = @('sshd','WinRM')
$CONT   = @('hns','vmcompute','vmms')
$TELEM  = @('DiagTrack','dmwappushservice','RetailDemo','OneCollectSvc')
$groups = @{ 'remote-mgmt' = @(); 'container' = @(); 'ASUS-bloat' = @(); 'telemetry' = @(); 'system' = @() }
foreach ($s in $svc){
  $n = $s.Name
  if ($REMOTE -contains $n){ $groups['remote-mgmt'] += $n }
  elseif ($CONT -contains $n){ $groups['container'] += $n }
  elseif ($ASUS -contains $n){ $groups['ASUS-bloat'] += $n }
  elseif ($TELEM -contains $n){ $groups['telemetry'] += $n }
  else { $groups['system'] += $n }
}
foreach ($k in ($groups.Keys | Sort-Object)){
  Write-Output ("--- GROUP: "+$k+" ("+$groups[$k].Count+")")
  foreach ($l in $groups[$k]){ Write-Output ("  "+$l) }
}
Write-Output "NOTE: Ollama is NOT a service (runs as user process) - see port census."

H "WINRM"
$wr = Get-Service WinRM
Write-Output ("WinRM service : Status="+$wr.Status+" StartType="+$wr.StartType)
$lp = (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in @(5985,5986) } | Select-Object LocalPort,LocalAddress)
if ($lp){ $lp | ForEach-Object { Write-Output ("Listening: "+$_.LocalAddress+":"+$_.LocalPort) } } else { Write-Output "5985/5986 NOT listening" }
Write-Output "WSMan provider listener query may misreport non-elevated; treat TCP state as authoritative."

H "SSHD"
$ss = Get-Service sshd -ErrorAction SilentlyContinue
if ($ss){ Write-Output ("sshd service  : Status="+$ss.Status+" StartType="+$ss.StartType) } else { Write-Output "sshd service: NOT present" }
$slp = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 22 }
if ($slp){ $slp | ForEach-Object { Write-Output ("Listening: "+$_.LocalAddress+":22") } } else { Write-Output "22 NOT listening" }
$cfg = 'C:\ProgramData\ssh\sshd_config'
if (Test-Path $cfg){
  Get-Content $cfg | Where-Object { $_ -match 'PasswordAuthentication|PubkeyAuthentication|PermitRootLogin' } | ForEach-Object { Write-Output ("  "+$_.Trim()+"  (commented=>default ON unless explicitly set)") }
}

H "FIREWALL (netsh dump + parse - fast, authoritative)"
$tmp = [System.IO.Path]::GetTempFileName()
netsh advfirewall firewall show rule name=all dir=in verbose > $tmp
$raw = Get-Content $tmp -Raw
$blocks = $raw -split '(?m)^Rule Name:\s*'
$rules = @()
foreach ($b in $blocks){
  if ($b -notmatch '\S'){ continue }
  $lines = $b -split "`r?`n"
  $name = $lines[0].Trim()
  $port = (($lines | Where-Object { $_ -match 'LocalPort\s*:\s*(.+)' } | ForEach-Object { $Matches[1].Trim() }) -join ',')
  $action  = if ($b -match 'Action\s*:\s*(.+)')    { $Matches[1].Trim() } else { '' }
  $enabled = if ($b -match 'Enabled\s*:\s*(.+)')   { $Matches[1].Trim() } else { '' }
  $dir     = if ($b -match 'Direction\s*:\s*(.+)') { $Matches[1].Trim() } else { '' }
  $profile = if ($b -match 'Profiles\s*:\s*(.+)')  { $Matches[1].Trim() } else { '' }
  $rules += [PSCustomObject]@{Name=$name;Ports=$port;Action=$action;Enabled=$enabled;Dir=$dir;Profile=$profile}
}
Remove-Item $tmp -Force
foreach ($p in @(22,5985,5986,11434,18789,5000,9000)){
  $hits  = $rules | Where-Object { ($_.Ports -split ',' | ForEach-Object { $_.Trim() }) -contains "$p" }
  $allow = $hits | Where-Object { $_.Action -eq 'Allow' -and $_.Enabled -eq 'Yes' }
  if ($allow){ Write-Output ("Port $p : ALLOW/Enabled -> "+($allow.Name -join ' | ')) }
  elseif ($hits){ Write-Output ("Port $p : rule exists but NOT Allow+Enabled -> "+($hits.Name -join ' | ')) }
  else { Write-Output ("Port $p : NO inbound rule") }
}

H "STARTUP TASKS (scheduled, AtStartup/AtLogOn)"
$st = Get-ScheduledTask
$startup = $st | Where-Object { $_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'AtStartup|AtLogOn|BootTrigger|LogonTrigger' } }
Write-Output ("Scheduled tasks total: "+$st.Count+", startup/logon-type: "+$startup.Count)
$startup | ForEach-Object { Write-Output ("  "+$_.TaskName+" | State="+$_.State+" | Logon="+$_.Principal.LogonType) }

H "RUN KEYS"
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce')){
  Write-Output ("--- "+$k)
  (Get-ItemProperty $k -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { Write-Output ("  "+$_.Name+" = "+$_.Value) }
}

H "DEFENDER"
$mp = Get-MpPreference
Write-Output ("DisableRealtimeMonitoring : "+$mp.DisableRealtimeMonitoring)
$cst = Get-MpComputerStatus
Write-Output ("RealTimeProtectionEnabled: "+$cst.RealTimeProtectionEnabled)
Write-Output ("AntivirusEnabled         : "+$cst.AntivirusEnabled)

H "DIAGTRACK"
$dt = Get-Service DiagTrack
Write-Output ("DiagTrack : Status="+$dt.Status+" StartType="+$dt.StartType)

H "LISTENING PORTS (full census)"
$cons = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort
foreach ($c in $cons){
  $proc = (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).Name
  if (-not $proc){ $proc = ('PID:'+$c.OwningProcess) }
  Write-Output (("{0,-22} {1,-7} {2}" -f ($c.LocalAddress+':'+$c.LocalPort), $c.LocalPort, $proc))
}
Write-Output ("Total listening: "+$cons.Count)
