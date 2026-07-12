# Git Conflict Resolution for ZQM Repos

## `__pycache__` and runtime artifact conflicts

When `git pull` introduces merge conflicts concentrated in `__pycache__`, `.pyc`, `state.db`, `board.json`, or similar runtime/state files:

1. Do not bulk-recursively `git rm --cached` or `rm -rf` without explicit user approval.
2. Preferred resolution: remove the runtime files from the tree/index, keep the intent-bearing source changes, then `git add` the source files and commit.
3. If the user blocks recursive cleanup, stop and wait for explicit guidance.
4. `board.json` is typically a state/live-run artifact; if both deleted in HEAD and modified on remote, retaining the deletion is usually correct.
5. Intentionally merge source files like `council_engine.py`, README, `.gitignore` when `Auto-merging` succeeds or fails.

## Unrelated histories

Symptom: `fatal: refusing to merge unrelated histories`

Fix: set branch tracking explicitly or fold one history into the other with an explicit merge commit that preserves both graphs, then sign and push.

## Council merge decision protocol

If the user explicitly selects manual merge resolution:
1. Stop performing git changes in that repo immediately.
2. Report the exact conflict set with paths and conflict codes (`AA`, `UD`, `DU`, `DD`, `UU`, `M`).
3. Propose a minimal resolution strategy without retrying the blocked command.
4. Wait for explicit confirmation before any subsequent change to repo history or working tree.

## Council improvement protocol for 32-seal requests

When asked to "improve with the N seals":
1. Audit `council_engine.py` for existing agent arrays, message schema, and board state.
2. If no attestation fields exist, propose provenance metadata additions: `keyFingerprint`, `sessionHash`, `sealTags`, `topicDigest`.
3. Map agents to user seal taxonomy only if explicit code/config references exist; otherwise classify as absent and propose import-only option.
4. Leave quarantined content alone; create clean manifests only.
5. Present A/B/C/D-style options with one recommendation and wait for explicit authorization before changing council code or git history.
