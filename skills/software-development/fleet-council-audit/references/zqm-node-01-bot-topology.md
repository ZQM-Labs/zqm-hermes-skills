# ZQM Node-1 Bot Topology — reference (2026-07-10, re-verified live)

Live on Node-1 (192.168.1.218, Win11 Pro for Workstations 24H2, build 26200):

## LIVE bots (verified via Win32_Process + Get-NetTCPConnection)
- Ollama LLM server — `ollama.exe serve`, owns `[::]:11434` (LAN-exposed).
  Spawn: explorer.exe → ollama app.exe → ollama.exe serve. Models: qwen3:8b (5.2GB), qwen3.6:latest (23.9GB).
- OpenClaw gateway — `node ...\openclaw\dist\index.js gateway --port 18789`, owns `127.0.0.1:18789` (loopback only).
  Auth: token. Model: ollama/qwen3.6 via http://127.0.0.1:11434. Has a "main" agent + paired operator device (openclaw-tui, win32).
  Launched by Scheduled Task "OpenClaw Gateway" (AtLogon) → `.openclaw\gateway.vbs` → `gateway.cmd`.
- Hermes agent — hermes.exe/python.exe under `AppData\Local\hermes\hermes-agent\venv` (this session + user console).

## DEAD (broken) Startup items — REPAIRED 2026-07-10
All 4 custom Startup items point at wrong/stale paths. 3 were broken; fixed by repointing to `OneDrive\Desktop\repos\`:
- Hermes_Gateway.vbs (Startup) — redirector; target `AppData\Local\hermes\gateway-service\Hermes_Gateway.vbs` MISSING.
  FIX: repoint to `OneDrive\Desktop\repos\hermes-config\gateway-service\Hermes_Gateway.vbs` (that .vbs sets HERMES_HOME + venv, runs `pythonw.exe -m hermes_cli.main gateway run`).
- ZQM-Node-01-Indexer.lnk — Args `OneDrive\Desktop\zqm-node-01-indexer\app.py` MISSING.
  FIX: Args → `OneDrive\Desktop\repos\zqm-node-01-indexer\app.py`, WorkDir → `...\repos\zqm-node-01-indexer`.
  It's a Flask/Waitress filesystem indexer; PORT env default 5000, binds 127.0.0.1; config.json was empty (never ran; total_files=0).
- ZQM-Skill-Automation-Center.lnk — Args `AppData\Local\hermes\skills\...\serve_dashboard.py` MISSING (only __pycache__).
  FIX: Args → `OneDrive\Desktop\repos\hermes-config\skills\skill-automation-center\scripts\serve_dashboard.py`.
  Flask dashboard; SAC_PORT env default 9000, SAC_HOST default 127.0.0.1; per-user auth via zqm_auth.
- Ollama.lnk — valid (only one that wasn't broken).

## Port mesh (distinct, no clash)
11434 Ollama (LAN) | 18789 OpenClaw (loopback) | 5000 Indexer (loopback) | 9000 Skill-Center (loopback).
Ollama is the shared brain for both gateways. Indexer/Skill-Center do NOT call Ollama.

## Residual risk (left as-is per user)
At next logon BOTH OpenClaw gateway (task :18789) AND native Hermes gateway (.vbs → `gateway run`, no PORT env)
could start. Hermes' default port is in a compiled module (couldn't read it). Mitigation if collision:
pin Hermes PORT env in the .vbs/.cmd, OR disable the OpenClaw Scheduled Task. Ask user which gateway owns :18789.

## SECURITY — plaintext tokens (flag, rotate)
`.openclaw\openclaw.json` (gateway auth token + device operator token) and `.openclaw\devices\paired.json`
(live operator token + public key) carry cleartext secrets. Loopback-only bind limits exposure to local-file read.
Never print these into a report.

## Repair recipe (one PowerShell -File pass)
1. Copy each broken .lnk/.vbs to *.bak.
2. For .lnk: $sh=New-Object -ComObject WScript.Shell; $l=$sh.CreateShortcut(...); $l.Arguments=...; $l.WorkingDirectory=...; $l.Save().
3. For .vbs: Get-Content -Raw, .Replace(oldTarget,newTarget), Set-Content -NoNewline.
4. Verify: Test-Path on the .lnk Arguments (NOT just TargetPath — launcher masks the broken script path), and regex-extract the .vbs `target = "..."` and Test-Path it.
Note: `CreateShortcut` `Test-Path $lnk.TargetPath` returns True even when the .py script (Arguments) is missing — the trap.
