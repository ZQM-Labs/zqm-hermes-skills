#!/usr/bin/env bash
# workstation_toolchain_inventory.sh
# Re-runnable inventory of the Windows 10 workstation toolchain (Node-1 / this host).
# Runs from git-bash / MSYS. Emits REAL version strings, not guesses.
#
# WHAT IT COVERS
#   - Package managers: scoop, choco, winget  (and PROVES scoop is really installed,
#     not just referenced in PATH — see GOTCHA below)
#   - Python (which), pip, uv
#   - Node / npm, git, go, rust, docker
#   - PowerShell version + custom-profile presence
#   - Notable installed apps (registry uninstall keys)
#   - A condensed PATH dump
#
# GOTCHA this script defends against:
#   A PATH entry like "C:\Users\zqmco\scoop\shims" can exist because a PowerShell
#   profile *appends* it, even though scoop was NEVER installed (no scoop\shims dir,
#   no scoop\apps dir, command not found). So "scoop is on PATH" != "scoop installed".
#   This script VERIFIES the install dirs and the command resolution before reporting.
#
# Run:  bash scripts/workstation_toolchain_inventory.sh

set -u

rule(){ printf '%s\n' "------------------------------------------------------------"; }
hdr(){  printf '\n### %s\n' "$1"; rule; }

# --- helper: probe a --version style command, tolerate missing ----------------
probe() {                # $1=label  $2=command-string
  local label="$1"; local cmd="$2"
  printf '%-14s ' "$label:"
  out=$(eval "$cmd" 2>&1 | head -1)
  if [ -z "$out" ]; then echo "(not found)"; else echo "$out"; fi
}

hdr "PACKAGE MANAGERS"
probe "scoop"   "scoop --version"
probe "choco"   "choco --version"
probe "winget"  "winget --version"

# --- scoop reality check (PATH-stub vs real install) -------------------------
hdr "SCOOP REALITY CHECK  (PATH entry != installed)"
# Resolve the user-profile scoop dirs via PowerShell to be PATH-agnostic.
pwsh_scoop=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
  $base = Join-Path $env:USERPROFILE "scoop"
  $shims = Test-Path (Join-Path $base "shims")
  $apps  = Test-Path (Join-Path $base "apps")
  $onPath = ($env:Path -split ";") -contains (Join-Path $base "shims")
  "ON_PATH=$onPath SHIMS_DIR=$shims APPS_DIR=$apps"
' 2>&1 | tr -d '\r')
echo "  $pwsh_scoop"
case "$pwsh_scoop" in
  *"SHIMS_DIR=True"*"APPS_DIR=True"*) echo "  => scoop IS installed (dirs present)" ;;
  *) echo "  => scoop NOT installed (PATH entry is a stub; dirs absent). Do not report scoop as present." ;;
esac

hdr "PYTHON / PIP / UV"
probe "python"  "python --version"
probe "python3" "python3 --version"
probe "pip"     "python -m pip --version"
probe "uv"      "uv --version"

hdr "NODE / NPM"
probe "node" "node --version"
probe "npm"  "npm --version"

hdr "VCS / LANGUAGES / RUNTIME"
probe "git"    "git --version"
probe "go"     "go version"
probe "rustc"  "rustc --version"
probe "cargo"  "cargo --version"
probe "docker" "docker --version"

hdr "POWERSHELL VERSION + PROFILE"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
  Write-Host ("  PSVersion : " + $PSVersionTable.PSVersion.ToString())
  $p = $PROFILE
  Write-Host ("  Profile   : " + $p)
  if (Test-Path $p) {
    Write-Host ("  Exists    : YES (" + (Get-Item $p).Length + " bytes)")
  } else {
    Write-Host "  Exists    : NO"
  }
' 2>&1 | sed 's/\r$//'

hdr "NOTABLE INSTALLED APPS (registry uninstall keys)"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
  $keys = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
  $apps = Get-ItemProperty $keys -ErrorAction SilentlyContinue
  $apps | Where-Object { $_.DisplayName } | Select-Object -ExpandProperty DisplayName |
    Sort-Object -Unique | ForEach-Object { "  APP: " + $_ }
' 2>&1 | sed 's/\r$//'

hdr "CONDENSED PATH (bash view)"
echo "$PATH" | tr ':' '\n' | sed 's/^/  /'

rule
echo "Done. Re-run any time to re-verify the live toolchain."
