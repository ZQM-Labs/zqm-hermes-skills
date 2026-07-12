---
name: zqm-repo-inventory-verification
description: 'Full diagnostics, deep verification, AND capability-mining across BOTH ZQM GitHub orgs (ZQM-Computing = 5 repos, ZQM-Labs = 32 repos; 37 total). Enumerate repos via gh, pull REAL content (languages + git/trees, master→main→develop fallback), classify by workstation-enhancement value (Tier 1/2/3 + not-applicable), exclude red-team/bounty tooling from friendly-workstation use, and stage-verify Tier-1 repos read-only (clone → verify prereqs → register MCP → prove end-to-end). SLASH COMMAND: /zqm-repo-inventory-verification TRIGGER: investigate all github repos, repo inventory, deep verification, capability mining, enhance workstation from our repos, clone state, file existence checks. DOMAIN: github, private repos, ZQM-Computing, ZQM-Labs, tree API, blob API, Windows host diagnostics.'
metadata:
  hermes:
    related_skills:
    - skill-publish-atomic
---

# ZQM Repo Inventory + Verification

Class-level skill for full-scope GitHub repo diagnostics AND capability-mining across
BOTH ZQM orgs (ZQM-Computing + ZQM-Labs). Use when the user asks to "investigate
repos", "deep verification", "repo inventory", "enhance this workstation from our
repos", "what in our repos can we use", "local clone state", "service correlation",
or "flag/redact sensitive data across repos".

## Methodology

1. **Enumerate BOTH orgs**: list ZQM-Computing (5 repos) AND ZQM-Labs (32 repos):
   `gh repo list ZQM-Computing --limit 1000 --json name,url,visibility,updatedAt,description,isPrivate`
   `gh repo list ZQM-Labs      --limit 1000 --json name,url,visibility,updatedAt,description,isPrivate`
   (The "18 private repos / ZQM-Computing only" figure in older notes is STALE —
   ZQM-Computing is 5 repos; the usable tooling lives in ZQM-Labs. Always list both.)
2. **Per-repo state**: `gh api repos/{org}/{repo}/languages` for language stats + sizes.
3. **Tree**: `gh api repos/{org}/{repo}/git/trees/{branch}?recursive=0` for top-level
   layout (use `recursive=1` only for deep single-repo reads). Branch fallback below.
4. **Selective doc reads**: fetch README/SKILL/INTEGRATION/PROTOCOLS/MATRIX/SCHEMA.
5. **Local clone state**: scan `C:\Users\zqmco\Documents`, `~/repos`, `~/github`.
6. **Service correlation**: socket connect to known ports (8000, 5000, 11434, 8188).
7. **File existence/content verification**: see `references/api-robustness.md`.
8. **Sensitive data**: see `references/sensitive-data.md`.
9. **Capability mining + report**: see `references/capability-mining.md`; consolidated
   artifact to `C:\Users\zqmco\Documents\repo_enhancement_report.md` (or
   `repo_investigation_full.md` / `deep_verification_report.md`).

## Capability mining — the usual real goal

The ask is usually "what in OUR repos can enhance THIS node?", not a pure audit.
Both orgs are the capability library. Source-verify every classification; never trust
the GitHub description as a capability statement. Full read-only recipe + the
2026-07-12 worked 37-repo inventory (Tier 1/2/3 + excluded) live in
`references/capability-mining.md`. Key rules:
- Classify EVERY repo, emit a COUNT per class + TOTAL (Tier 1/2/3 + not-applicable).
- EXCLUDE red-team/bounty tooling (zqm-sword, zqm-auth, bounty-tools) for friendly-
  workstation enhancement — capability-library but out of scope.
- To enhance: read-only `git clone --depth 1` into a STAGING dir, then verify prereqs →
  register MCP (`printf 'y\n' | hermes mcp add ...`) → PROVE end-to-end (e.g. ingest +
  query against local Ollama) BEFORE claiming it works. Tools load only after a Hermes
  restart.

## Branch fallback pitfall

`gh repo view --json defaultBranchRef.name` can report the wrong branch on some ZQM
repos. Do not derive the branch for tree/blob fetches from it. Instead always try
`master` → `main` → `develop` in that order.
Sheets this for 2026-07-09: `hermes-config` and `zqm-localhost-findings` had files on
`master` that do not exist on `main`, even though GitHub reported `main` as default.

## Output Artifacts

- `C:\Users\zqmco\Documents\repo_inventory.md` — full inventory
- `C:\Users\zqmco\Documents\repo_enhancement_report.md` — capability-mining result
- `C:\Users\zqmco\Documents\deep_verification_report.md` — verified content checks
- Clean up temp hermes-verify-* scripts after execution.

## Reference Files

- `references/api-robustness.md` — GitHub tree/blob API usage, branch fallback rules, and why `contents/{path}` must not be used for existence checks on ZQM repos.
- `references/sensitive-data.md` — confirmed sensitive files, redaction rules, and what is safe to include in reports.
- `references/no-code-signals.md` — methodology for categorizing repos that have no source-code signals (meta-repos, placeholders, upstream forks).
- `references/runtime-fixes.md` — local service bring-up and config recovery patterns observed during repo correlation, including invalid-escape JSON recovery and config path hygiene.
- `references/capability-mining.md` — the read-only capability-mining recipe (both orgs → classify Tier 1/2/3 → stage-verify → register MCP → prove end-to-end), plus the 2026-07-12 worked 37-repo inventory.

## Skill-sync caveat (zqm-hermes-skills → installed skills)
When consuming `zqm-hermes-skills` to refresh/extend installed skills:
- Diff FIRST. Copy whole NEW upstream-only categories + NEW files inside existing
  categories. EXCLUDE `.hub/` local state.
- HOLD conflicts (upstream differs from local) for user approval — do NOT auto-overwrite.
- **DETERMINE SYNC DIRECTION BEFORE OVERWRITING (2026-07-12 pitfall):** Do NOT trust a
  "newer-on-disk" / mtime read to decide which side is the revision. A fresh clone (today) is
  always "newer" than a skill installed weeks ago — that flag only reflects clone recency, not
  content authority. To find the actual superset, relabel the diff explicitly:
  `difflib.unified_diff(a=LOCAL_FILE, b=UPSTREAM_FILE)` → `-` lines are LOCAL-only,
  `+` lines are UPSTREAM-only. Count each; the side with MORE unique lines is the superset.
  On 2026-07-12 this revealed the INSTALLED skills were the supersets (computer-use +58 LOC,
  github-repo-management +448/-263, zqm-local-setup +158/-28 were LOCAL-only improvements) —
  i.e. the GitHub `zqm-hermes-skills` repo is STALE relative to this workstation. So the real
  enhancement direction is LOCAL → REPO (reverse sync: commit the 14 local-superset skills back
  to zqm-hermes-skills), NOT repo → local. Every one of the 14 conflicts was correctly HELD.
- PRESERVE local-only custom skills (e.g. forensics, session-history-enumeration,
  skill-automation-center, tavily-mcp, verification, zqm-bounty-hub,
  zqm-fleet-management).

## Tier-1 supervised-service gate (zqm-node-01-indexer)
- The indexer's engine is proven by a SCOPED build (e.g. set `indexer.DEFAULT_SCAN_ROOTS=[one
  safe dir]`; `build_index(rebuild=True)` → `search_index` returns ranked hits). Do this BEFORE
  any service wiring.
- The supervised-service install (`install-service.ps1` / `zqm_node_service.py`, Windows service
  auto-start + :5000 listener) is SIDE-EFFECTING: it hardcodes `OneDrive\Desktop\...` + a fixed
  `Python312` path and opens a port. PRE-GATE: (a) repoint the script to the staging dir +
  dynamic `python` resolution, (b) confirm :5000 is free (use localhost-management), (c) get
  explicit user approval. Installing the engine deps (whoosh, waitress, pywin32) is reversible and
  safe on its own; the SERVICE registration is the gate.
- `app.py` is authored specifically for this workstation (hardcoded zqmco paths, references
  `skill-automation-center`, Hermes memory dirs) — that is expected, not a defect.
- BUILD ISOLATED VENV ON PYTHON312: `python -m venv .venv` based on the standalone Python312
  (`C:\Users\zqmco\AppData\Local\Programs\Python\Python312\python.exe`), then
  `pip install whoosh flask waitress`. Do NOT pip into the ComfyUI venv or global `python` (3.11) —
  the repo scripts hardcode `Python312\pythonw.exe`, so the venv must be Python312-based or the
  service launch fails on missing modules. `pythonw.exe` is in `.venv\Scripts\` for silent launch.
- **WINDOWS SCHEDULED-TASK NON-ADMIN BOUNDARY (2026-07-12, proven):** agent terminal runs as
  `zqmco` = NON-admin (verify: `[Security.Principal.WindowsPrincipal]::IsInRole('Administrator')` = False).
  `Register-ScheduledTask` for a task running a USER SCRIPT (e.g. `pythonw.exe app.py` under
  `Documents\repo_staging`) returns **"Access is denied" (HRESULT 0x80070005)** — even though a
  trivial probe task (`cmd.exe /c echo`) REGISTERS FINE under the same non-admin account. A task
  executing a user script under a non-system path triggers the elevation requirement; a system
  binary does not. The repo's own `register-task.ps1` uses `-AtStartup` (admin-only) + hardcodes
  `OneDrive\Desktop\zqm-node-01-indexer` (wrong path, no symlink) and is SIGNED by Alex — repointing
  breaks the signature, so DO NOT reuse it; build a fresh unsigned task instead.
  - DO: launch the service as a foreground/background process in-session to PROVE it works
    (`netstat -ano | findstr :5000` → `curl /api/health` → expect `document_count` + ranked search).
  - DO: hand the user the EXACT elevated one-liner to finish persistence (run in ADMIN PowerShell),
    staging paths + `.venv\Scripts\pythonw.exe`. `-AtLogOn -User zqmco` auto-starts at every logon +
    auto-restarts on crash; swap for `-AtStartup` for pre-logon boot start.
  - DO NOT claim the service "is installed" when only the foreground process is up. The task
    registration was blocked by the account boundary — report it honestly with the finish command.
  - Non-admin alternate: leave the foreground process running, or create a Basic Task (Task
    Scheduler → runs as you at logon) which does NOT require admin.

## Non-Goals

- Do not modify repos, branches, releases, or settings without explicit approval.
- Do not push, install, or delete. Read-only `git clone --depth 1` into a STAGING dir
  for verification/enhancement is permitted (no remote side-effects possible).
- Do not claim suite-green coverage from writer/linter output alone.
- Do not apply red-team/bounty tooling (zqm-sword, zqm-auth, bounty-tools) to a
  friendly workstation — capability-library, but out of scope for enhancement.
