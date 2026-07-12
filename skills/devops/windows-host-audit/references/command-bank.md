# Windows host audit — read-only command bank (all proven live 2026-07-10)

Run every command through git-bash/MSYS:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '<SINGLE-QUOTED PS>'

NEVER double-quote the PS command — bash expands $_ / $() and mangles it.

For multi-line / loop audits, WRITE A .ps1 and run `-File` through the
`cygpath -w` shim (MSYS strips backslashes otherwise):
  runps() { local w=$(cygpath -w "$1"); powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$w" 2>&1; }
  runps /c/Users/zqmco/inv.ps1

## HOST IDENTITY / OS
# Authoritative OS (corrects Get-ComputerInfo's lagging "Windows 10" string on 24H2):
(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture,BuildNumber | Format-List | Out-String).Trim()
# Alt product string (CAN lie on 24H2 — says "Windows 10"):
Get-ComputerInfo | Select-Object WindowsProductName,WindowsVersion,OsInstallDate,OsLastBootUpTime
hostname
(Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,HyperVisorPresent,NumberOfLogicalProcessors,TotalPhysicalMemory | Format-List | Out-String).Trim()

## CPU / RAM / UPTIME
Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize,FreePhysicalMemory
((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToString()

## GPU
Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM | Format-Table -AutoSize

## STORAGE
Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free | Format-Table -AutoSize
Get-CimInstance Win32_DiskDrive | Select-Object Model,Size | Format-Table -AutoSize
Get-CimInstance Win32_BaseBoard | Select-Object Product,SerialNumber
Get-CimInstance Win32_BIOS | Select-Object SMBIOSBIOSVersion,ReleaseDate

## NETWORK
# Adapters + MAC + link speed + status:
Get-NetAdapter | Select-Object Name,MacAddress,LinkSpeed,Status | Format-Table -AutoSize
# IPs:
Get-NetIPAddress | Select-Object InterfaceAlias,IPAddress,PrefixLength,AddressFamily | Format-Table -AutoSize
# Gateway + DNS:
Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object NextHop
Get-DnsClientServerAddress | Select-Object InterfaceAlias,ServerAddresses | Format-Table -AutoSize
# Wi-Fi SSID:
netsh wlan show interfaces
# Listening ports + TCP states:
Get-NetTCPConnection | Group-Object State | Select-Object Name,Count
Get-NetTCPConnection -State Listen | Select-Object LocalPort,OwningProcess,LocalAddress | Sort-Object LocalPort | Format-Table -AutoSize

## SECURITY / SERVICES
(Get-Service | Where-Object {$_.Status -eq "Running"}).Count
Get-Service | Where-Object {$_.Status -eq "Running"} | Select-Object -ExpandProperty DisplayName
# Fleet-relevant services:
Get-Service | Where-Object {$_.Status -eq "Running"} | Select-Object -ExpandProperty DisplayName | Select-String 'ollama|hyper|ssh|docker|vmcompute|wsl|remote'
# RDP on?
(Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections).fDenyTSConnections   # 1 = disabled
# UAC:
(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA).EnableLUA   # 1 = on
Get-NetFirewallProfile | Select-Object Name,Enabled
(Get-MpComputerStatus | Select-Object AntivirusEnabled,RealTimeProtectionEnabled | Format-List | Out-String).Trim()
Get-LocalUser | Select-Object Name,Enabled,LastLogon | Format-Table -AutoSize
Get-ScheduledTask | Measure-Object | Select-Object -ExpandProperty Count
Get-CimInstance Win32_StartupCommand | Select-Object Name,Command,Location | Format-Table -AutoSize
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10 HotFixID,InstalledOn | Format-Table -AutoSize

## SOFTWARE / TOOLCHAIN
winget --version
git --version
node --version ; npm --version
python --version   # NOTE: python3 is MS Store alias — use `python`
uv --version
go version
docker --version
powershell.exe -NoProfile -Command '$PSVersionTable.PSVersion'
# Custom profile presence:
Test-Path $PROFILE ; (Get-Item $PROFILE).Length   # in PS; from bash, profile lives at ~/OneDrive/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1
# Installed apps (registry):
Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Select-Object DisplayName,DisplayVersion | Where-Object {$_.DisplayName} | Sort-Object DisplayName | Format-Table -AutoSize

## LIVE OLLAMA PROBE (Node-1 = 192.168.1.218)
curl -s --max-time 5 http://127.0.0.1:11434/api/tags
curl -s --max-time 5 http://192.168.1.218:11434/api/tags   # LAN exposure check
# Model count + sizes:
curl -s --max-time 5 http://127.0.0.1:11434/api/tags | python.exe -c "import sys,json; d=json.load(sys.stdin); print(len(d['models']),'models'); [print(' -',m['name'],round(m['size']/1e9,1),'GB') for m in d['models']]"

## SCHEDULED TASKS — FULL CUSTOM AUDIT (automation surface)
Count only: `Get-ScheduledTask | Measure-Object | Select-Object -ExpandProperty Count`
Full inventory of what each automation EXECUTES (real deliverable): filter out the
noisy \Microsoft\Windows\* and \Microsoft\* vendor tasks, then dump per-task
State / Triggers / Actions / LastRunTime / LastTaskResult. Multi-line + loops →
write a .ps1 and run via `-File` (see MSYS quoting gotcha in SKILL.md §0; translate
path with `cygpath -w`). Proven recipe:

  $custom = Get-ScheduledTask | Where-Object {
      $_.TaskPath -notlike '\Microsoft\Windows\*' -and $_.TaskPath -notlike '\Microsoft\*'
  }
  foreach ($t in $custom) {
      "TASK: $($t.TaskPath)$($t.TaskName)"; "State: $($t.State)"
      "--- Triggers ---"
      foreach ($tr in $t.Triggers) {
          # GOTCHA: $tr.GetType().Name is just "CimInstance" — does NOT tell you
          # Logon vs Time vs OnUnlock. Read PROPERTIES instead:
          #   Repetition.Interval = ISO8601 (P1D=daily, PT15M=15min, PT1M=1min, ''=none)
          #   StartBoundary = '' for AtLogon/AtStartup triggers, populated for Time/OnUnlock
          $rep = if ($tr.Repetition) { $tr.Repetition.Interval } else { '' }
          "  Repetition=$rep StartBoundary=$($tr.StartBoundary)"
      }
      "--- Actions ---"
      foreach ($a in $t.Actions) {
          if ($a.Execute -ne $null) {        # Executable action
              "  Execute: $($a.Execute)"; "  Arguments: $($a.Arguments)"
          } elseif ($a.ClassId -ne $null) {  # COM-handler task (no exe — loads CLSID)
              "  ComHandler ClassId: $($a.ClassId)"
          }
      }
      "--- Last Run ---"
      $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath
      "  LastRunTime: $($info.LastRunTime)  LastTaskResult: $($info.LastTaskResult)"
  }

DECODING:
- LastTaskResult: 0 = success. SCHED_S_TASK_RUNNING = 0x00041301 = 267009/267011
  ("task still running" — NOT an error). 0x80041324 = 2147806724 = "task not
  currently running" (benign, means queried while idle). Other nonzero = real error.
- TRUE trigger TYPE (Logon/Time/OnUnlock/Boot): read task XML, not GetType():
  `([xml](Get-ScheduledTask -TaskName X -TaskPath Y).Xml).Task.Triggers` — child
  element name (LogonTrigger / TimeTrigger / OnSessionStateChangeTrigger / BootTrigger)
  is authoritative. Use when audit needs trigger semantics, not just intervals.
- "Custom" = not under \Microsoft\*. Most survivors are VENDOR tasks (OneDrive,
  Realtek [RtkAudUService*], Google Chrome PEH [platform_experience_helper],
  Chrome SoftLanding). True USER/BESPOKE automation = Action pointing at a user-owned
  path (e.g. C:\Users\<you>\...vbs/.ps1/.bat) or a non-vendor exe. Flag those as
  "bespoke automation found" vs "vendor cruft".
- COM-handler tasks (ClassId only, no Execute) are typically Chrome/Edge campaign or
  engagement frameworks — note them; payload invisible without the CLSID.

## KNOWN GOTCHAS
- Get-ComputerInfo WindowsProductName says "Windows 10" on 24H2 builds (26200). Trust Win32_OperatingSystem.Caption = "Microsoft Windows 11 ...".
- Scheduled-task Triggers come back as generic "CimInstance" with no useful GetType() —
  read Repetition.Interval + StartBoundary for interval/boundary, or the task XML
  (.Xml → Task.Triggers) for authoritative trigger TYPE. LastTaskResult 267009/267011
  is "still running", NOT an error; 2147806724 is "not currently running" (benign).
- python3 from git-bash is the MS Store stub → use `python`.
- scoop appears in the user's PS profile PATH but is NOT installed (dirs absent).
- Defender version string often comes back empty via Get-MpComputerStatus — not an error.
- Public IP probes (api.ipify.org) fail from host — NAT/egress filtered, expected.
- The MSYS `terminal` runs PS NON-ELEVATED. `winrm enumerate/get`, the WSMan
  registry, and Defender exclusion *values* return "Access is denied" / "must
  be admin" — that is a privilege gate, not a finding. See fallbacks below.

## SECURITY/SERVICES DEEP AUDIT RECIPE (ZQM-NODE-1 session, 2026-07-10)
One `.ps1` per domain, run via the `cygpath -w` shim. Group running services
heuristically, then RECHECK regex misfires (the auto-script over-matched
PcaSvc->ASUS and InventorySvc/nvagent->AI; both are plain Windows svchost).
# Running services grouped:
$running = Get-CimInstance Win32_Service | Where-Object {$_.State -eq 'Running'}
"TOTAL_RUNNING=$($running.Count)"
$running | Where-Object {$_.DisplayName -match 'ASUS|Armoury|ROG|Aura|MyASUS'} | ForEach-Object {"ASUS: $($_.Name) | $($_.DisplayName)"}
# Signature check for notable listeners (catches unsigned binaries):
Get-Process -Id <PID> | ForEach-Object { Get-AuthenticodeSignature $_.Path | Select-Object Status,@{n='Issuer';e={$_.SignerCertificate.Subject}} }

## NON-ELEVATED FALLBACKS (winrm enumerate / Defender exclusions denied)
# Admin check — run FIRST:
[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# WinRM 5986 listener exists? (works without elevation):
netsh http show sslcert | Select-String '5986|IP:port|Certificate Hash|Application ID'
# GUID {afebb9ad-9b97-4a91-9ab5-daf4d59122f6} = canonical WinRM service.
# Reachability probe:
$t=[System.Net.Sockets.TcpClient]::new(); $t.Connect('127.0.0.1',5986); "5986=$($t.Connected)"; $t.Close()
# Defender protection state (readable non-elevated); only exclusion values hidden:
Get-MpComputerStatus | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,AMProductVersion | Format-List

## BOTS & AUTOMATIONS — LIVE PROCESS + STARTUP RESOLUTION
The "what bots/automations run here" audit. Two layers: (A) live processes
(spawn tree), (B) auto-start items resolved to REAL targets. This session found
the "Hermes_Gateway" Startup shortcut actually launches an **OpenClaw** gateway
(node .../openclaw/dist/index.js gateway --port 18789), NOT native Hermes —
so NEVER trust a shortcut's display name; resolve it.

### A. Live process spawn-tree (INLINE PS GOTCHA: $_. + @{} calc props get
# mangled by bash -> "Missing ')' in method call". Prefer .ps1 -File form.)
Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match 'ollama|cua|node|python|pythonw' -or
    ($_.CommandLine -ne $null -and $_.CommandLine -match 'zqm|hermes|index|gateway|skill|automation|bot|ollama')
} | Select-Object ProcessId, Name, ParentProcessId,
    @{N='MemMB';E={[math]::Round($_.WorkingSetSize/1MB,1)}}, CommandLine |
    Format-List | Out-String -Width 4096
# NOTES from live run: Ollama = ollama app.exe (13240) -> ollama.exe serve (11556) :11434.
#   OpenClaw gateway = cmd.exe -> node.exe ...\openclaw\dist\index.js gateway --port 18789.
#   Hermes shows as hermes.exe / python.exe ...\hermes.exe (user session + this agent) — filter out.
#   msedgewebview2.exe children are noise unless webview-exe-name is a real bot.

### B. Auto-start items + .lnk/.vbs resolution
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" | Select-Object Name, FullName | Format-Table -AutoSize
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location | Format-Table -AutoSize
$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut('C:\Users\zqmco\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk')
"Target: $($lnk.TargetPath)"; "Args: $($lnk.Arguments)"; "CWD: $($lnk.WorkingDirectory)"
Get-Content 'C:\Users\zqmco\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Hermes_Gateway.vbs'
#   -> CreateObject("WScript.Shell").Run """C:\Users\zqmco\.openclaw\gateway.cmd""", 0, False
# .vbs hides a .cmd; follow it: gateway.cmd sets OPENCLAW_GATEWAY_PORT=18789 then
#   "C:\Program Files\nodejs\node.exe" ...\openclaw\dist\index.js gateway --port 18789

### C. Custom (non-Microsoft) Windows services
Get-CimInstance Win32_Service | Where-Object { $_.PathName -and $_.PathName -notmatch 'system32|svchost' } | Select-Object Name, DisplayName, PathName, State, StartMode | Format-Table -AutoSize

### D. Credential-exposure discipline (SECURITY FLAG)
Bot config files may carry PLAINTEXT TOKENS. This session found
~/.openclaw/openclaw.json (gateway auth token + device operator token) and
~/.openclaw/devices/paired.json (device token). RULES:
  - Scan bot configs for "token"/"apiKey"/"secret"/"password" keys.
  - FLAG credential exposure + recommend ROTATION; NEVER reproduce token values.
  - OpenClaw bind=loopback, mode=local, model=ollama/qwen3.6:latest -> on-box
    AI agent wired to the local fleet model; treat as an automation surface.

### E. Hermes-side automations
`cronjob action=list` returned 0 jobs this session -> no Hermes scheduled
automations. Seen Hermes processes are the interactive session + this agent.

## FIREWALL RULE INBOUND-ALLOW BY PORT
Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True | ForEach-Object {
  $pf = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
  if ($pf -and $pf.LocalPort -in 22,11434,5985,5986) { "$($_.DisplayName) | $($_.Profile) | $($pf.Protocol):$($pf.LocalPort)" }
}
