# windows-host-inventory.ps1
# One-shot local Windows host census: identity, CPU, RAM, GPU, disks, services,
# installed software, top processes, display, battery, SMB shares, local Ollama.
#
# RUN (the -File form is REQUIRED on MSYS/git-bash -- inline -Command mangles $_):
#   powershell -NoProfile -ExecutionPolicy Bypass -File windows-host-inventory.ps1
#
# Known pitfalls (see references/local-host-inventory.md):
#   - wmic is REMOVED in Win11 24H2 (build 26200) -> use Get-CimInstance
#   - Win32_VideoController.AdapterRAM under-reports VRAM -> also call nvidia-smi
#   - Docker daemon may be stopped even when Docker Desktop is installed

$out = [System.Collections.Generic.List[string]]::new()
function Add($s){ $out.Add($s) }

Add("=== IDENTITY ===")
try {
  $os = Get-CimInstance Win32_OperatingSystem
  $cs = Get-CimInstance Win32_ComputerSystem
  Add("Host: $($cs.Name) | Domain: $($cs.Domain) | User: $($env:USERNAME)")
  Add("OS: $($os.Caption) $($os.OSArchitecture) | Build $($os.BuildNumber) | Install $($os.InstallDate)")
  Add("Boot time: $($os.LastBootUpTime) | Reg owner: $($os.RegisteredUser)")
} catch { Add("identity error: $_") }

Add("")
Add("=== CPU ===")
try {
  Get-CimInstance Win32_Processor | ForEach-Object {
    Add("$($_.Name) | Cores: $($_.NumberOfCores) | Threads: $($_.NumberOfLogicalProcessors) | MaxClock: $($_.MaxClockSpeed) MHz")
  }
} catch { Add("cpu error: $_") }

Add("")
Add("=== RAM ===")
try {
  $ram = Get-CimInstance Win32_PhysicalMemory
  $total = ($ram | Measure-Object -Property Capacity -Sum).Sum
  Add("Total: $([math]::Round($total/1GB,1)) GB across $($ram.Count) module(s)")
  $ram | ForEach-Object { Add("  $($_.Manufacturer) $($_.PartNumber) $([math]::Round($_.Capacity/1GB,1)) GB @ $($_.Speed) MHz ($($_.BankLabel))") }
} catch { Add("ram error: $_") }

Add("")
Add("=== GPU (WMI) ===")
try {
  Get-CimInstance Win32_VideoController | ForEach-Object {
    Add("$($_.Name) | WMI-VRAM: $([math]::Round($_.AdapterRAM/1GB,2)) GB | Driver: $($_.DriverVersion)")
  }
} catch { Add("gpu error: $_") }

Add("")
Add("=== GPU (nvidia-smi, true VRAM) ===")
try {
  $smi = nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu --format=csv 2>$null
  if ($smi) { $smi | ForEach-Object { Add($_) } } else { Add("nvidia-smi not available / no NVIDIA GPU") }
} catch { Add("nvidia-smi error: $_") }

Add("")
Add("=== DISK (physical) ===")
try {
  Get-CimInstance Win32_DiskDrive | ForEach-Object {
    Add("$($_.Model) | $([math]::Round($_.Size/1GB,1)) GB | $($_.MediaType)")
  }
} catch { Add("disk error: $_") }

Add("")
Add("=== VOLUMES ===")
try {
  Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
    Add("$($_.DriveLetter): $($_.FileSystem) | $([math]::Round($_.Size/1GB,1)) GB total / $([math]::Round($_.SizeRemaining/1GB,1)) GB free")
  }
} catch { Add("volume error: $_") }

Add("")
Add("=== RUNNING SERVICES ===")
try {
  Get-Service | Where-Object { $_.Status -eq 'Running' } | Select-Object -ExpandProperty Name | Sort-Object | ForEach-Object { Add($_) }
} catch { Add("services error: $_") }

Add("")
Add("=== INSTALLED SOFTWARE (registry) ===")
try {
  $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
  Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
    Sort-Object DisplayName | Select-Object -ExpandProperty DisplayName | ForEach-Object { Add($_) }
} catch { Add("software error: $_") }

Add("")
Add("=== TOP 15 PROCESSES (RAM) ===")
try {
  Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 15 Name,@{n='RAM_MB';e={[math]::Round($_.WorkingSet/1MB)}},CPU |
    ForEach-Object { Add("$($_.Name)  RAM=$($_.RAM_MB)MB  CPU=$($_.CPU)") }
} catch { Add("process error: $_") }

Add("")
Add("=== DISPLAY ===")
try {
  Get-CimInstance Win32_DesktopMonitor | Select-Object DeviceID,ScreenWidth,ScreenHeight |
    ForEach-Object { Add("$($_.DeviceID): $($_.ScreenWidth)x$($_.ScreenHeight)") }
} catch { Add("display error: $_") }

Add("")
Add("=== BATTERY ===")
try {
  $bat = Get-CimInstance Win32_Battery
  if ($bat) { $bat | ForEach-Object { Add("$($_.Name): $($_.EstimatedChargeRemaining)% status=$($_.BatteryStatus)") } }
  else { Add("no battery (desktop)") }
} catch { Add("battery error: $_") }

Add("")
Add("=== SMB SHARES ===")
try {
  Get-SmbShare | Select-Object Name,Path,Description | ForEach-Object { Add("$($_.Name) -> $($_.Path)  [$($_.Description)]") }
} catch { Add("shares error: $_") }

Add("")
Add("=== LOCAL OLLAMA :11434 ===")
try {
  $r = Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 4
  Add("Ollama responding. Models: $($r.models.Count)")
  $r.models | ForEach-Object { Add("  $($_.name)  $([math]::Round($_.size/1GB,1))GB") }
} catch { Add("Ollama not responding on :11434 (or no model)") }

Add("")
Add("=== DOCKER ===")
try {
  $dv = docker version --format '{{.Server.Version}}' 2>&1
  if ($dv -match '^\d') { Add("docker server: $dv") } else { Add("docker daemon down (installed but not running)") }
} catch { Add("docker not installed") }

$out | Out-String
