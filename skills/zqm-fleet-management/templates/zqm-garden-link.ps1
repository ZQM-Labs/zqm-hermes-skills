<#
.SYNOPSIS  ZQM Garden resilient link layer - unbreakable Node->Garden connections.
.DESCRIPTION
  Resolve a Garden by DNS name (.lan); if name fails, fall back across all cluster member IPs.
  Establish a PERSISTENT SMB mount to the Garden share using a local DPAPI-stored credential.
  Protocol-aware: skips DSM-only assumptions for clusters that are SSH/SMB only (Garden-04).
  Self-heals: registers a scheduled task to re-link on boot + every 15 min.
  Supports -DryRun (no mounts, no cred use) for safe inspection. NON-DESTRUCTIVE by default.
.PARAMETER DryRun      Report resolution + plan; no mounts, no cred use.
.PARAMETER Apply       Persist mounts (needs garden DPAPI cred readable).
.PARAMETER InstallTask Register boot + periodic self-heal scheduled task (needs -Apply + admin).
#>
[CmdletBinding(DefaultParameterSetName='DryRun')]
param(
  [switch]$DryRun, [switch]$Apply, [switch]$InstallTask,
  [string]$TopologyFile = (Join-Path $PSScriptRoot 'zqm-garden-topology.json'),
  [string]$CredFile = 'C:\zqm\cred\zqm-cred-garden-admin.json',
  [string]$DriveLetter = 'Z'
)
$ErrorActionPreference = 'SilentlyContinue'
function Log($m){ Write-Host $m }
if (-not (Test-Path $TopologyFile)) { Log "FATAL: topology not found: $TopologyFile"; exit 2 }
$topo = Get-Content $TopologyFile -Raw | ConvertFrom-Json
Log "Topology loaded (verified $($topo.verified)): $($topo.gardens.Count) gardens, $($topo.nodes.Count) nodes"

function Resolve-GardenTarget($g) {
  $candidates = @( $g.name ) + $g.members
  $order = @()
  foreach ($c in $candidates) {
    $ip = $null
    if ($c -match '^\d+\.\d+\.\d+\.\d+$') { $ip = $c }
    else { try { $ip = (Resolve-DnsName $c -ErrorAction Stop | Select-Object -First 1).IPAddress } catch {} }
    if ($ip) {
      $smb = Test-NetConnection -ComputerName $ip -Port 445 -InformationLevel Quiet
      $order += [pscustomobject]@{ host=$c; ip=$ip; smbOpen=$smb }
    }
  }
  return $order
}

$results = @()
foreach ($g in $topo.gardens) {
  Log "`n=== $($g.name) (primary $($g.primary)) ==="
  $plan = Resolve-GardenTarget $g
  $live = $plan | Where-Object { $_.smbOpen }
  if ($live.Count -eq 0) { Log "  ALL SMB PATHS DOWN - garden unreachable"; $results += [pscustomobject]@{Garden=$g.name;Status='DOWN'}; continue }
  $target = $live[0]
  Log "  Resolved via $($target.host) -> $($target.ip) (SMB open). Fallback chain: $(($live.host) -join ' > ')"
  if ($DryRun -or -not $Apply) {
    Log "  [DryRun] would mount \\$($target.ip)\$($g.share) as ${DriveLetter}:"
    $results += [pscustomobject]@{Garden=$g.name;Status='DRYRUN';Target=$target.ip}
    continue
  }
  if (-not (Test-Path $CredFile)) { Log "  FATAL: garden cred missing: $CredFile"; $results += [pscustomobject]@{Garden=$g.name;Status='NO-CRED'}; continue }
  Add-Type -AssemblyName System.Security | Out-Null
  $o = Get-Content $CredFile -Raw | ConvertFrom-Json
  $raw = [System.Convert]::FromBase64String($o.data)
  $pw = [System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($raw, $null, 'LocalMachine'))
  net use "${DriveLetter}:" /delete /y 2>$null | Out-Null
  $r = net use "${DriveLetter}:" "\\$($target.ip)\$($g.share)" /user:$($o.user) $pw /persistent:yes 2>&1 | Select-Object -First 2
  if ($LASTEXITCODE -eq 0) { Log "  MOUNTED ${DriveLetter}: -> \\$($target.ip)\$($g.share) (persistent)"; $results += [pscustomobject]@{Garden=$g.name;Status='MOUNTED';Target=$target.ip;Drive="${DriveLetter}:"} }
  else { Log "  MOUNT FAILED: $r"; $results += [pscustomobject]@{Garden=$g.name;Status='MOUNT-FAIL';Target=$target.ip} }
}
if ($InstallTask -and $Apply) {
  $taskName = 'ZQM-Garden-Link'
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Apply"
  $triggerBoot = New-ScheduledTaskTrigger -AtStartup
  $triggerPeriodic = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 15) -At (Get-Date)
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerBoot,$triggerPeriodic) -RunLevel Highest -Force | Out-Null
  Log "`nSelf-heal task '$taskName' registered (boot + every 15 min)."
}
Log "`n=== SUMMARY ==="
$results | Format-Table -AutoSize | Out-String | Write-Host
