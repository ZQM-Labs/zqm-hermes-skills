# Toolset Gate Reference (Hermes v0.18.0, 2026-07-11)

Exact `check_fn` / `requires_env` findings from enabling all 7 previously-disabled
built-in toolsets on a git-installed Hermes (C:\Users\zqmco\AppData\Local\hermes\hermes-agent, v0.18.0).
Re-derive against your own version with `grep -nE "requires_env|check_fn" tools/<name>*.py`
— gate conditions change between releases.

## Per-toolset gate
| Toolset        | Gate type        | Requirement / proof found                                          |
|----------------|------------------|--------------------------------------------------------------------|
| video          | none             | `video_generation_tool.py` check_fn exists but toolset has no cred gate for `video_analyze`. Live immediately. |
| context_engine | none             | Registered in `toolsets.py` (line 215), no `requires_env`/`check_fn`. Live immediately. |
| x_search       | env var          | `tools/x_search_tool.py` `check_x_search_requirements()` -> `requires_env=["XAI_API_KEY"]`. Needs xAI OAuth / XAI_API_KEY in `~/.hermes/.env`. |
| homeassistant  | env var          | `tools/homeassistant_tool.py` `_check_ha_available()` -> `bool(os.getenv("HASS_TOKEN"))`. Needs long-lived HA token in `~/.hermes/.env`. |
| spotify        | OAuth / platform | No `requires_env`/`check_fn` in core `tools/`; handlers live in a gateway module (only matched under `tools/mcp_tool.py`). Effectively a gateway/chat-platform feature -> `hermes auth add spotify`. |
| video_gen      | provider plugin  | `check_video_generation_requirements()` -> loops `list_providers()`; True only if a provider `.is_available()`. Zero tools until a video-gen provider plugin is installed. |
| yuanbao        | platform context | `_check_yuanbao()` -> True only when `HERMES_SESSION_PLATFORM == "yuanbao"` (reads `gateway.session_context.get_session_env`). On the CLI: always zero tools. Enabling on CLI does nothing. |

## Grep recipe used
```
cd <hermes-agent repo>
for t in video video_gen x_search context_engine homeassistant spotify yuanbao; do
  echo "--- $t ---"
  grep -nE "requires_env|requires_keys|check_fn|def check_|HASS_TOKEN|X_API|SPOTIFY|YUANBAO" tools/${t}*.py 2>/dev/null | head
done
# then read the check_fn body:
sed -n '/def <fn_name>/,/return/p' tools/<file>.py
# and check creds present:
[ -f ~/.hermes/.env ] && grep -oE '^[A-Z_]+=' ~/.hermes/.env | sed 's/=$//' | sort || echo "(no .env)"
```

## Files that did NOT exist (so don't grep for them)
- `tools/spotify_tool.py` — not present in core; spotify is gateway-side.
- `tools/context_engine_tool.py` — not a separate file; context_engine tools register elsewhere.
- `tools/video_tool.py` — not present; video analysis lives in `tools/xai_video_tools.py` and `tools/video_generation_tool.py`.
Grep `tools/` for the basename before assuming a `tools/<name>_tool.py` exists.
