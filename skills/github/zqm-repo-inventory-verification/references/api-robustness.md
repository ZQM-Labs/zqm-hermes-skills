# GitHub API Robustness for ZQM Repo Verification

## What to use

| Goal | API endpoint | Why |
|------|--------------|-----|
| Existence + size + sha | `GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1` | Authoritative source of truth for path existence |
| Raw file content | `GET /repos/{owner}/{repo}/git/blobs/{sha}` | No `contents/{path}` 404 edge cases |
| Paged tree fetches | `GET /repos/{owner}/{repo}/git/trees/{tree_sha}?recursive=1` | Use returned `truncated` flag; if true pagination is needed |

## What NOT to use

- `GET /repos/{owner}/{repo}/contents/{path}` can return `404` for files that exist in git.
- Rate-limit headers (`X-RateLimit-Remaining`) can remain healthy during these false negatives.
- `gh repo view --json defaultBranchRef` can report `main` while files of interest live on `master`.

## Robust branch fallback

Use the fixed order `master` → `main` → `develop` for ZQM-Computing repos.

**Do not** use `gh repo view --json defaultBranchRef.name` and then fall back from that branch. GitHub's reported default branch can be wrong for this account: it reported `main` for `hermes-config`, but files of interest (`check_npcap.ps1`, `elevated_install.ps1`, `instances/zqmco/state/state.db`) only exist on `master`. Always try `master` first regardless of what `gh repo view` says.

Observed divergence (2026-07-09):
- `hermes-config`: reports `main` as default; `check_npcap.ps1` and `elevated_install.ps1` only on `master` (12470 paths vs 3688 on `main`).
- `zqm-localhost-findings`: same pattern — files on `master` absent from `main`.
- `zqm-auth`, `comfyui-setup`: same divergence observed.

## Verification pattern

# 1. Pre-fetch trees for all repos with fallback chain
for repo in repos:
    for branch in ['master', 'main', 'develop']:
        data = gh_api(`/repos/ZQM-Computing/{repo}/git/trees/{branch}?recursive=1`)
        if data and 'tree' in data and data['tree']:
            tree_cache[repo] = {t['path']: t for t in data['tree']}
            break

# 2. Existence checks use tree_cache[repo]
if 'check_npcap.ps1' in tree_cache.get('hermes-config', {}):
    # PASS

# 3. Content checks use blob API with SHA from tree
sha = tree_cache[repo][path]['sha']
blob = gh_api(`/repos/ZQM-Computing/{repo}/git/blobs/{sha}`)
content = base64.b64decode(blob['content'])

## Result

13/13 deep checks pass across all 18 ZQM-Computing repos when using tree+blob with master-first fallback.

## GOTCHA — `recursive=0` / shallow tree is NOT a safe cap

`GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=0` returns a TRUTHY
dict with `'tree'` present, but GitHub still returns the FULL recursive tree
(entire node_modules, lsp/, instances/, etc.). A naive `if data and 'tree' in data`
check passes and you get a ~1MB dump that blows the tool context.

Two safe shapes:
- Top-level listing ONLY: use `GET /repos/{owner}/{repo}/contents/` → array of
  `{path, type}` (discovery view, not existence-truth, but fine for a map). Cap with `[:40]`.
- Full path-existence + content: use `git/trees/{branch}?recursive=1` and rely on
  the `truncated` flag for pagination.
- NEVER do a recursive tree fetch for a repo you merely want a top-level map of
  (e.g. `hermes-config` has 12k paths — one tree fetch = context overflow).

Verified 2026-07-12: a bulk inventory of 37 repos fetched
`git/trees/{branch}?recursive=0` for each and truncated mid-output on the
largest repo; switching the map pass to `contents/` + a 40-entry cap fixed it.

## WORKFLOW — "enhance MY workstation/fleet" repo applicability filter

When the user asks what repos they can use to improve THIS node (Node-1 /
local workstation), do NOT just dump all repos. Apply a 3-tier filter against
live `gh api` language stats + top-level tree (NOT descriptions):

- TIER 1 HIGH: drop-in capability for the local box (local RAG/MCP servers, the
  node's own indexer service, Ollama routers). Pull read-only into a staging dir
  first — never clone wholesale.
- TIER 2 MEDIUM: hardening / config parity / skill-currency (attestation
  toolkits, shield helpers, dotfiles, upstream skills repos).
- TIER 3 LOW/situational: skeletons, policy docs, per-GPU tooling.
- NOT APPLICABLE: framework source, red-team/bounty tooling (zqm-sword,
  zqm-auth, bounty-tools), other nodes' indexers, meta-staging repos. EXCLUDE
  with a one-line reason each.

CAUTION for ZQM-Computing/hermes-config: its live tree includes
`instances/*/state/session_tokens.txt` and `pastes/` — cloning it wholesale to a
node leaks secrets. Diff config SELECTIVELY only.

Always QUANTIFY the verdict: per-tier counts + TOTAL, label each repo's claim
PROVEN by live API evidence. Repo descriptions lie; `gh api` languages + tree don't.
