# 2026-07-09 Homelab Runtime Snapshot

Use for audit continuity on this workstation. Do not treat as generic defaults.

## Hardware/resource state
- Host: ZQM-Node-1 / zqmco
- RAM: 16 GB physical, typically near exhaustion during active Ollama sessions
- GPU: RTX 4060 Laptop, 8188 MiB VRAM
- GPU utilization during council runs can be moderate, but large-model captures evict service memory pressure to swap

## Installed Ollama models
- `qwen3:8b` — 5.2 GB, Q4_K_M, 8.2B params; reliable on this host
- `qwen3.6:latest` — 23.9 GB, Q4_K_M, 36.0B params; context entries at 4096; can stallGenerate under RAM pressure
- `/api/generate` against `qwen3:8b` returns in seconds; `qwen3.6:latest` can timeout without backend error logs

## Service stack
- Council/FastAPI: `127.0.0.1:8000` — expected, **currently not reachable** on this host
- Ollama: `127.0.0.1:11434` — **UP** on 2026-07-09
- ComfyUI: `127.0.0.1:8188` — expected in repo docs, **currently not reachable**
- Node-01 indexer: `127.0.0.1:5000` — expected, **currently not reachable**
- Node-02 indexer: `127.0.0.1:5000` — expected, **currently not reachable**
- Docker: installed, **0 running containers** on 2026-07-09
- Port-binding conflicts occur when restarting after crashes; prefer actual process kill + relaunch over blind second launches
- Verified on host: use PowerShell `Get-NetTCPConnection -State Listen` instead of `netstat -ano`; local listener PIDs for Ollama=4848, RPC=1848, SMB=4, WinRM-like=8220

## Verified repo/runtime artifacts on disk
- `.quarantined/` contains runtime boards/logs; do not delete without inventory
- Tracked `__pycache__` pycs may be present; user must approve any `git rm --cached` moves
- `instances/zqmco/state/state.db`, `-shm`, `-wal` committed in `zqm-auth` at ~95MB total
- `zqm-bounty-hub/adapter-routing.json` contains confirmed HackerOne token identifier `zqm-computing` with 15 verified endpoints and a plaintext-never-commit note
- `dev-setup/bootstrap.ps1` fetches and runs remote unsigned PowerShell: `iex "& {$(iwr -useb https://get.scoop.sh)} -RunAsAdmin"`; also `install.ps1` fetch pattern
- `zqm-auth/elevated_install.ps1` exists and contains `Start-Process ... -ArgumentList '/S' -Wait`
- `hermes-config/check_npcap.ps1` exists in repo but GitHub `contents` API can return 404 for individual files even when the file is present in the tree; confirm via `/git/trees/{branch}?recursive=1` list before classifying as missing
- `hermes-config` and `zqm-auth` contain identical `SOUL.md`

## Host identity
- This workstation is `ZQM-Node-1` at `192.168.1.218`
- `ZQM-Node-2` is `192.168.1.21`; treat it as a separate node
- Treat `zqm-localhost-findings/findings.md` and `management.md` as sensitive because they contain live LAN reconnaissance and remote-management playbooks for both nodes, including hostnames, OS builds, MACs, accounts, and a REDACTED password/credential reference