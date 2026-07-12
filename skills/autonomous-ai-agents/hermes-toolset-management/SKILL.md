---
name: hermes-toolset-management
description: "Enable, disable, and VERIFY Hermes toolsets and their actual tool exposure. Covers the critical gotcha that `hermes tools enable X` only flips a toggle — individual tools stay hidden until their `check_fn` credential gate passes. Use whenever the user asks to 'add tools', 'enable tools', 'turn on X toolset', or expects newly-enabled tools to appear in a session."
version: 1.0.0
author: ZQM homelab
license: MIT
platforms: [linux, macos, windows]
tags: [hermes, toolsets, tools, configuration, verification]
---

# Hermes Toolset Management & Exposure Verification

## The core gotcha (read first)
In Hermes, a **toolset** is a *namespace* and a **tool** is a *function*. `hermes tools enable video` flips the toolset toggle to ON, but each individual tool inside it is independently gated by a `check_fn` (and often `requires_env=[...]`) that only returns True when its credential/provider is present.

**Consequence:** `hermes tools list` reporting `✓ enabled video` does NOT mean the `video_analyze` tool is exposed to the model. It means the toolset is whitelisted. If the gate fails, the tool silently shows up nowhere — no error, no warning. This is the #1 source of "I enabled X but it doesn't work" confusion. **Always verify exposure; never trust the toggle.**

## When to use
- User says "add tools", "enable the X tool", "turn on toolset Y".
- You've run `hermes tools enable ...` and need to confirm the tools are actually callable.
- Auditing which capabilities are live in a given Hermes install.

## Procedure
1. **Enable the toggle** (no code, one command each):
   ```
   hermes tools enable video
   hermes tools enable x_search
   ```
   Loop over as many as requested.

2. **List state** to confirm toggles flipped:
   ```
   hermes tools list
   ```
   Shows `✓ enabled` / `✗ disabled` per toolset — but NOT tool exposure.

3. **Verify actual exposure** — the part most people skip. For each enabled-but-gated toolset, inspect its gate:
   ```
   cd <hermes-agent repo>     # git-installed: ~/.hermes/hermes-agent ; pip: site-packages
   grep -nE "requires_env|check_fn" tools/<name>*.py
   ```
   Then read the `check_fn` body to learn exactly what it needs:
   ```
   sed -n '/def <fn_name>/,/return/p' tools/<file>.py
   ```
   Check for credentials present:
   ```
   [ -f ~/.hermes/.env ] && grep -oE '^[A-Z_]+=' ~/.hermes/.env | sed 's/=$//' | sort || echo "(no .env)"
   ```

4. **Report the split honestly:** which toolsets are LIVE NOW (no credential) vs ENABLED-BUT-GATED (tool hidden until key added). Do NOT report "all N enabled" as "all N working".

5. **New-session requirement:** toolset changes take effect only on a fresh session — `/reset` in chat, or restart the CLI/gateway. Mid-conversation toggles do NOT reload (prompt-caching invariant).

6. **When the user doesn't have the tokens yet (common):** don't block. Pre-create `~/.hermes/.env` with the gated keys as *commented* placeholders so it's ready to paste into. Copy `templates/dotenv-stub.env` to `~/.hermes/.env`, then tell the user exactly which line to uncomment + fill per toolset (HASS_TOKEN, XAI_API_KEY, etc.). Verify the stub is secret-free: 0 active `KEY=VALUE` lines, placeholders present, ends with newline. This is real work that survives the "I'll get the key later" gap — see the [workspace-verification-status] discipline for the temp-check script shape.

## Gate patterns observed (Hermes v0.18.0)
Condensed; verify against your version via the grep in step 3. Full transcripts in `references/toolset-gate-reference.md`. Reusable blank `.env` with commented placeholders: `templates/dotenv-stub.env` (copy to `~/.hermes/.env`).
- **No gate (live immediately):** `video` (video_analyze), `context_engine` (thread/context tools).
- **Env-var gate:** `x_search` → needs `XAI_API_KEY`; `homeassistant` → needs `HASS_TOKEN` (long-lived HA token).
- **OAuth gate:** `spotify` → `hermes auth add spotify`; handlers live in a gateway module, so effectively a gateway/chat-platform feature.
- **Provider-plugin gate:** `video_gen` → needs an installed video-gen provider plugin (`provider.is_available()`); zero tools until one is added.
- **Platform gate:** `yuanbao` → gated on `HERMES_SESSION_PLATFORM == "yuanbao"`; on the CLI it ALWAYS shows zero tools. Enabling it on the CLI does nothing.

## Pitfalls
- Trusting `hermes tools list` "enabled" as proof of availability. It is not.
- Forgetting the new-session reload — user reports tools still missing mid-session.
- Assuming a missing `.env` means "no tools need creds". Gated tools just vanish silently.
- Editing the bundled `hermes-agent` skill to add this — it's protected. Clone the knowledge into a separate skill instead (this one).

## Verification
After enabling, grep the gate and confirm the required env var is absent → report as gated. If present, the next session should expose the tool. To prove exposure end-to-end, start a fresh `hermes chat -q` and ask it to call the tool; if it can't, re-grep the check_fn — the gate condition changed or the env var isn't loaded.
