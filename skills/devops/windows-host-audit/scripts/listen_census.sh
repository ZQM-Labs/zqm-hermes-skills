#!/usr/bin/env bash
# listen_census.sh — Windows host TCP listener census (Hermes MSYS terminal).
#
# PROVEN form (2026-07-11, ZQM-NODE-1 audit). The single inline powershell
# below is the ONLY form that reliably returns netstat rows:
#   powershell.exe -NoProfile -Command "cmd.exe /c 'netstat -ano -p TCP' | Select-String 'LISTENING'"
# AVOID these (burned 3x this session — cmd.exe stdout gets SWALLOWED, empty output):
#   - wrapping netstat in a .ps1 run via -File
#   - piping through Out-String -Stream | Select-String
#   - chaining Get-CimInstance Win32_Process | ForEach Write-Host in the SAME -Command
#     (the process-name column also dropped)
# Run netstat and the PID->path lookup as SEPARATE inline -Command calls.
#
# Output line shape:  TCP  addr:port  0.0.0.0:0  LISTENING  <PID>
# Then resolve each PID path with its OWN call:
#   powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.ProcessId -eq <PID> } | ForEach-Object { \$_.ExecutablePath }"
#
powershell.exe -NoProfile -Command "cmd.exe /c 'netstat -ano -p TCP' | Select-String 'LISTENING'"
