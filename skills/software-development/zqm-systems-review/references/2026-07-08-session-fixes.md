# 2026-07-08 Session Fix Log

## Auth root-cause fix
- `/api/auth/status` returned `authenticated:false` even though `~/.zqm-auth/token` existed.
- Root cause: `zqm_auth` module was missing from the filesystem; `app.py` import fallback set `zqm_auth = None`.
- Fix: created minimal `zqm_auth.py` with `parse_credentials(headers)` bound to `~/.zqm-auth/token`.
- Verified bearer token auth returns `user=zqmco`.

## Indexer profile-scoping fix
- `/api/config` returned unscoped `root_paths: ["C:\Users", ...]`
- `/api/search?q=python` returned `C:\Users\AlexZ\...` paths.
- Root cause: `_resolve_root_path()` existed but was not wired into `build_index()`; config written before scoping patch.
- Fix: added `_resolve_root_path()` / `_resolve_root_paths()` helpers and used them in `build_index()`.
- Rebuilt index; verified `/api/config` now shows `C:\Users\zqmco` and search returns scoped paths.

## Whoosh lock/recovery notes
- Rebuild can fail with `whoosh.index.LockError` if a stale `MAIN_WRITELOCK` exists.
- Running service can crash with `FileNotFoundError` for `.seg` during concurrent rebuild.
- Recovery: stop server, clear lock, rebuild, restart service.
- `INDEX_DIR` may resolve to `C:\Users\<profile>\.zqm-node-01-indexer\index`; confirm actual path before lock manipulation.

## Git push taxonomy
- `bounty-tools-naabu`: remote repo not found on GitHub; cannot push until remote exists.
- `wiki`: push blocked by `forensic/evidence/state.db` (~1.36 GB) exceeding GitHub 100MB limit; needs `git lfs` or history rewrite.
- `zqm-hermes-skills`: topo-equivalent histories; no true divergence; earlier `ahead/behind` was HEAD-only artifact.
- `ZQM-AI-Council`: merge conflicts in `__pycache__` artifacts, `board.json`, and `council_engine.py`; user-selected manual merge resolution.

## User preferences observed
- Explicit deny on bulk destructive git operations when ambiguously framed.
- Explicit deny on deletion of orphan files and quarantined CVG artifacts.
- Prefers concise, explicit blockers and manual merge decisions to force-fix options.
