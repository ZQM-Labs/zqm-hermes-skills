# host-storage-net-audit.ps1
# One-shot storage / shares / network audit of a Windows node.
# Reusable across the ZQM fleet: edit the CONFIG block per node, then run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/host-storage-net-audit.ps1
# Output goes to stdout AND a raw dump (host-storage-net-audit_raw.txt) for evidence.
#
# AUTHORING RULES (else it will not parse): ASCII-only source, NO literal '%'
# adjacent to a {N} -f placeholder (compute pct into a var instead), no em-dash.
$ErrorActionPreference = 'SilentlyContinue'
$out = [System.Collections.Generic.List[string]]::new()
function line($s){ $out.Add($s) | Out-Null; Write-Output $s }

# ---------------- CONFIG (edit per node) ----------------
$NAS_NAME   = "ZQM-Garden-01"          # remote NAS to probe
$NAS_SHARES = @('web','backups')        # shares to test reachability for
$SWEEP_START = 1
$SWEEP_END   = 40
$KNOWN_IPS   = @('192.168.1.21','192.168.1.46','192.168.1.215','192.168.1.218','192.168.1.173')
# ---------------------------------------------------------

line "===== HOST STORAGE/SHARES/NET AUDIT - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====="
line "HOST: $env:COMPUTERNAME"

# 1. PHYSICAL DISKS
line ""
line "### [DISK] Physical disks"
foreach ($d in Get-Disk){
  line ("DISK#{0} | {1} | {2} | {3} | {4} GB | Style={5}" -f `
        $d.Number, $d.FriendlyName, $d.OperationalStatus, $d.HealthStatus, [math]::Round($d.Size/1GB,1), $d.PartitionStyle)
}

# 2. VOLUMES + UNMOUNTED-FORMATTED classifier
line ""
line "### [VOLUME] All volumes"
foreach ($v in Get-Volume){
  $dl = if($v.DriveLetter){$v.DriveLetter}else{"<none>"}
  $fs = if($v.FileSystem){$v.FileSystem}else{"<raw>"}
  $sz = if($v.Size){[math]::Round($v.Size/1GB,1)}else{0}
  $fr = if($v.SizeRemaining){[math]::Round($v.SizeRemaining/1GB,1)}else{0}
  line ("VOL {0}: | FS={1} | {2} GB | free={3} GB | Type={4} | Health={5}" -f $dl,$fs,$sz,$fr,$v.DriveType,$v.HealthStatus)
}

line ""
line "### [UNMOUNTED-FORMATTED] partitions with NO DriveLetter but a Filesystem present"
$unmounted = @()
foreach ($p in Get-Partition){
  $v = Get-Volume -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -ErrorAction SilentlyContinue
  $hasFS = $v -and $v.FileSystem -and $v.FileSystem -ne ""
  $noLetter = (-not $p.DriveLetter) -or ($p.DriveLetter -eq "")
  if ($noLetter -and $hasFS){
    $cls = "DATA(?)"
    $t = $p.Type
    if($t -match "Recovery"){ $cls="RECOVERY" }
    elseif($t -match "OEM|System|Reserved|Microsoft"){ $cls="OEM/SYS" }
    $unmounted += $p
    line ("UNMOUNTED-FORMATTED -> Disk#{0} Part#{1} | FS={2} | {3} GB | Type={4} | CLASS={5}" -f `
          $p.DiskNumber, $p.PartitionNumber, $v.FileSystem, [math]::Round($p.Size/1GB,1), $t, $cls)
  }
}
if($unmounted.Count -eq 0){ line "NONE - all formatted volumes are mounted. PROVEN" }

line ""
line "### [C/D] System data volumes C: and D:"
foreach ($dl in @('C','D')){
  $v = Get-Volume -DriveLetter $dl -ErrorAction SilentlyContinue
  if($v){
    $pct = [math]::Round(($v.SizeRemaining/$v.Size)*100,1)
    line ("{0}: | FS={1} | total={2} GB | free={3} GB ({4} pct) | Health={5}" -f `
          $dl, $v.FileSystem, [math]::Round($v.Size/1GB,1), [math]::Round($v.SizeRemaining/1GB,1), $pct, $v.HealthStatus)
  } else {
    line ("{0}: NOT PRESENT / UNRESOLVED" -f $dl)
  }
}

# 3. LOCAL SMB SHARES
line ""
line "### [SMB-LOCAL] Local SMB shares (Get-SmbShare)"
$shares = Get-SmbShare
foreach ($s in $shares){
  line ("SHARE '{0}' -> Path='{1}' | Desc='{2}'" -f $s.Name, $s.Path, $s.Description)
}
if($shares.Count -eq 0){ line "NO LOCAL SHARES. UNRESOLVED" }

# 4. REMOTE NAS REACHABILITY
line ""
line "### [NAS] $NAS_NAME resolution + share reachability"
try {
  $ip = (Resolve-DnsName -Name $NAS_NAME -ErrorAction Stop | Select-Object -First 1).IPAddress
  line ("RESOLVED {0} -> {1}  PROVEN" -f $NAS_NAME, $ip)
} catch {
  line ("RESOLVE {0} FAILED: {1}  UNRESOLVED" -f $NAS_NAME, $_.Exception.Message)
  $ip = $null
}
foreach ($share in $NAS_SHARES){
  $unc = "\\$NAS_NAME\$share"
  try {
    $ok = Test-Path -Path $unc -ErrorAction Stop
    if($ok){ line ("REACHABLE {0}  PROVEN" -f $unc) }
    else   { line ("UNREACHABLE {0} (Test-Path false)  UNRESOLVED" -f $unc) }
  } catch {
    line ("UNREACHABLE {0}: {1}  UNRESOLVED" -f $unc, $_.Exception.Message)
  }
}

# 5. NETWORK ADAPTERS / IP / APIPA / ROUTE / DNS
line ""
line "### [ADAPTER] Get-NetAdapter"
foreach ($a in Get-NetAdapter){
  line ("ADAPTER '{0}' | ifIndex={1} | Status={2} | LinkSpeed={3} | MAC={4}" -f `
        $a.Name, $a.ifIndex, $a.Status, $a.LinkSpeed, $a.MacAddress)
}

line ""
line "### [IP] IPv4 per adapter (flag APIPA 169.254.x)"
foreach ($i in Get-NetIPAddress -AddressFamily IPv4){
  $flag = ""
  if($i.IPAddress -like "169.254.*"){ $flag = " <-- APIPA (no DHCP)" }
  $adpName = (Get-NetAdapter -InterfaceIndex $i.InterfaceIndex -ErrorAction SilentlyContinue).Name
  line ("IPv4 {0} | ifIndex={1} ({2}) | Prefix={3}{4}" -f $i.IPAddress, $i.InterfaceIndex, $adpName, $i.PrefixLength, $flag)
}

line ""
line "### [ROUTE] Default route 0.0.0.0/0"
$routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
if($routes){ foreach ($r in $routes){ line ("DEFAULT -> NextHop={0} | ifIndex={1} | Metric={2}" -f $r.NextHop, $r.InterfaceIndex, $r.RouteMetric) } }
else { line "NO DEFAULT ROUTE. UNRESOLVED" }

line ""
line "### [DNS] Get-DnsClientServerAddress (IPv4)"
foreach ($d in Get-DnsClientServerAddress -AddressFamily IPv4){
  $adpName = (Get-NetAdapter -InterfaceIndex $d.InterfaceIndex -ErrorAction SilentlyContinue).Name
  line ("DNS ifIndex={0} ({1}) -> {2}" -f $d.InterfaceIndex, $adpName, ($d.ServerAddresses -join ', '))
}

# 6. /24 LIVE-HOST PING SWEEP (via PowerShell Test-Connection, single probe)
line ""
line "### [SWEEP] /24 live-host ping sweep $SWEEP_START-$SWEEP_END (single probe each)"
$alive = @()
for ($i = $SWEEP_START; $i -le $SWEEP_END; $i++){
  $addr = "192.168.1.$i"
  if (Test-Connection -ComputerName $addr -Count 1 -Quiet -ErrorAction SilentlyContinue){ $alive += $addr; line ("ALIVE $addr") }
}
line ("SWEEP ALIVE ({0}): {1}" -f $alive.Count, ($alive -join ' '))

line ""
line "### [KNOWN-IPS] explicit retest"
foreach ($ip in $KNOWN_IPS){
  if (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue){ line ("ALIVE $ip") }
  else { line ("DEAD  $ip") }
}

line ""
line "===== END AUDIT ====="
$out | Out-File -FilePath ".\host-storage-net-audit_raw.txt" -Encoding utf8
