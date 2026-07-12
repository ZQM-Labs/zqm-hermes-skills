# Local host inventory / profiling from the bash terminal (Win11 24H2)

The user asked "learn more about this workstation" — a full hardware/software/process
census of a single Windows box (here: ZQM-NODE-1, an ASUS Vivobook K6602VV running
Windows 11 Pro for Workstations, build 26200). Reusable technique + the traps that cost
cycles.

## Reusable script
`scripts/windows-host-inventory.ps1` — emits identity, CPU, RAM (per-module),
GPU (WMI + nvidia-smi), physical disks + volumes, running services, installed software,
top-15 processes by RAM, display, battery, SMB shares, local Ollama count, Docker state.
Run with the `-File` form (see below).

## Traps

### 1. `wmic` is REMOVED in Windows 11 24H2 (build 26200)
`wmic cpu get ...` / `wmic diskdrive get ...` returned **exit 127** on this host.
Use `Get-CimInstance Win32_Processor|Win32_PhysicalMemory|Win32_VideoController|
Win32_DiskDrive|Win32_Battery` piped to `Select` + `Format-Table/List` instead.
`systeminfo` still works but is slow (use only for OS build + hotfix list).

### 2. MSYS/git-bash expands PowerShell `$_` BEFORE PowerShell runs it
Inline `powershell -Command "... ForEach-Object { $_.Name } ..."` became literal
`$.Name` (parse error) because bash substitutes `$_` in the double-quoted string
before launching powershell. This silently broke the first inventory attempts.
RELIABLE pattern: write the probe to a `.ps1` file and run
`powershell -NoProfile -ExecutionPolicy Bypass -File <path>.ps1`.
The `-File` form is NOT parsed by bash, so `$_`, `$env:`, and `$($_.x)` survive intact.
This is the SAME discipline the fleet skill already mandates (pitfall #6 / #10:
`cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\x.ps1"`,
forward slashes or `C:\temp` also survive). Reuse it.

### 3. `Win32_VideoController.AdapterRAM` UNDER-REPORTS VRAM
On an RTX 4060 Laptop GPU, WMI `AdapterRAM` reported 4 GB while
`nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu --format=csv`
showed the true **8188 MiB**. For accurate GPU VRAM/usage always call nvidia-smi;
treat WMI GPU RAM as a floor, not truth.

### 4. Docker Desktop daemon may be stopped even when installed
Installed-but-stopped yields `docker version` failing on the npipe
(`//./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified`).
Report docker as "installed but daemon down", not "usable".

## Why this belongs to the agent, not the user
The agent's sandbox can reach 192.168.1.0/24, but local host profiling is best done by
invoking PowerShell directly on the box (no remoting needed for the local node). For
REMOTE nodes, prefer the WinRM-tunnel / staged-file patterns in the parent skill over
re-deriving these probes per node.

## Reproduction (what was run this session)
- `systeminfo` (slow, for build + hotfix list)
- `ipconfig` for NIC/IP/gateway
- `Get-CimInstance` for CPU/RAM/GPU/disk/battery/display/services
- `Get-ItemProperty` of the two Uninstall registry hives for software census
- `nvidia-smi --query-gpu=...` for true VRAM
- `Invoke-RestMethod http://localhost:11434/api/tags` for local Ollama models
- `Get-SmbShare`, `Get-Process | Sort WorkingSet`
All wrapped in `scripts/windows-host-inventory.ps1` for re-runs.
