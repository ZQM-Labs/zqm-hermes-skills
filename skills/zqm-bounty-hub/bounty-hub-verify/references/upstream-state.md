# Upstream state as of 2026-07-09

Probe command: `python scripts/verify_upstream.py`

## LIVE OBSERVATIONS

- Ollama 11434: healthy; `/api/tags` 200.
- FastAPI 8000: healthy; `/health` 200.
- ComfyUI 8188: listener UP after foreground restart; `/` 200, empty `/prompt` 400 `prompt_no_outputs`. Those logs alone are misleading; startup succeeded, no exception surfaced.
  `Error handling request from 127.0.0.1` in `user/comfyui_8188.log` without traceback is prompt-validation failure, not process death.
- Node-01 indexer 5000: `/api/health` 200 from 127.0.0.1, but `netstat` binds to `127.0.0.1`. LAN probes to `192.168.1.218:5000` refused because of localhost-only binding, not because the process is dead.
- Node-02 indexer 192.168.1.21: 100% packet loss; host offline.

## FILESYSTEM STATE

- `C:\\Users\zqmco\.zqm-node-01-indexer\config.json`: present; `last_indexed` present but `"skip_stats": {"scanned_dirs": 1, "root_skip_unchanged": 4}` and `"total_files": 0`. This is stale state-empty, not timeouts.
- `C:\Users\zqmco\.zqm-node-02-indexer\config.json`: absent.
- Active checked-out indexer now lives at `C:\Users\zqmco\Documents\zqm-node-01-indexer\`; PowerShell `install-service.ps1` and scheduled task still point to the older OneDrive Desktop path.

## REPAIR NOTES

- Rebind path: change `host="127.0.0.1"` to `"0.0.0.0"` in indexer launch code/service wrappers and re-register the scheduled task.
- Reindex one-shot: after rebind, force at least one real walk before declaring the indexer populated; the first post-fix run often reports `root_skip_unchanged` until `root_walk_state` is refreshed by a real scan.
- Once Node-01 is reachable from the LAN, `192.168.1.218:5000` should respond to `/api/health`.

## OPERATIONAL MEANING

- Local hunting/reporting/triage via FastAPI + direct filesystem: possible.
- Live H1-backed automation through the indexer path: blocked until LAN rebind, real reindex, Node-02 host online, and ComfyUI validated with an actual output-producing workflow.
