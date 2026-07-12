---
name: zqm-systems-review
description: 'ZQM full systems review and integrations: verify MCP servers, enumerate
  skills, run full-scope gym review, validate local services, and produce a single
  integration status report.'
version: 1.0.0
author: zqmco
license: MIT
platforms:
- windows
- linux
- macos
category: software-development
metadata:
  hermes:
    tags:
    - systems
    - review
    - integration
    - mcp
    - gym
    - verification
    related_skills:
    - audit-sqlite-sink
    - data-eda
    - hermes-cron-ops
    - homelab-backup
    - ollama-fleet-lb
    - ollama-recovery
    - openclaw-mesh
    - skill-publish-atomic
required_commands: []
required_environment_variables: []
missing_required_commands: []
missing_environment_variables: []
setup_needed: false
setup_skipped: false
readiness_status: available
linked_files:
- references/software-management-workflow.md
- references/live-snapshot-reference-protocol.md
- references/council-probe-notes.md
- references/council-activation-and-delivery.md
- references/council-runtime-model-fit.md
- references/windows-shell-subprocess-pitfalls.md
- references/council-repo-maintenance-telemetry.md
- references/council-activation-runtime-pattern.md
- references/indexer-rebuild-protocol.md
- references/github-api-trees-not-contents.md
- references/skill-library-topology.md
- references/claim-chain-verification.md
- references/stability-diagnostic.md
- references/genesis-lore-classification.md
---
# ZQM Full Systems Review and Integrations

Perform end-to-end verification of the Hermes/ZQM workstation stack.

## Contract

Output a single integration status report with these sections:
1. MCP servers/tools count
2. Installed skills count
3. Local service status
4. Gym/benchmark status
5. Skill-specific deep checks
6. Blockers/repairs
7. Overall pass/fail

## Procedure

### 1. MCP and tooling
- Reconnect MCP servers and verify tool count.
- Confirm cua-driver is active.

### 1a. Local inter/intra-session comms
- Verify these surfaces locally only: kanban board, local webhook, API server/gateway SSE endpoints, dashboard.
- Do not enable cloud chat transports unless explicitly requested.
- Config check: `streaming.enabled`, `transport`, and gateway platforms should reflect local-only intent.
- Evidence checklist before declaring gateway/SSE pass: same-interpreter import check, one foreground launches + log tail, port probe for 8642/9119/8644, and `hermes gateway status` only if it returns within timeout. If any check is skipped, report status as `BLOCKED` with the exact missing evidence.
- Do not retry identical blind launches after a fresh failure snapshot; inspect actual MCP/process conflicts instead.

## Claimed-system existence check
When the user asks to investigate a named system—e.g., zseals, qseals, gseals, alpha seals, neural tattoo, identity mesh—treat it as a multi-source existence check before deeper diagnostics:
1. Run a filesystem/repo scan for exact-term matches across active roots, paste exports, and state stores.
2. If matches appear only inside old paste exports or redacted path strings, classify as **historical artifact, not live system**.
3. If matches appear in code/config/services, classify as **present** and proceed to route/process enumeration.
4. If no local match, probe common local ports and known remote endpoints; if still absent, report **not present on this node** and stop.
5. Do not invent bridges or wrappers for absent systems; report the absence with evidence paths.
6. For seal/neural-tattoo-style terms on ZQM, default classification after exhaustive scan is **historical CVG-era project residue**; only promote to active if live code/config is found.

## Council/SAC route probe pattern
On this workstation, `127.0.0.1:9000` is the Skill Automation Center, not a council server probe target for `/council` paths.
- `/` returns SAC root HTML with `user=None`.
- `/council`, `/council/board`, `/api/council/board`, `/health`, `/api/health` all return **404** on SAC.
- If the user asks to “utilize the council,” do not blind-retry missing SAC council routes.
- True council target, when present as source code, is standalone repo code, typically with:
  - Service entrypoint: `service.py` or equivalent FastAPI app, default port **8000**
  - Council routes: `/council/topic`, `/council/round`, `/council/summarize`, `/council/board`, `/council/last`
  - Agent routes: `/agent/tool`, `/tool`
  - Health route: `/health`
  - Auth: bearer/header token or environment-gated `/tool` auth when `ZQM_COUNCIL_TOKEN` is set
  - Backend dependency: often **Ollama** at `127.0.0.1:11434`; council is non-functional without it or another configured model backend
  - Repo-local OpenClaw tooling often lives at `tools/openclaw/openclaw.ps1`. If it hardcodes a model not present in `ollama ps`/`/api/tags`, treat it as an active failure path and patch it to resolve via `ZQM_COUNCIL_MODEL` -> `OLLAMA_MODEL` -> `/api/tags` first entry -> `qwen3:8b` fallback, not to a missing model.
- Startup sequence for council source code:
  1. `python -m py_compile` entrypoints
  2. Import probe for runtime deps; install minimum missing deps only
  3. Start service bound to `127.0.0.1`
  4. Call `/health`; degraded status without model backend is expected
  5. Set `ZQM_COUNCIL_TOKEN` and verify `/tool` auth behavior before wider use
- If council source code exists but Ollama/model backend is missing, report council as **ready code, blocked runtime**.

## Runtime-data preservation policy
`.quarantined/`, `board*.json`, `deliberation.log`, and similar are session state/evidence, not garbage.
- Do not delete until contents are inventoried.
- Recover corrupt/overwritten histories only with operator confirmation; fallback is quarantine or copy, not wholesale removal.
- For council artifacts, prefer `.quarantined/` as audit history.

Council provenance/schema audit notes: `references/2026-07-08-council-investigation.md` captures the current 32-agent layout in `council_engine.py` and residual gaps for seal/attestation improvement.

Preferred verification artifact for JSON/config edits on this host:
- Write an ad-hoc probe under `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*.py` using `tempfile.mkstemp(prefix="hermes-verify-", suffix=".json", dir=...)` for the report path.
- Run it with system Python, capture stdout/stderr.
- Treat the result as ad-hoc runtime verification; explicitly state its scope and cleanup status.

Common root cause: Ollama generation times out mid-run with large models; the council service stores empty turns instead of raising a 500. Directly probe `POST http://127.0.0.1:11434/api/generate` with the configured model; a timeout there confirms backend, not council routing. Fix path: use a smaller Ollama model suited to the hardware, then re-run `/council/round`.

Current adaptive resolver in `council_engine.py`:
- Env order: `ZQM_COUNCIL_MODEL` -> `OLLAMA_MODEL` -> default installed `qwen3:8b`
- Installed-model discovery from `/api/tags`, cached for process lifetime
- Stream and non-stream paths both use the resolved model, not the hardcoded `"hermes3:latest"`
- On this host, large models such as `36B Q4_K_M` can time out despite being installed; preference should default to the smallest installed working model when the preferred model stalls.

## Ollama model-fit check before council deliberation
Before assuming council will deliberate:
1. Query `http://127.0.0.1:11434/api/tags`.
2. For each model, note `parameter_size`, `quantization_level`, and `context_length`.
3. If the only model is a large file or has very large context on hardware with limited RAM/VRAM, expect generation timeouts on complex council topics.
4. Prefer smaller models or lighter quantization on small-form-factor Windows hosts.
5. **Deletion policy:** do not remove a too-large model proactively. Treat coexistence on disk as acceptable, and only delete the oversized model if the operator explicitly rejects disk-only coexistence after a successful `qwen3:8b` generation test.
6. After any model-fit fix, rerun `/council/round` and re-check `/council/last` `text` fields before declaring utilization successful.

## Ollama LAN endpoint audit (multi-host inventory + security)
When the user asks to inventory, locate, or assess Ollama model servers across the LAN,
use the probe recipe in `references/ollama-lan-audit.md`. Key discipline points:
- Full /24 parallel scan on :11434 (`/api/tags` HTTP 200 = a live server). Rescan fresh
  every time; do NOT trust a prior IP list (nodes reboot, IPs shift).
- Enumerate real model counts + sizes from `/api/tags` `size` fields (NOT a remembered
  number). Diff the model-name SETS between two hosts to decide alias vs DISTINCT — identical
  lists = same backend; disjoint/partial = distinct hosts. A prior agent wrongly called
  Node-2 (192.168.1.21) a "DNS alias" of Node-4 (192.168.1.215); their lists were disjoint,
  so they are separate machines.
- Version currency: query `GET /api/version` per host AND confirm latest stable via the
  GitHub releases API (`api.github.com/repos/ollama/ollama/releases`), NOT web_search
  (web_search returned a stale "0.30.10 latest" while 0.31.2 was current). Treat `v0.x.0-rcN`
  as pre-release; don't call a host outdated just because it's below an -rc.
- Running models: `GET /api/ps` shows what's loaded NOW (`size_vram`, `quantization_level`,
  `context_length`). Empty `{"models":[]}` = nothing running.
- Exposure: Ollama ships NO native auth. Prove the gap: `POST /api/show` (existing model) →
  200 without creds; `POST /api/generate` (BOGUS model) → 404 (not 401/403) = open endpoint.
  Anyone on the LAN can list/run/pull/delete models. Mitigate: firewall 11434 to source IPs,
  bind 127.0.0.1 behind nginx+basic-auth/tunnel, or set `OLLAMA_ORIGINS`.
- WAN exposure is UNVERIFIABLE from inside the LAN — explicitly flag it as a gap; tell the
  user to check the router for port-forwarding / exposed 11434. Do not claim safe/exposed.

## Adaptive model fallback and healthy-endpoint classification
- If the preferred local Ollama model stalls/hangs under memory pressure, prefer the smallest installed working model automatically for operational probes; keep the large model installed unless the user explicitly requests removal.
- `/health` returning `status: degraded` can still indicate the service process is alive; degraded is not equivalent to down. Use `/health` plus direct `/api/generate` and representative application routes to classify true outage vs. degraded runtime.
- Webhook alias `openclaw agent ...` can mask backend/model mismatches; probe the canonical Ollama `/api/generate` path directly for determining model health, then adjust service/tooling defaults to an installed working model.
`.zqm-auth` is a distinct Hermes-like subtree with its own git repo, instances, skills, dogfood artifacts, and wiki.
- Instances: `zqmco` (`state.db` ~100MB + WAL), `alice` (`session_tokens.txt`), `bob` (`session_tokens.txt`).
- Skills: enumerate `skills/` subdirs and record count.
- Dogfood: Basecamp, GitLab, Instacart, Shopify, Valve probes/scopes under root.
- Wiki: `shared/wiki/index.md`; treat as separate durable store from `~/wiki`.
- Cron: `cron/jobs.json` and ticker files.
- When asked to audit all systems, include `.zqm-auth` as a separate subsystem row in the report.
- Remote: `origin https://github.com/ZQM-Computing/zqm-auth.git`; treat as private code source, not live service.

### 2. Skill inventory
- The registry (via `skills_list`) is the AUTHORITATIVE source of what is actually loaded. Get it FIRST: record the registered count + category breakdown. Do NOT trust raw disk counts.
- On this Windows/MSYS host the canonical loaded tree is `AppData\Local\hermes\skills` — NOT `AppData\Roaming\hermes\skills`. `$APPDATA` resolves to Roaming here, so a naive `find $APPDATA/hermes/skills` returns EMPTY and misleads. Use the explicit `Local` path or the literal `/c/Users/zqmco/AppData/Local/hermes/skills`.
- On-disk there are several DUPLICATE/STALE skill trees (`.hermes/skills`, `.hermes/shared/skills`, `.zqm-auth/shared/skills`, `zqm-hermes-skills`, per-instance `instances/{alice,bob}/skills`) that are NOT all live. The registered count (e.g. 88) is the live number; disk SKILL.md counts run higher because of mirrors. Use the discovery recipe in `references/skill-library-topology.md`.
- Report the registry count as `Skills installed`, and note the on-disk tree divergence as a cleanup item rather than inflating the live number. A future dedup pass is warranted but out of scope for a review.

### 3. Local services
- Check Hermes dashboard ports.
- Check local indexer/web apps if configured.
- Record PIDs and URLs.

### 4. Full-scope gym review
- Dispatch: `python <skill-gym>/scripts/gym_launcher.py full --auto`
- Capture manifest with pass/fail per skill.
- Surface any skill that does not return `"benchmark": "ok"`.

### 5. Skill deep checks
Run the appropriate verifier for skills modified since last review:
- `quantum-computing`: `bash scripts/run_tests.sh`
- Other skills: use their canonical verifier or `gym_launcher.py benchmark <skill> --auto`

### 6. Integration points
- Verify MCP -> Hermes -> skill dispatch.
- Verify cron jobs list.
- Verify shared store/wiki paths if configured.

## Windows service restart pattern for indexer/web apps

When a resident Python service must be reloaded after a code fix:
1. Identify the process with PowerShell: Get-CimInstance Win32_Process -Filter "Name='pythonw.exe'" | Select-Object ProcessId,ExecutablePath,CommandLine
2. If startup shortcuts/launchers reference the same app.py, terminate the old PID with taskkill /F /PID <pid>.
3. Ignore shell wrapper noise like bash: no job control in this shell; that is the wrapper exiting, not the application. If the port is still LISTENING after the wrapper exits, the actual server process is still running and must be killed before relaunch.
4. Launch the new process via terminal(background=true) from the project directory; do NOT use shell wrappers like nohup/disown/&
5. Wait 5-10s, then verify readiness with direct port probe + representative API path before rerunning health-check endpoints

## Ad-hoc verification script contract
This host lacks a canonical test suite for many ZQM services; use ad-hoc runtime probes instead.
1. Write a focused probe to `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*.py` using an OS-safe temp path.
2. Run it with the **project venv interpreter** when the changed code imports `whoosh`, `requests`, or other deps not present in system Python.
3. Treat the result as ad-hoc runtime verification; explicitly state its scope and cleanup status.
4. If verification is not possible, explain the concrete blocker instead of claiming the work is fully verified.
5. After successful verification, clean up the temp script. If cleanup fails, report the reason.

## Indexer dual-index/lock-recovery pitfall

On this host, `INDEX_DIR` can resolve to `C:\Users\<profile>\.zqm-node-01-indexer\index`, while older operational guidance assumes `C:\ProgramData\ZQM-Node-01-Indexer\index`. A mismatch between these paths creates two failure modes:
- Removing a lock from the `ProgramData` index while the running server reads `.\zqm-node-01-indexer\index` does not free the actual holder.
- Opening `ix.searcher()` during an in-progress rebuild can hit `FileNotFoundError` on a `.seg` file still being written.

Recovery:
- Verify `INDEX_DIR` at runtime before touching locks.
- During rebuilds, ensure no active writer holds the same dir; stop the resident server if necessary.
- After rebuild, rerun endpoint probes instead of asserting health from build output alone.

## Windows taskkill syntax

Use `taskkill /F /PID <pid>`. The form `taskkill //F //PID <pid>` fails with `Invalid argument/option`.

## User authorization shorthand

Replies like `yes please`, `all of the above`, or specific option letters (`A`, `B`, `C`) authorize STAGING that vector (log as open_question + draft a dry-run patch script). A SEPARATE explicit `apply` / `go` is required before any system mutation.
- Apply this only to non-destructive holistic workflows.
- Destructive or history-rewriting actions still require explicit confirmation.
- If the user denies a destructive git operation, stop immediately; do not retry via alternate destructive paths.

## Council repo-maintenance telemetry pattern

When the user asks to improve the council's ability to maintain repos:
1. Do not edit conflicted service entrypoints directly during an unmerged merge state. If `service.py` or shared modules are in `AA`/`UD`/`UU` conflicts, introduce clean new modules instead.
2. Add `tools/repo_tools.py` with read-only helpers: `_git(args, cwd)`, `repo_status(path)`, `known_repo_telemetry()`, and `KNOWN_PATHS`.
3. Add `tools/maintenance_tool.py` with `score_repo_health(telemetry)` and `maintenance_brief()` for council-facing health output.
4. Create `tools/__init__.py` if missing so imports are package-relative.
5. Do not yet wire a `/maintenance/repos` API endpoint from `service.py` until the merge conflicts there are resolved; instead publish the tooling via direct Python invocation or shell script.
6. Ad-hoc verify with a temp probe under `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*.py`; assert `len(KNOWN_PATHS)` coverage, expected 4 councils / 32 agents, and score logic (clean=100, deductions for ahead/behind/dirty).

## Unmerged-file protection rule for council/service edits

If `git status --short` shows conflict codes in a service module you intend to edit:
- Do not patch `service.py`, `utils/helpers.py`, `config.py`, or anything in `AA`/`UD`/`UU` state.
- Introduce new files in subpackages (`tools/`, `utils/next/`) that remain clean.
- After the operator resolves the merge, then wire the new modules into the service layer.

## Stale-verification evidence guard
On this host, prior failed verifications can persist in the conversation context as if they were current.
- The system can surface an old `Traceback` as "verification status: stale" even after fresh passing runs.
- Always re-run the focused verification script after code edits and present the newest terminal output as the source of truth.
do not declare a fix verified based on a write_file/edit returning `"status":"ok"`; that validates syntax, not runtime behavior.

Tamper-evident chaining of the ledger itself (the "hash claims" verb): see `references/claim-chain-verification.md`.

## Post-review remediation order
After a full-systems diagnosis, prefer this order:
1. Auth fix first; authenticated endpoints unlock safer rebuild/update flows.
2. Indexer root-path fix + rebuild after auth.
3. Git divergence sync after local state is consistent.
4. Disk recovery only after normal service paths are healthy.

## Indexer rebuild lock-error recovery protocol

Symptom: `build_index(rebuild=True)` fails with `whoosh.index.LockError` after a code/config fix.
Root cause: a stale `MAIN_WRITELOCK` or active writer holds the index, often because the running service was not stopped before rerunning the build script.

Fix path:
1. Inspect the index dir for lock files: `find <INDEX_DIR> -maxdepth 1 -name '*lock*' -o -name '*WRITELOCK*'`
2. Inspect active Python processes and port listeners on the indexer port.
3. If no legitimate writer is active and lock ownership is clearly stale, remove the lock files and rerun. If ownership is unclear, stop the resident service first.
4. A rebuild should be rerun **after** the index lock is cleared, not from the same stale service session.

## Indexer rebuild lock recovery

Symptom seen in this session:
- `whoosh.index.LockError` on `build_index(rebuild=True)` after code/config fixes.
- A background process crashes with `FileNotFoundError` for a `.seg` file while a rebuild is still in progress.

Root-cause pattern:
1. A stale `MAIN_WRITELOCK` or active `pythonw.exe` process still owns the Whoosh index.
2. The active service and rebuild script race; if they share the same index dir concurrently, one succeeds and the other reads a torn segment.
3. On Windows, shell-wrapper lines like `bash: no job control in this shell` are noise and can mislead cleanup; always verify actual port ownership before killing processes.

Working recovery sequence:
1. Verify index dir for `*WRITELOCK*` / `*.lock`.
2. Identify the actual Python process holding the indexer port via `netstat -ano | grep LISTENING`, not by wrapper output alone.
3. Kill the old service PID with `taskkill /F /PID <pid>`.
4. Remove stale lock files only after confirming the holder is gone.
5. Relaunch the service via Hermes `terminal(background=true)`, not shell background wrappers.
6. Re-verify endpoints before running another rebuild.

## Portfolio-level git push classification for remaining divergences

After full-systems review, do not leave repos blocked-on-push without a per-repo disposition:
- `push succeeded` -> clean record.
- `fetch first / remote ahead` -> classify as pull-merge pending.
- `pre-receive declined` from file size -> classify as LFS/history rewrite needed.
- `repository not found` -> classify as remote creation/policy decision needed.
- `refusing to merge unrelated histories` -> classify as history-alignment decision needed; do not force history merges without operator confirmation.
- Unauthorized destructive/bulk cleanup on merge conflicts -> report as operator-managed merge and move on to other workstreams.

## Council 32-seal/void-tag metadata improvement pattern

When the user asks to improve function using the 32 council agents/seals, or references “the void speaks”:
- Treat “the void speaks” as an **explicit null-signal metadata event**, not a remote service, magic call, or quarantined artifact reference.
- Add `SEAL_TAXONOMY` to `council_engine.py` mapping each agent id to `(seal, domain)` tuples; keep len == 32.
- Add `VOID_TAG = "void"` and emit `voidTag` on every deliberation message when `text` is empty/error/null.
- Preserve existing runtime paths; do not change recorded verdicts, access control, or backend routing.
- Validate with an ad-hoc probe that asserts `len(SEAL_TAXONOMY) == 32`, expected `council-32` mapping, and message-schema field presence.

## Observed push blocker taxonomy (added from 2026-07-08 review)
- `Repository not found` -> remote missing on GitHub; verify/create remote before retrying.
- `refusing to merge unrelated histories` -> local and remote histories were created independently; classify as history-alignment decision and do not force a merge without operator confirmation.
- `pre-receive declined` large file >100MB -> needs `git lfs` or history rewrite; operator must authorize non-destructive remediation.
- Operator-managed merge conflicts -> if user denies destructive/recursive cleanup in a conflicted repo, stop git operations in that repo and report the exact conflict set; continue with other repos.

## Council provenance/schema audit notes
- User focus: improve system functionality using the 32 configured council agents/seals.
- Promote seal taxonomy to metadata on messages; do not gate execution on seals unless explicitly requested.
- Quarantined boards under `.quarantined` remain inaccessible under active zero-trace boundary; create fresh `board.json` manifest only.

## Council merge decision protocol

If the user explicitly selects manual merge resolution:
1. Stop performing git changes in that repo immediately.
2. Report the exact conflict set with paths and conflict codes (`AA`, `UD`, `DU`, `DD`, `UU`, `M`).
3. Propose a minimal resolution strategy without retrying the blocked command.
4. Wait for explicit confirmation before any subsequent change to repo history or working tree.

## ZQM-AI-Council merge investigation pattern

When `ZQM-AI-Council` shows merge conflicts plus unrelated/duplicate histories:
1. Inspect `git status --short`, `git diff --name-only --diff-filter=U`, `git rev-parse MERGE_HEAD`, `git rev-parse CHERRY_PICK_HEAD`, and `git reflog | head -10`.
2. Do not retry the blocked merge blindly. Instead classify:
   - duplicate local commits vs remote tip
   - unmerged `__pycache__` / `.gitignore` noise
   - authored deletions like `board.json` that must be preserved
   - service files in `AA`/`UD`/`UU` state that must not be patched directly
3. If the user denies destructive pycache cleanup, do not attempt alternative recursive deletion. Proceed only with non-destructive moves.
4. Minimal safe resolution when histories are nearly aligned:
   - `git merge --abort`
   - `git reset --soft origin/master`
   - Unstage pycache adds/deletes without removing disk files
   - Update `.gitignore` to match intended ignore rules
   - Preserve authored deletions and changes
   - Commit only authored files
   - Do not force-push without explicit confirmation

## Council service-module protection during merges

When `service.py`, `utils/helpers.py`, `config.py`, or any module shows conflict codes (`AA`/`UD`/`UU`) during an unmerged merge state:
- Do not patch those files directly.
- Introduce clean new modules in subpackages (`tools/`, `utils/next/`) that remain unmerged.
- After the operator resolves the merge, wire the new modules into the service layer.
- This avoids corrupting metadata, board, or health routes while the merge is live.

## Live state preservation during service restarts

Before restarting a resident service:
- Capture the current verified state from live endpoints.
- After restart, compare new endpoint responses against that snapshot before repeating large operations like rebuilds or syncs.
- If auth/index/cache paths were corrected, the next verify sweep must confirm those three things are live before changing the todo state from "pending" to "completed".


## GitHub push-time blocker taxonomy

When `git push` fails, classify before retrying:
- `Repository not found` -> verify repo existence via `gh repo view <org>/<repo>` or GitHub API, then recreate/repair remote before retrying.
- `pre-receive hook declined` due to file size -> large tracked file exceeds GitHub 100MB limit; use `git lfs track`/migration or remove the oversized path from history with `git filter-repo`/BFG, then force-with-lease-push only after confirming local intent.
- `fetch first` -> remote contains commits you do not have locally; run `git pull origin <branch> --rebase`, resolve intentionally, then push.
- `refusing to merge unrelated histories` -> branches were created independently; resolve by setting branch tracking explicitly or folding one history into the other with an explicit merge commit that preserves both commit graphs, then signing and pushing.

## Windows service reload pattern for indexer/web apps
When a resident Python service must be reloaded after a code fix:
1. Identify the process with PowerShell: `Get-CimInstance Win32_Process -Filter \"Name='pythonw.exe'\" | Select-Object ProcessId,ExecutablePath,CommandLine`
2. If startup shortcuts/launchers reference the same `app.py`, terminate the old PID with `taskkill /PID <pid> /F`
3. Launch the new process via `terminal(background=true)` from the project directory; do NOT use shell wrappers like `nohup`/`disown`/`&`
4. Wait 5-10s, then verify readiness with direct port probe + representative API path before rerunning health-check endpoints

## Indexer `/api/health` peer-probe pitfall

On this workstation, `zqm-node-01-indexer` `/api/health` can be broken in two ways:
1. Missing import: `urllib.request` is used but not always present in `app.py`
2. Wrong paths: after the code fix, the loop still probed `/api/health` on both dashboard and indexer, but the dashboard here is the Skill Automation Center on `:9000/`, not the indexer.
Use explicit dashboard and indexer probe paths with a 5s timeout, rather than a shared loop.

## Preferred verification artifact for JSON/config edits on this host
- Write an ad-hoc probe under `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*.py` using `tempfile.mkstemp(prefix="hermes-verify-", suffix=".json", dir=...)` for the report path.
- Run it with system Python, capture stdout/stderr.
- Treat the result as ad-hoc runtime verification; explicitly state its scope and cleanup status.

## GitHub org-wide private-repo inventory

When the user asks to review, investigate, or inventory all private repos under a GitHub user/org—especially this `ZQM-Computing` account—use this sequence. It avoids local-only blind spots and handles `gh` schema quirk differences between Windows and upstream docs.

1. `gh auth status` first; if not logged in, pause and report.
2. `gh repo list <org> --limit 1000 --json name,url,visibility,updatedAt,description` to enumerate every private repo.
3. For each repo, build a summary row:
   - Primary metadata: `gh repo view <org>/<repo> --json name,visibility,primaryLanguage,diskUsage,topics,defaultBranchRef,issues,pullRequests,description,createdAt,updatedAt,pushedAt,isArchived`
   - Language bytes: `gh api repos/<org>/<repo>/languages`
   - README preview: fetch `/contents/README.md`, base64-decode, preview first 12-14 non-empty lines.
   - Top-level tree: `gh api repos/<org>/<repo>/contents` and summarize names/types; for deeper files/trees, use `/git/trees/<branch>?recursive=1`.
4. Windows quirk: `gh repo view ... --json language` returns **Unknown JSON field**; use `primaryLanguage.name` instead.
5. For top-size files proof: `gh api repos/<org>/<repo>/git/trees/<defaultBranch>?recursive=1 --jq '.tree'`, fall back to raw response if the `--jq` path errors, then filter blobs and sort by `size`.
6. For doc deep-reads and raw content: **do not use `GET /repos/<org>/<repo>/contents/<path>` for existence checks**—it can return `404` for files that exist in git. Use `GET /git/trees/<branch>?recursive=1` for path+size+sha, then `GET /git/blobs/<sha>` for raw text. The tree API is authoritative for path existence; the blob API is authoritative for content; neither depends on the `contents` service layer. See `references/github-api-trees-not-contents.md` for the exact quirk, reproduction, and branch fallback order.
7. Branch fallback order when resolving trees: try `master` first, then `main`, then `develop`. Some `ZQM-Computing` repos (`hermes-config`, `zqm-localhost-findings`, `zqm-auth`, `comfyui-setup`) have files on `master` that are absent from `main`, even if GitHub reports `main` as the default branch. Prefer whichever branch returns a non-empty tree for the paths under test.</value>
6. For doc deep-reads: request specific paths with `gh api repos/<org>/<repo>/contents/<path>`, base64-decode, and preview the first N lines. If the path is a directory, skip or list only.
7. For local-clone presence: scan common roots (`~/Documents`, `~/repos`, `~/github`) plus any known project roots from memory; for each matching `.git` directory, collect branch, HEAD commit short SHA, and remote URL.
8. After inventory, summarize risk flags from repo content: committed runtime artifacts (`state.db`, `node_modules`, `cache/`, `pastes/`), credentials/tokens/hardcoded identifiers, LAN-sensitive operational notes, and in-repo fetch/elevation scripts that retrieve remote code.
9. For recent-commit context across repos, preferred path is `gh api repos/<org>/<repo>/commits?per_page=5` raw-jq fallback to parsing the full response array; if both fail, mark commits unreadable and move on.
10. If a repo’s README content matches upstream project READMEs verbatim (e.g., naabu, ComfyUI, gemini-desktop upstream), classify it as a snapshot/fork rather than original authored content.

## Private repo commit audit

Before declaring a systems-review clean, verify that every private/local code repository under this host has its current code changes committed. Use this procedure:

1. Enumerate candidate roots with bounded scan: check known ZQM code roots first (`AppData/Local/hermes`, `OneDrive/Desktop/zqm-node-01-indexer`, `Documents/comfy/ComfyUI`, `Documents/bounty-tools`, `Documents/bounty-tools-naabu`, `.zqm-auth`, `.zqm-node-01-indexer`, `.hermes`, `wiki`, plus any workspace roots documented in memory).
2. For each root with a `.git` directory, run `git status -s`. If output is empty, it is clean.
3. If `git -C <path>` reports the path does not exist, retry once with `git --work-tree=<path> --git-dir=<path>/.git status --short --branch`. If that succeeds, continue; if it still fails, mark the repo as UNREACHABLE and move on.
4. If dirty, inspect `git diff --name-only` and stage only intentional code/config changes. Skip runtime artifacts, caches, secrets, `.venv`, `__pycache__`, OS junk, and OneDrive sync debris.
5. If the sweep discovers an unprompted repo outside the known roots, pause and ask whether to commit it. Do not run `git init` / `add` / `commit` on unknown repos without explicit instruction.
6. Before bulk-committing a repo with many untracked runtime files, update `.gitignore` first, then verify with `git check-ignore -v <sample paths>`. Only after verification, propose `git rm --cached` for paths that are already tracked in the index but should now be ignored. **Do not run `git rm --cached` without explicit user approval; it mutates the index even though local files stay on disk.**
7. When proposing `.gitignore` additions on Windows, cover these common pollution classes:
   - bundled runtimes/embeds: `node/package/`, `node/_node_zip/`
   - runtime scratch: `Temp/`, `pastes/`, `cache/terminal/`
   - generated output: `cron/output/`
   - crash/backup artifacts: `auth.json.corrupt`, `config.yaml.mcp-backup-*`, `config.yaml.pre-*`, `config.yaml.corrupt*.bak`
   - unit-test scratch: `.pytest-cache/`, `.restart_last_processed.json`, `.restart_notify.json`
   - subtree exclusions for submodules/worktrees that belong in a different repo, e.g. `hermes-agent/`
8. Commit with a scoped message, e.g. `indexer/dashboard: <summary>`.
9. Do not bulk-commit prebuilt binaries, zip archives, JRE bundles, platform-tools, or runtime tooling.
10. Record the post-commit status in the systems review report under `Commit audit: <clean|N commits>`.
11. Do not bulk-commit upstream forks or vendor clones unless the user explicitly asks.

## Report Template
## Full systems diagnostics sweep
When the user asks for "full systems diagnostics" (or "diagnostics on X") on a
ZQM repo, run ONE consolidated live sweep covering every subsystem, then write a
`SYSTEMS_DIAGNOSTICS.md` to disk. The reusable 10-section template lives in
`references/full-systems-diagnostics-sweep.md`. For the stability/health sub-query
(the "diagnostics and improve stability" verb) use `references/stability-diagnostic.md`.
For classifying a "genesis/recruitment/beacon" module as benign lore vs C2/exfil, use
`references/genesis-lore-classification.md`. For tamper-evident chaining of the
ledger itself (the "hash claims" verb) see `references/claim-chain-verification.md`. Key discipline: every section must
show ACTUAL EMITTED OUTPUT, and any subsystem that previously "passed" only
because of a hardcoded constant or disconnected data source must be flagged with the
real (often failing or empty) behavior. This is the same honesty rule as the
mixed-code+narrative investigation, applied per-subsystem.
- Section set: [1] env+deps, [2] module imports, [3] hypothesis/engine all-N
  live, [4] spine/event write, [5] live API (auth/CORS/host via TestClient =
  same path as uvicorn), [6] DB persistence (correct statuses, not UNKNOWN/FAIL),
  [7] billing (reads real source, non-empty invoice), [8] rotation/cache
  service, [9] repo hygiene (fiction quarantined vs engineering root), [10] demo
  scripts with phantom deps (e.g. cvg_hive ImportError).

## "Bots & automations" audit (class: enumerate every autonomous execution surface)
When the user asks "what bots/automations run on this node," use the dedicated method in
`references/windows-bots-automations-audit.md`. It covers all 7 surfaces (scheduled tasks,
Startup `.lnk`, Run/RunOnce keys, running server/bot processes, listening ports, container
hosts, Hermes cron) plus two non-obvious traps: (1) `pythonw.exe` is NOT matched by a
`python` name regex — query it separately; (2) resolve Startup `.lnk` targets with
`WScript.Shell.CreateShortcut` + `Test-Path` to catch DEAD autoruns (shortcut exists but
target script is missing). Reconcile "registered" vs "running" and report both states.

## Report Template
```
=== SYSTEMS REVIEW ===
MCP tools: <N>
Skills installed: <N>
Services: <list with PID/port/status>
Commit audit: <clean | N commits across M repos>
Gym review: <N> skills reviewed, <M> benchmark ok
Deep checks: <list with pass/fail>
Blockers: <none | list>
Overall: PASS | FAIL
```

## Hermes runtime files blocking git sync

`AppData\Local\hermes` contains live runtime files owned by Hermes processes: `SOUL.md`, `cron/.jobs.lock`, `cron/.tick.lock`, `kanban/.dispatcher.lock`. When a rebase/merge/reset wants to touch these paths, Git will error with `The following untracked working tree files would be overwritten by merge` or `could not move back to ...`.

Do NOT bulk-delete these. Recovery procedure:
1. Quarantine all non-lock blocking files to `AppData\Local\Temp\hermes-sync-quarantine-<timestamp>` using copy-then-remove; do not move lock files Hermes holds open.
2. Stop local Hermes processes briefly (`tasklist /FI "PID eq <pid>"` to verify, then `taskkill /PID <pid> /F` if approved).
3. Retry `git rebase --abort` (or `git merge --abort` / `git reset --hard` as appropriate).
4. Verify with `git status -sb` that the repo is back to a clean state.
5. Restart Hermes.
6. Re-run the sync/push sequence from a clean state.

If a lock file is held open by Hermes and cannot be moved/removed, do not force-delete it. After quarantine + Hermes stop, if `git rebase --abort` still refuses, capture the exact paths and report the blocker instead of looping on identical commands.

## Private repo library inspection before activation

Before starting or debugging an unfamiliar private repo—especially council/service code on this host:

1. Read the repo manifest first: `README.md`, entrypoints (`service.py`, `main.py`, `app.py`), config (`config.py`, `config.json`), state files (`board*.json`), and `requirements.txt`.
2. Identify the framework, ports, backend dependencies, and auth patterns before attempting to launch.
3. Note any board/state files that may contain stale topics or credentials from prior sessions.
4. Only after architecture is understood, proceed to dependency install + launch.

## Remote existence guard before `git remote set-url`

Before pointing a local repo at a remote that "should" exist:
1. Verify repo existence with `gh repo view <org>/<repo>` or `curl https://api.github.com/repos/<org>/<repo>`.
2. If API returns 404, do not set the remote; report the missing repo and ask whether to create it.
3. Only set `origin` after confirming the target exists.

## Branch mismatch recovery for private repos

Symptom: `git push origin master` returns `! [rejected] master -> master (fetch first)`, even though you own the repo.
Root cause: remote has new commits you do not have locally.
Fix:
1. `git fetch origin`
2. `git checkout -b main origin/master` or `git branch -f main origin/main` from a detached `HEAD`
3. If detached after conflict resolution: `git checkout main`, `git add -A`, `git commit --amend --no-edit`
4. `git push --force-with-lease origin main`

Only force-push to repos you own. Never force-push to shared forks.

## config.json conflict-marker cleanup

If `git status` or `git diff` shows merge conflict markers inside `config.json`, do not try to `git add` the conflicted file and continue. The machine-readable config will be broken. Fix path:
1. Rewrite a canonical JSON config with required keys/values.
2. Run a bounded JSON parse verification.
3. Then commit/push from a clean state.

## Ollama shard/context optimization on limited-RAM hosts
- Before deleting a too-large Ollama model, attempt cheaper optimizations first: GPU offload and context reduction.
- Check VRAM availability: `nvidia-smi --query-gpu=memory.free`.
- Inspect `llama-server` command line for `--gpu-layers` / `--no-mmap` to confirm CPU-only mode.
- Preferred env vars on this host before model deletion: `OLLAMA_NUM_GPU=1`, `OLLAMA_CONTEXT_LENGTH=8192`, `OLLAMA_NUM_PARALLEL=1`.
- Restart Ollama after env-var changes and re-probe `/api/generate` + `/council/last` before deciding a model must be removed.

## Windows PowerShell code-signing workflow for local artifacts

When the user asks to sign or re-sign local scripts/artifacts as `Alex Zelenski, GISP <zqmcomputing@gmail.com>`:

1. Identify the signing target(s) and existing certificate thumbprint: `D9C7C50808FD1FEB074D635DCC71111FB712F733`.
2. Sign with PowerShell using SHA256: `Set-AuthenticodeSignature -FilePath <target> -Certificate (Get-ChildItem Cert:\\CurrentUser\\My | Where-Object { $_.Thumbprint -eq 'D9C7C50808FD1FEB074D635DCC71111FB712F733' }) -HashAlgorithm SHA256`.
3. Verify immediately with `Get-AuthenticodeSignature` and assert `Status -eq 'Valid'` and `SignerCertificate.Thumbprint` match.
4. Report signing as complete only after verification returns the expected subject and thumbprint.
5. Do not re-sign files that already verify correctly.

If the certificate is missing or expired, stop and report the exact blocker instead of retrying silently.

Preferred code-signing verification probe: `scripts/verify-codesign.ps1` under this skill. Use it instead of hand-typing inline `Get-AuthenticodeSignature` checks.

For verification-only requests, reuse the same ad-hoc probe pattern documented in this skill; do not create duplicate long-lived “signed” wrappers unless the user explicitly asks.

## Signed-script edit-verify-resign loop

Any edit to a signed `.ps1` invalidates its Authenticode signature. Do not claim a signed artifact is still signed after changing its bytes. Required sequence:

1. Edit file.
2. Re-sign with the workflow above.
3. Verify with an ad-hoc probe; pass before reporting.
4. Clean up the probe file.
5. Only then report `Signed and verified` or ad-hoc verification success.

Repeated user edits require repeated re-sign+re-verify cycles. Skipping re-sign between edit and verification is a stale-signature error.

## Windows temp verification script hygiene

Ad-hoc verification scripts must be `tempfile.mkstemp(prefix='hermes-verify-', suffix='.ps1', dir=...)` written, executed, then removed deterministically. Avoid static filenames like `hermes-verify-toroidal.ps1`: they can leave orphan files in `C:\Users\zqmco\AppData\Local\Temp` across retries. After a successful verification, run a bounded glob cleanup for `hermes-verify-*.ps1` and report how many were removed. If cleanup fails, report the exact path and OS error rather than silently leaving artifacts.

## Hermes terminal bootstrap failure on Windows

On this workstation, the Hermes terminal backend prepends `C:\Users\zqmco\AppData\Local\hermes\git\bin` to PATH before each shell session. That directory contains only `bash.exe` plus an empty `usr/bin`, and does not expose `git`, `python`, `node`, or `wmic`.

Symptom: every `terminal()` call exits before the requested command runs, with `Top-level not found: C:\Users\zqmco\AppData\Local\hermes\git\bin`.

Workaround/repair:
- Use `execute_code` with Python stdlib to read files and inspect configs; use it with `subprocess.run(['cmd.exe','/c', ...])` for shell commands.
- If the user approves, install Git for Windows or otherwise populate `...\hermes\git\bin` with a real POSIX `sh` and `git.exe`; rerun systems sweeps only after `terminal()` starts succeeding.
- Do not retry the same `terminal()` invocation after a fresh failure snapshot; switch strategy to `execute_code` + direct cmd.exe/python invocations instead.

## Windows subprocess/here-doc quoting pitfalls
- Avoid writing raw Windows-style here-doc strings through bash into PowerShell: git-bash line-ending conversion can inject `\r` and turn quoted string literals into unterminated PowerShell strings.
- When invoking PowerShell from `subprocess.run([...], text=True, ...)`, do not use Python triple-quoted strings with backslash-escape sequences directly; pass the whole PowerShell command as a single Python raw string or as separate argv tokens, and avoid embedding `\\\\U`/`\\\\u` sequences inside it. Use `-NoProfile -Command` plus a short script block rather than multi-line Python heredocs.
- When using `terminal` on Windows, prefer POSIX-compatible shell syntax via git-bash/bash, not PowerShell cmdlets. Do not reference PowerShell builtins (`Get-ChildItem`, `$env:FOO`, `Select-String`) in `terminal` invocations; use `ls`, `$FOO`, `grep`, `find`, etc. instead.

## JSON config verification pattern on Windows

Before declaring a JSON edit verified:
1. Read the file with `open(path,'r',encoding='utf-8')`.
2. Parse with `json.load()` or `json.loads()` on the raw text.
3. Assert expected keys/paths/types in-process.
4. Optionally write a small ad-hoc probe under `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*.py` and run it with system Python.

Do not declare verification success based solely on a linter or write_file returning "status":"ok"; that validates syntax, not JSON parseability.

## Windows JSON escape/backslash pitfall for filesystem paths

When writing JSON on Windows, paths like `C:\\Users\\zqmco` must be stored with literal `\\\\` in the file text. If the in-memory string is created from nested backslashes, JSON parsers will reject it because they see `\\U` as an invalid escape. Preferred fixes:
- Use Python raw strings or explicit double-backslash forms before serializing.
- Re-parse with `json.loads()` immediately after writing; if parse fails, inspect raw text for single-backslash escaping.

## Named-system investigation protocol
1. Run a bounded scan for the exact term across active roots, paste exports, and state stores.
2. If a term appears only in old paste exports or redacted path strings, classify as **historical artifact, not live system**.
3. If it appears in code/config/services, classify as **present** and enumerate routes/processes.
4. If absent locally, probe common local ports and known remote endpoints; if still absent, report **not present on this node** with evidence paths.
5. Do not invent wrappers/bridges for absent systems; report the absence and stop.

Council/SAC distinction on this host:
- Port `9000` = Skill Automation Center, not a council server.
- Council-mounted routes return **404**; do not retry identical absent routes.
- A request to “utilize the council” is blocked at transport/auth first whenever all council routes 404.

## Mixed code + narrative repo investigation (ZQM-Quantum-Automation pattern)

Some ZQM repos bundle real, runnable Python with pseudoscientific worldbuilding
markdown and present both as if equally real. Investigating one demands a
separation discipline so a client/auditor is never misled into thinking
fiction is engineering.

Reproducible procedure used on `C:\Users\zqmco\ZQM-Quantum-Automation` (see
`references/zqm-quantum-automation-investigation.md` for the full findings):

1. **Separate the two layers first.** Code (`*.py`, `*.db`, `*.json`, `*.log`)
   is evidence; narrative markdown (`*_realm.md`, `omnimap.md`,
   `progress_map.md`, `dark_realm.md`) is speculative fiction unless backed by
   code or measured data. State this split explicitly in the report. Do not let
   claims like "first light activated" or "network is self-aware" pass as fact
   without a code/data citation.
2. **Verify pass/fail claims by execution, not by reading return values.**
   - Reproduce any hardcoded expected hashes (H1 SHA3-256) in a throwaway
     script to confirm it actually checks something.
   - For endpoints that persist a verdict, inspect the DB row after a request:
     they often log the wrong key (e.g. `result.get("pass")` is `None` because
     the envelope uses `"promotion"`, so H21–H30 always record "FAIL"; H8–H12
     record "UNKNOWN" because the envelope has no `"status"` key).
3. **Trace the data-source wiring end-to-end.** A service can emit usage events
   to SQLite while the billing service reads a JSONL file the API never writes
   (`usage_events.jsonl`) → billing silently produces empty invoices. Grep for
   the written path vs the read path.
4. **Flag the auth/CORS defaults.** `allow_origins=["*"]` + `allow_credentials=True`
   is an invalid/insecure combo; `allowed_hosts=["*"]` is a no-op; a single
   hardcoded API key (`example-client`/`example-key-12345`) is a default
   credential. Report these as MEDIUM even on a mock.
5. **Catch the cross-user path drift.** Code authored by Alex Zelenski hardcodes
   `C:\Users\AlexZelenski\Desktop\...` (spine_local, __pycache__) but the host
   user is `zqmco`; those dirs don't exist here and the spine writer will hit a
   PermissionError after mkdir fails. Also note package/dir name mismatches
   (`quantum_automation/` vs the real `ZQM-Quantum-Automation/`).
6. **Confirm the engine is real or mocked.** With few exceptions (H1, H31–H35
   do real math) these "hypotheses" hardcode `pass=True` or check a constant
   against a threshold and report PASS. A `/latest-results` endpoint that
   hardcodes all 31 as "PASS"/"PROMOTABLE" is a fake real-time feed.
7. **Hygiene anomalies.** 0-byte `*.pyc` files (stale_cache*.pyc) are not
   written by normal Python — flag and remove. Orphaned modules (H31–H35
   defined but unreachable via the API's `/test/{id}` which only accepts H1–H30)
   indicate dead surface.
8. **requirements.txt completeness.** It can omit runtime deps the code imports
   (fastapi/uvicorn) and list deps never imported (liboqs-python/pqcrypto when
   PQC is a sha3 stub) → `pip install -r requirements.txt` won't yield a working
   app.
9. **Deliverable.** Always write the full findings to an on-disk markdown report
   (e.g. `C:\Users\zqmco\ZQM-Quantum-Automation-INVESTIGATION.md`) and summarize
   in plain terminal text. Severity-rank: HIGH = misleads users (fake PASS,
   disconnected billing, wrong status keys); MEDIUM = security defaults + ops
   drift; LOW = anomalies + orphaned modules.

`.zqm-auth` subsystem inventory:
- Treat `.zqm-auth` as a separate Hermes-like subtree during full-system audits.
- Capture its own instances, skills, dogfood artifacts, wiki, and cron state rather than folding it into the main Hermes tree.

Live dogfood artifact confirmed healthy even while terminal is degraded:
- `dogfood-output/report.md` shows 111 skills benchmark=ok, 0 failures, last run 2026-07-06.
- Gateway lock/pid present: pid `18224`, argv `hermes_cli/main.py gateway run`.
- Dashboard config: `:9119` bound to `127.0.0.1`, auth username `zqmco`, password scrypt hash; live `streaming.enabled=false`.
- `auth.json.corrupt` exists alongside `auth.json`; if auth errors appear, inspect both rather than only the live file.

## Indexer auth root-cause pattern
Symptom: `/api/auth/status` returns `authenticated: false`, `user: null`, `zqm_user: null`, even though a token file exists and `/api/user/paths` resolves to the expected user.
Root-cause checks in order:
1. Confirm token file exists at `~/.zqm-auth/token` and contains the expected prefix.
2. Confirm `zqm_auth` is importable from the running service’s Python path/venv.
3. If `zqm_auth` import fails, the service usually sets `zqm_auth = None` and auth endpoints will report unauthenticated regardless of token presence.
Fix path: install/restore the `zqm_auth` module or restore the caller’s import path so the token is actually parsed/validated.

## Indexer profile-scoping staleness pattern
Symptom: profile-scoping helpers exist in `indexer.py`, but `/api/config` still returns unscoped `root_paths` and `/api/search` returns cross-profile noise.
Root-cause: `build_index()` writes whatever `root_paths` it received. If `_resolve_root_path()` exists but is not used by `scan_directory()`/`build_index()`, the persisted config/index remains unscoped until a rebuild runs with resolved roots.
Fix path: update `scan_directory()`/`build_index()` to resolve roots before scanning/writing config, then rebuild the index.

## Pitfalls

- Always use `--auto` for gym commands; interactive mode hangs CI/cron.
- On this Windows host, MSYS/bash path translation can make `git -C <path>` spuriously fail on certain hidden/config repos even though the work tree exists. When that happens, fall back to `git --work-tree=<path> --git-dir=<path>/.git status --short --branch` and `rev-parse HEAD`. Do not re-init or delete a repo simply because the first command failed.
- In a change-tracker sweep, new hidden/config repos may appear mid-run. If you discover an unprompted repo beyond the known set, pause and ask whether it should be committed, rather than silently running `git init`/`add`/`commit` on it.
- Bulk initial commits are fine only for code/config artifacts. Never bulk-commit prebuilt binaries, zip archives, JRE bundles, platform-tools, or runtime artifacts; use `.gitignore` first, then stage docs/manifests only.
- On Windows, some shells rewrite `&`; use `cmd.exe /c python` or bash.
- If `run_tests.sh` is missing for a skill, create it before declaring verification done.
- Gateway/api_server enablement is opt-in on `API_SERVER_ENABLED=true`/`API_SERVER_KEY` or platform config; `streaming.enabled=true` alone does not bind the HTTP server.
- When launching `gateway.run` from Git Bash, prefer explicit venv Python and inspect full logs; timeout checks can be unreliable if the process stays resident or exits immediately.
- If the host has multiple Python runtimes, prefer the project venv interpreter for imports/lifecycle tests, then use the same interpreter for the actual background launch.
- `hermes gateway run --replace` and live reload can surface MCP startup failures instead of binding the API server; validate MCP config first.
- On this Windows host, `python` often resolves to a `uv`-managed Python rather than the system/bundled interpreter. Before assuming stdlib/PyPI behavior, verify with `python --version`, `where python`, and `python -c "import sys; print(sys.executable)"`. Do not assume `subprocess.run(['python', ...])` matches the project venv or bundled runtime.
- Do not claim gateway/SSE pass on command success alone; require actual port-open evidence.
- `wmic` is not available on this Windows 10 host; use PowerShell `Get-CimInstance` for process inspection.
- Do not use shell background operators (`nohup`, `&`, `disown`) in foreground `terminal()` calls; use `background=true` instead.
- Live SQLite stores can drift between build and verification because cron/messaging writes continue. Do not assert exact future DB equality for a snapshot artifact built earlier. Use build-time anchors stored in the artifact itself, or rebuild under quiet store conditions.
- A validator should accept a snapshot as valid when build-time anchors match the DB at build time, even if later DB reads disagree.

## Delegated / council / subagent output is SECONDHAND — re-verify before presenting
When you dispatch subagents (delegate_task "council") or consume another agent's (e.g.
Cline's) report, its claims are NOT ground truth until you reproduce them live. This
session a Cline inventory was FALSE on 3 material points: it declared Node-2
(192.168.1.21) a "DNS alias" of Node-4 (192.168.1.215) (false — disjoint model lists =
distinct hosts), undercounted Node-4 models (43 vs real 45), and understated its size
(~325 GB vs real 451.6 GB). Discipline:
- For any claim with a LIVE check available (port open, model list, version, running
  models, exposure), run that check yourself in the same turn and present REAL output.
- Hold subagent numbers against your own live pull; flag contradictions explicitly
  (PROVEN / NOT PROVEN / FALSE) rather than quietly adopting them.
- Never tell the user a finding is "verified" if only a subagent asserted it.

## Config parse error protocol

When Hermes emits:
```
Failed to parse config.yaml: while parsing a quoted scalar ...
Falling back to default config — every user override ... is being IGNORED.
```
1. Verify the live config path with `python -c \"from hermes_cli.config import get_config_path; print(get_config_path())\"` from the Hermes venv.
2. Validate YAML with `yaml.safe_load(open('config.yaml','r',encoding='utf-8'))` from the same interpreter. If it parses cleanly, the warning may be stale or from a sibling `.bak` file.
3. Inspect sibling files: `config.yaml.bak`, `config.yaml.mcp-backup-*`, `config.yaml.pre-*`, `config.yaml.corrupt.*.bak`. A parse failure on these does not affect the live config, but indicates past write-time corruption.
4. If the live `config.yaml` truly fails to parse, repair the YAML and restart Hermes. Do not delete the file; Hermes snapshots corrupt configs automatically.

## Git index cleanup after `.gitignore` updates

When a repo has many untracked runtime files because they were tracked before `.gitignore`:
- `.gitignore` alone does not retroactively remove paths from the git index.
- After verifying ignore rules with `git check-ignore -v <sample paths>`, propose `git rm --cached` for tracked paths that should now be ignored.
- Always obtain explicit user approval before running `git rm --cached`; it mutates the index even though local files remain on disk.
- If the user declines, leave `.gitignore` correct and report the repo as dirty with the reason indexed legacy artifacts remain.

## Remote wiring sequence (private repos)

When creating GitHub repos and pushing local code:
1. `gh repo create <org>/<repo> --private` first, then set remote. If `gh` creation fails or hangs, delete and retry once.
2. Set remote with `git remote set-url origin https://github.com/<org>/<repo>.git`. If origin already exists, do not blindly re-add; inspect `git remote -v` and reuse.
3. Handle branch name mismatches explicitly: `git branch -M <newname>` before first push.
4. If push fails with `fetch first` and remote contains upstream commits you own:
   - `git pull origin <branch> --rebase`
   - If rebase hits conflict: resolve file, `git add <resolved>`, set `GIT_EDITOR=true git rebase --continue`
   - Then `git push -u origin <local_branch>:<remote_branch>`
5. If rebase rewrites history and force is required: `git push --force-with-lease` only for repos you own; never force-push to shared forks.
6. After success: confirm with `git status -sb` showing `local_branch...origin/remote_branch`.

## Detached-HEAD recovery for private repos

Symptom: after conflict resolution during rebase, `git status --short --branch` shows `## HEAD (no branch)` and dirty files are present.
Fix path:
1. `git checkout main` or `git checkout -b main <upstream_branch>` to recover a named branch.
2. `git add -A` and `git commit --amend --no-edit` to pack the dirty state back onto the branch tip.
3. `git push --force-with-lease origin main` only for repos you own.

## Remote-wiring fallback for dirty push targets

Symptom: `git push origin master` returns `! [rejected] master -> master (fetch first)`, even though you own the repo, and the local branch is already ahead.
Fix:
1. `git remote -v` first; if origin is missing or points at a different repo than expected, set it explicitly before retrying.
2. `git fetch origin` then reconcile local branch with remote refs (`main` vs `master` naming).
3. Pack dirty work into a new tip and force-with-lease only after inspecting the remote diff.

## Hermes runtime files blocking git sync

`AppData\Local\hermes` contains live runtime files owned by Hermes processes: `SOUL.md`, `cron/.jobs.lock`, `cron/.tick.lock`, `kanban/.dispatcher.lock`. When a rebase/merge/reset wants to touch these paths, Git will error with `The following untracked working tree files would be overwritten by merge` or `could not move back to ...`.

Do NOT bulk-delete these. Recovery procedure:
1. Quarantine all non-lock blocking files to `AppData\Local\Temp\hermes-sync-quarantine-<timestamp>` using copy-then-remove; do not move lock files Hermes holds open.
2. Stop local Hermes processes briefly (`tasklist /FI "PID eq <pid>"` to verify, then `taskkill /PID <pid> /F` if approved).
3. Retry `git rebase --abort` (or `git merge --abort` / `git reset --hard` as appropriate).
4. Verify with `git status -sb` that the repo is back to a clean state.
5. Restart Hermes.
6. Re-run the sync/push sequence from a clean state.

If a lock file is held open by Hermes and cannot be moved/removed, do not force-delete it. After quarantine + Hermes stop, if `git rebase --abort` still refuses, capture the exact paths and report the blocker instead of looping on identical commands.

## User authorization shorthand

Replies like `yes please`, `all of the above`, or `proceed` authorize executing the last proposed holistic vector without re-asking. Apply this only to non-destructive holistic workflows; destructive or history-rewriting actions still require explicit confirmation.

## Repo hygiene workflow

Use this when the user asks to make private repos fully populated, clean commit histories, or learn proper software management.

### Dirty-repo decision tree
1. Read the working tree first: `git status -sb` and `git diff --name-only`.
2. Separate intentional changes from runtime/cache/backup pollution.
3. If `.gitignore` is missing ignore rules for observed pollution, update `.gitignore` first, then verify with `git check-ignore -v <sample paths>`.
4. Stage only intentional code/config changes. Leave runtime artifacts un staged unless the user explicitly asks for bulk cleanup.
5. Commit with scoped conventional commits: `<type>(<scope>): <summary>`.
6. If a repo is already clean but has staged/unstaged changes in ignored paths, prefer `.gitignore` updates over committing noise.

### Commit taxonomy
- `feat(...)`: new capability, skill, integration, or workflow.
- `fix(...)`: bug fix with symptom and code path.
- `chore(...)`: housekeeping, snapshots, config maintenance, `.gitignore` updates.
- `refactor(...)`: structural cleanup without behavior change.
- `test(...)`: test additions/corrections.
- `docs(...)`: documentation only.
- `revert(...)`: explicit revert with original reference.

### Branch hygiene
- Standardize default branches only after inspecting remotes and local refs.
- If renaming, do it deliberately: `git branch -m <old> <new>` and `git branch -u origin/<new> <new>`.
- Avoid blind bulk renames across unrelated repos; confirm per repo.

### Remote workflow on this host
- Do not assume ownership of unknown remotes. Inspect `git remote -v` before setting push targets.
- For private ZQM work, prefer `ZQM-Computing/<repo>`; for upstream projects, keep upstream tracking and add a private remote if needed.
- Push after commit; do not leave local-only commits unpushed without an explicit reason.

### Backup / corrupt config handling
- `config.yaml.bak`, `config.yaml.mcp-backup-*`, `config.yaml.pre-*`, and `config.yaml.corrupt.*.bak` are lifecycle artifacts, not live config.
- A YAML parse error in these files does not mean live `config.yaml` is broken.
- When Hermes warns about config parse failure: verify live path with `get_config_path()`, validate live `config.yaml` with `yaml.safe_load`, and inspect sibling backup files separately. Do not delete user config files; Hermes snapshots corrupt configs automatically.

## `.quarantined/` cache/runtime inventory protocol
`.quarantined/` is session evidence, not garbage:
- Before any delete/move/cleanup, inspect contents and provenance.
- Treat archived `board*.json`, `deliberation.log`, and similar as prior runtime state useful for debugging or audit.
- In git, `.quarantined/` is often untracked and unignored; do not bulk-remove.
- If `.gitignore` already excludes runtime files, propose adding `.quarantined/` only after inventory; otherwise leave it as-is and report its contents separately.
- User preference here: do not delete until contents are inventoried.

## Windows service restart and port-conflict recovery
Before relaunching a resident Python/FastAPI service:
1. If the previous bind attempt failed with `only one usage of each socket address`, do not start a second instance.
2. Determine actual owner of the listening port; prefer `netstat -ano | grep LISTENING` on the target port or PowerShell `Get-NetTCPConnection -LocalPort <port>` rather than trusting shell wrapper exit lines.
3. If the real server is still running, reload/kill only if explicitly approved; otherwise wait and reuse the running instance.
4. If approved to restart, terminate the holder PID, then relaunch from the project directory with the project venv interpreter.
5. After launch, verify readiness with a direct port probe plus a representative API path before running health endpoints only.

## Fleet service security & launch pitfalls (ZBit/LiteLLM/Ollama/Redis)
See `references/fleet-service-security-launch-pitfalls.md` for full detail. Quick hits:
- **Redis Windows v3.0.504** rejects live `CONFIG SET bind`/`protected-mode`
  (`-ERR Unsupported CONFIG parameter`); only `requirepass` applies live.
  To close a LAN RCE fast: remote `CONFIG SET requirepass <48hex>` (all
  cmds now NOAUTH from LAN). Loopback-bind + firewall need the conf-file + restart.
- **litellm.exe is a PE launcher** — run DIRECTLY (`venv\Scripts\litellm.exe
  --config ...`), NOT via `python.exe litellm.exe` (No module named litellm)
  nor `python -m litellm` (no __main__). Launch persistently with
  `terminal(background=true)` from `ZBit_api`; avoid `start cmd /c` quoting mangle.
- **litellm zbit-heavy hang**: add `timeout: 45` + `model_group_fallback:
  [zbit-fast]` to reroute instead of 120s hard-fail.
- **Trace a service before locking it**: prove NO legitimate consumer (netstat
  pid -> tasklist -> grep fleet configs for host:port). Lock only if orphaned.
- **Coined-verb handling**: decode the verb, FLAG the assumption, then act.
  "approve with branches and forks" on non-git artifacts first needs a repo
  HOME identified (deep-look the 49 repos; `zqm-localhost-findings` is the
  clean purpose-named target). Never `git init`/`add .` blindly.
- **Label precision**: if the user challenges an overstated label ("why is that a
  mistake?"), retract to the defensible word (unintended-default, not
  accidental/mistake) and keep the risk-contrast that matters. Blame != fix.

## Windows memory-pressure preflight before large-model runs
On small-form-factor Windows hosts, resident services plus large Ollama models can exhaust RAM/VRAM:
- Physical memory near exhaustion plus virtual memory near ceiling predicts generation stalls even when `/api/tags` reports models present.
- Before declaring council/service healthy, inspect `nvidia-smi` and physical memory; if free RAM is very low, default to smaller models or postpone long council runs.
- Do not infer backend failure from service routes alone; direct `/api/generate` against the candidate model is the deciding evidence.
