# deep_recon.ps1 — DEEP-tier read-only host recon (windows-host-audit 0b "explore deeply").
# NO mutations: no Set/New/Disable/Write to system state. Output to a .txt only.
# Technique notes:
#  - Uses -f formatting throughout so literal '[' brackets never abort the parser (P7).
#  - Parent PID + command line via Get-CimInstance Win32_Process (not Get-Process -IncludeUserName).
#  - Maps every Listen/Established socket to its real process PATH (catches services vs user apps).
#  - Scheduled tasks: dumps ACTIONS + TRIGGERS and RESOLVES .vbs targets (e.g. OpenClaw gateway.vbs -> gateway.cmd).
#  - Scans interesting user dirs (.ssh/.ollama/.openclaw/Documents/bounty-tools/quarantine*).
#  - Defender exclusions attempt is DENIED non-elevated -> reported as "needs elevation", not faked.
$ErrorActionPreference = 'SilentlyContinue'
$out = "C:\Users\zqmco\swarm\2026-07-11_fleet_audit\deep_recon.txt"
function w([string]$s){ Add-Content -Path $out -Value $s }
w ("DEEP RECON runtime={0} host={1} user={2}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"),$env:COMPUTERNAME,$env:USERNAME)

# [A] ALL adapters (up+down+virtual) + gateways
w "`n[A] ALL NETWORK ADAPTERS"
Get-NetAdapter | ForEach-Object {
  $a = $_
  $ips = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue | ForEach-Object { "{0}/{1}" -f $_.AddressFamily,$_.IPAddress }) -join ", "
  w ("  {0} | {1} | Status={2} | MTU={3} | MAC={4} | IP=[{5}]" -f $a.Name,$a.InterfaceDescription,$a.Status,$a.MtuSize,$a.MacAddress,$ips)
}
w "  --- IP config (gateways) ---"
Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway} | ForEach-Object { w ("  if={0} GW={1} DNS={2}" -f $_.InterfaceAlias,($_.IPv4DefaultGateway.NextHop -join ','),($_.DNSServer -join ',')) }

# [B] Processes WITH command line + parent + path
w "`n[B] PROCESSES (cmdline + parent + path)"
$procs = Get-CimInstance Win32_Process
$procs | Sort-Object WorkingSetSize -Descending | Select-Object -First 60 | ForEach-Object {
  $pp = ($procs | Where-Object {$_.ProcessId -eq $_.ParentProcessId} | Select-Object -First 1 -ExpandProperty Name)
  w ("  {0} PID={1} PPID={2}({3}) MEM={4}MB" -f $_.Name,$_.ProcessId,$_.ParentProcessId,$pp,[math]::Round($_.WorkingSetSize/1MB,0))
  if ($_.CommandLine) { w ("      CMD: {0}" -f $_.CommandLine) }
}

# [C] Every listening/established socket mapped to process path + cmdline
w "`n[C] SOCKETS -> PROCESS (full map)"
$conns = Get-NetTCPConnection | Where-Object {$_.State -in @('Listen','Established')} | Sort-Object LocalPort
$conns | ForEach-Object {
  $p = $procs | Where-Object {$_.ProcessId -eq $_.OwningProcess} | Select-Object -First 1
  $path = if ($p) { $p.ExecutablePath } else { '?' }
  w ("  {0} {1}:{2} -> {3}:{4} PID={5} [{6}]" -f $_.State,$_.LocalAddress,$_.LocalPort,$_.RemoteAddress,$_.RemotePort,$_.OwningProcess,$path)
}
w "  --- UDP endpoints (top) ---"
Get-NetUDPEndpoint | Sort-Object LocalPort | Select-Object -First 25 | ForEach-Object {
  $p = $procs | Where-Object {$_.ProcessId -eq $_.OwningProcess} | Select-Object -First 1
  w ("  UDP {0}:{1} PID={2} [{3}]" -f $_.LocalAddress,$_.LocalPort,$_.OwningProcess,$(if($p){$p.ExecutablePath}else{'?'}))
}

# [D] Services with binary paths (spot anything weird)
w "`n[D] SERVICES (binary paths, Running+Auto)"
Get-CimInstance Win32_Service | Where-Object {$_.State -eq 'Running' -or $_.StartMode -eq 'Auto'} | Sort-Object Name | ForEach-Object {
  w ("  {0} [{1}/{2}] -> {3}" -f $_.Name,$_.State,$_.StartMode,$_.PathName)
}

# [E] Scheduled tasks FULL detail (actions + triggers), esp OpenClaw; resolve .vbs
w "`n[E] SCHEDULED TASKS (full actions + triggers)"
Get-ScheduledTask | Where-Object {$_.State -eq 'Ready'} | ForEach-Object {
  $t = $_
  $acts = ($t.Actions | ForEach-Object { "exec={0} args={1} work={2}" -f $_.Execute,$_.Arguments,$_.WorkingDirectory }) -join " | "
  $trg = ($t.Triggers | ForEach-Object { $_.CimClass.CimClassName }) -join ","
  w ("  TASK {0}" -f $t.TaskName)
  w ("    ACTIONS: {0}" -f $acts)
  w ("    TRIGGERS: {0}" -f $trg)
}
$vbs = "C:\Users\zqmco\.openclaw\gateway.vbs"
if (Test-Path $vbs) {
  w "  --- OpenClaw gateway.vbs CONTENT ---"
  (Get-Content $vbs -Raw) -split "`n" | ForEach-Object { w ("    | {0}" -f $_) }
} else { w ("  OpenClaw vbs NOT at {0}" -f $vbs) }

# [F] WSL distros + Docker
w "`n[F] WSL + DOCKER"
try { $wsl = & wsl.exe --list --verbose 2>&1; w ("  WSL: {0}" -f ($wsl -join " / ")) } catch { w "  WSL: n/a" }
try { $dk = & docker.exe ps --format "{{.Names}}:{{.Image}}:{{.Status}}" 2>&1; w ("  DOCKER running: {0}" -f ($dk -join " / ")) } catch { w "  DOCKER: n/a or not running" }

# [G] Defender exclusions (non-elevated -> DENIED is expected)
w "`n[G] DEFENDER EXCLUSIONS"
try {
  $mp = Get-MpPreference
  w ("  ExclusionPath: {0}" -f ($mp.ExclusionPath -join ', '))
  w ("  ExclusionProcess: {0}" -f ($mp.ExclusionProcess -join ', '))
  w ("  ExclusionExtension: {0}" -f ($mp.ExclusionExtension -join ', '))
} catch { w "  Defender prefs: DENIED (needs elevation)" }

# [H] Interesting dirs (incl quarantine scan)
w "`n[H] INTERESTING USER/PROFILE ARTIFACTS"
@("$env:USERPROFILE\.ssh","$env:USERPROFILE\.ollama","$env:USERPROFILE\.openclaw","$env:USERPROFILE\Documents\bounty-tools") | ForEach-Object {
  if (Test-Path $_) {
    w ("  DIR {0}:" -f $_)
    Get-ChildItem $_ -ErrorAction SilentlyContinue | Select-Object -First 25 | ForEach-Object { w ("    {0}  {1}" -f $(if($_.PSIsContainer){'DIR '}else{'FILE'}), $_.Name) }
  } else { w ("  DIR {0}: (absent)" -f $_) }
}

# [I] Exposure notes: priv ports + 0.0.0.0 listeners
w "`n[I] EXPOSURE NOTES"
$priv = $conns | Where-Object { $_.LocalPort -lt 1024 -and $_.State -eq 'Listen' }
$priv | ForEach-Object { w ("  PRIV-PORT LISTEN: {0}:{1} PID={2}" -f $_.LocalAddress,$_.LocalPort,$_.OwningProcess) }
$zer = $conns | Where-Object { $_.LocalAddress -eq '0.0.0.0' -and $_.State -eq 'Listen' }
$zer | ForEach-Object { w ("  ALL-IF LISTEN: 0.0.0.0:{0} PID={1}" -f $_.LocalPort,$_.OwningProcess) }

w "`nEND DEEP RECON"
