---
name: artifact-provenance-review
description: Inspect and triage AI-agent memory/identity artifacts (SOUL.md, USER.md, knowledge bases, chain*.json) found on the user's machines. Establish provenance BEFORE judging trust, separate an agent's aspirational lore from real verified infra, and never propose deleting a user-owned agent's memory without explicit confirmation. Use when asked to 'inspect / read / diff' a soul/config/memory file, or when encountering agent artifacts in quarantine/contaminated/import folders.
---

# Artifact Provenance Review

## When to use
- User asks to inspect / read / diff a `SOUL.md`, `USER.md`, agent config, or "memory" file.
- You find agent-identity or knowledge-base files in folders named `quarantine`, `CVG-CONTAMINATED`, `archive`, `imports`, etc.
- You're auditing what an agent believes vs. what's actually real.
- User wants a discovered first-party agent REVIVED (re-homed onto the verified fleet via an API layer), not scrubbed — see `references/revive-agent-via-api.md`.

## Core discipline (learned the hard way)
1. **Provenance ≠ folder name.** A folder called `CVG-CONTAMINATED` or `quarantine` is a label the USER chose — it is NOT a verdict that the contents are external or malicious. Treat as user-owned/first-party until proven otherwise. In one session an agent's memory store was mis-flagged as "3rd-party/untrusted lore" and nearly scrubbed; the user corrected: "not 3rd party… just memories and dreams from another agent we created." These files are FIRST-PARTY.
2. **Never propose deletion of a user's own agent's memory/code without explicit confirmation.** Offer options, don't assume. Default to leaving it in place. (A clarify() with explicit choices is the right move, not silent scrubbing.)
3. **Separate lore from reality.** Agent SOUL/identity docs routinely contain aspirational or fictional content: invented hardware specs (e.g. "HP Pavilion AIO i7-13700T" that contradicts the real Node-1 = ASUS Vivobook K6602VV / i9-13900H), imaginary blockchains ("ZBit mining", "QSeal chain", "4,572 blocks", "CHSH 2.63"), services/ports that don't exist. Flag these as NARRATIVE; cross-check against VERIFIED infra (memory + live probes) before trusting any fact in them.
4. **Same doc at multiple redaction levels.** You may find the identical identity doc with `[REDACTED]` placeholders (quarantine copy) and a "declassified" copy (Google-Drive import) where redactions are filled in (real LAN IP, chain name, NAS name). Diff them to recover what was hidden — but still verify against reality.

## Technique (this Windows/MSYS host)
- **Find:** `search_files(pattern='SOUL.md', target='files')` returns matches, but the paths use a `/Users\...` (backslashed) form that `read_file` CANNOT open. **Retry with the MSYS form `/c/Users/<user>/...`** — that's what `read_file` accepts.
- **Verify existence** with `terminal`: `for p in ...; do [ -e "$p" ] && echo EXISTS || echo MISSING; done` before batch-reading. Filename search may return stale entries from other environments (`/opt/...`, `/tmp/...`) that don't exist here — confirm, then mark absent ones STALE.
- **Read:** `read_file` with the `/c/Users/...` path.
- **Diff:** `terminal` `diff a b` on resolved paths (handles CRLF; trailing-newline differences show as "\ No newline at end of file").

## Output shape
- State which file is the LIVE config (typically `~/AppData/Local/hermes/SOUL.md` = stock default) vs. which are other agents' memory/lore.
- For each artifact: provenance (user-built agent? stock repo copy? skill template?), redaction level, and fact-vs-fiction flags.
- If a delete/scrub was considered, state it was NOT done and why.

## References
- `references/agent-memory-triage.md` — worked example: the ZBit/ZQM SOUL.md triage (3 copies, exact diffs, fiction flags).
- `references/revive-agent-via-api.md` — REVIVE path: re-home a discovered agent's identity onto verified infra via FastAPI + LiteLLM; re-scrub PII that survived a prior sanitize pipeline; honest BLOCKED-at-Ollama-key status.
