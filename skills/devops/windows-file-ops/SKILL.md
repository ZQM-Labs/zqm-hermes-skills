---
name: windows-file-ops
description: Reliably FIND and READ files on the ZQM Windows host (MSYS/git-bash terminal + Hermes read_file/search_files). Covers the non-obvious path-form mismatch and stale cross-environment index entries that make read_file fail with "File not found" even when the file exists. Use for any "find/read this file", "inspect X", "where is Y" task across OneDrive, quarantine, repos, and AppData on this Windows machine.
---

# Reliable file discovery & reading on the ZQM Windows/MSYS host

## The problem
`search_files` (ripgrep-backed) finds files across mounted drives but returns
paths in a normalized form that `read_file` cannot always open directly, and it
surfaces **stale entries from other environments**. Blindly `read_file`-ing the
returned paths produces a "File not found" failure loop (the tool raises a
`same_tool_failure_warning` after ~3 retries).

## Gotchas (verified 2026-07-11, SOUL.md sweep)
1. **Path-form mismatch.** `search_files` may return `C:\Users\...\SOUL.md` or a
   `/Users/zqmco/...` form. On this MSYS host, `read_file` needs the MSYS form
   `/c/Users/zqmco/...` (drive letter → `/c`, `/d`, ...). A `/Users/...` path
   with NO drive prefix fails even though the file exists. **Translate to
   `/c/...` before reading.**
2. **Stale cross-environment index entries.** `search_files` can return paths
   that do NOT exist on this machine — e.g. `/opt/data/...`,
   `/tmp/hermes_no_plugins/...`, `/tmp/test_hermes/...`, or unmounted OneDrive
   "Google Drive" import subpaths. These are leftovers from previous/foreign
   environments. Verify before trusting.
3. **The read_file loop trap.** If a path 404s, do NOT re-call `read_file` with
   the same string — you'll trip the `same_tool_failure_warning` loop. Break out
   and diagnose with the terminal first.

## Procedure
- After `search_files`, **normalize every hit to MSYS form** (`/c/Users/...`,
  `/d/...`) and **verify existence with the terminal**:
  ```sh
  for p in "/c/Users/zqmco/AppData/Local/hermes/SOUL.md" "/c/Users/zqmco/quarantine/.../SOUL.md"; do
    [ -e "$p" ] && echo "EXISTS: $p" || echo "MISSING: $p"
  done
  ```
- Only `read_file` paths the terminal confirmed `EXISTS`.
- Treat `/opt`, `/tmp`, and unmounted OneDrive import paths as **suspect**; skip
  unless terminal confirms they exist on this host.
- When a hit lives in an unmounted OneDrive/import tree, the search index may
  resolve to a path the terminal cannot reach — check whether the real copy
  lives elsewhere (e.g. under `C:\Users\zqmco\OneDrive\...` reachable as
  `/c/Users/zqmco/OneDrive/...`).

## "Read them all" — verbatim + index, not a summary (2026-07-11)
When the user says "read them all" against a tree, deliver ALL files, not a digest:
- **Narrative `.md`/`.txt`**: dump VERBATIM (the agent's own words) into one
  consolidated `NAME_KB_FULL.md`. Prove-complete by asserting every
  `FILE: <name>` substring from the tree is present (0 missing), not by count.
- **Code/data/other** (`.py`/`.json`/`.js`/`.html`): don't verbatim-dump
  (megabytes of noise) — write a FULL INDEX: relative path, type
  (CODE/DATA/JS/HTML), byte size, and the first meaningful non-comment
  line (so each module's purpose is glanceable). This separates real logic
  from stubs/fixtures without a useless blob.
- **Cross-tree dedup**: if a second tree is a redacted/declassified superset
  (e.g. a OneDrive import mirroring a quarantine folder), prove the
  *set* matches (superset check on basenames minus `-Variant` suffixes)
  and report the declassified copy exposes what the redacted one withholds
  (read-only, never write the secrets out). Don't re-dump the duplicate.
- Deliverables this session: `ZBit_KB_FULL.md` (20 .md verbatim + 165
  indexed), plus `ZBit_KB_READ_ALL.md` (analysis) + `ZBit_KB_CODE_SURFACE.md`
  (real-vs-stub map) + `ZBit_AGENT_OMNIMAP.md` (source analysis).
  Pattern: analysis/map docs are SUPPLEMENTARY to the verbatim dump, not a
  substitute for it.

## Encrypt + reversible-relocate a plaintext cred tree (2026-07-11)
When authorized to remove the LAST plaintext-cred surface without hard-deleting:
1. `cryptography` is available in the ZBit_api venv (48.x). Build a
   **Fernet** key, write `.vault_key` (os.chmod 600 — NOTE: on
   Windows this is OFTEN IGNORED; follow with `icacls <f> /inheritance:r
   /grant:r "<USERNAME>:(R,W)"` so ONLY the owner has access).
2. `tarfile` (gz) each tree → `fernet.encrypt(blob)` → `<tree>.tar.gz.enc`.
3. **VERIFY round-trip BEFORE touching originals**: decrypt, count tar members,
   assert == original file count (this session: 185 and 206 both MATCHED).
4. Relocate originals via `shutil.move` into `<vault>/.deprecated/` —
   **reversible, NOT shredded**. Leave `.deprecated` as the undo buffer.
5. **ACL gotcha**: `os.chmod` 0o600 silently does NOT apply on Windows;
   the vault files came out 0o666 until `icacls /inheritance:r /grant:r
   owner:(R,W)` was applied. Always verify perms with `icacls <f>` and
   confirm only `<HOSTNAME>\<user>:(R,W)` appears.
6. Scan scope: a full `os.walk(C:\Users\...)` over OneDrive + sanitize_work
   TIMES OUT (>300s). Scope secret scans to specific known trees, not the
   whole profile.
Reversible + owner-locked. Irreversible `shred`/secure-delete is a
SEPARATE explicit authorization — never fold it into step 4.

## Worked example (the triggering task)
User asked to read all `SOUL.md`. `search_files` returned 15 hits; after MSYS
translation + terminal `-e` checks, only 6 were real on this host (live soul +
2 stock repo copies + quarantine lore doc + Node-1 lore doc + OneDrive import
lore doc + a skill template). The `/opt` and `/tmp` hits and second import copy
were stale and skipped. 3 of the lore docs were near-duplicate worldbuilding
with minor redactions (Hive/Garden, Neuron/AI, QSeal revealed) — reported as
reference only, not live config.

## When to use
Any file-locate/read/inspect task on this Windows host — especially spanning
OneDrive, quarantine, repos, and AppData — where `read_file` starts 404ing.

## Overlap note
`windows-host-audit` (host inventory from MSYS terminal) covers adjacent MSYS
quirks; this skill focuses specifically on robust file discovery/reading and the
search_files→read_file path-resolution trap. Consolidate if the curator prefers
a single MSYS-file umbrella.
