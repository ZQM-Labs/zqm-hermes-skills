---
name: github-inventory
description: "Account-wide GitHub repository inventory: enumerate all repos, detect languages, README previews, top-level trees, recent commits, size, topics, and issue/PR counts. Use when asked to inspect, audit, or summarize everything in a GitHub account or org. For full diagnostics, also see references/github-api-field-compatibility.md and the Deep Diagnostics section below."
version: 0.1.0
author: Alex Zelenski / Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [GitHub, Inventory, Audit, Repositories, gh-cli, REST]
    related_skills: [github-auth, github-repo-management, codebase-inspection]
---

# GitHub Repository Inventory

Account-wide and per-repo inspection. Covers metadata, language breakdown, README previews, top-level trees, and recent-commit signals.

## Prerequisites

- Authenticated with GitHub (`gh auth status` or `GITHUB_TOKEN` exported)
- Python stdlib available for JSON/base64 decode
- On Windows: prefer `execute_code`/`python` over shell heredocs because `/tmp` may not exist

## 1. List every accessible repo

```bash
OWNER="ZQM-Computing"
gh repo list "$OWNER" --limit 1000 --json name,url,visibility,updatedAt,description
```

Parse the JSON to build the master list. If shell parsing is fragile, route through Python:

```python
import subprocess, json
out = subprocess.check_output(["gh","repo","list","ZQM-Computing","--limit","1000","--json","name,url,visibility,updatedAt,description"], text=True)
repos = [r["name"] for r in json.loads(out)]
print(len(repos), "repos")
```

## 2. Per-repo detail collection

For each repo, gather:

| signal | preferred command |
|--------|-------------------|
| metadata | `gh repo view $r --json ...` + fallback API call |
| languages | `gh api repos/$OWNER/$r/languages` |
| README | `gh api repos/$OWNER/$r/readme --jq '.content'` then base64 decode |
| top-level tree | `gh api repos/$OWNER/$r/contents` |
| recent commits | `gh api repos/$OWNER/$r/commits?per_page=5 --jq '.[].commit.message'` |
| workflows | `gh api repos/$OWNER/$r/actions/workflows` |

### 2.1 `gh repo view` field quirk

Some `gh` versions fail with `Unknown JSON field: "language"` or omit fields entirely. When that happens, do not retry the same wrapper. Switch to equivalent REST endpoints directly:
- primaryLanguage → `/languages` endpoint
- README content → `/readme` endpoint
- Commit messages → `/commits` endpoint
- Workflows → `/actions/workflows` endpoint
- repo size/disk usage → `diskUsage` field (MB, integer); `sizeKB` is NOT a valid field in current `gh repo view`

This avoids silent data loss from omitting fields rather than erroring. Also, some repos return 404 for recursive tree fetches; this usually means the default branch is not `main`/`master` or the repo is empty. Always try `master` → `main` → `develop` in that order instead of trusting `defaultBranchRef.name`.

### 2.2 README base64 helper

```python
import base64
raw = json.loads(out)["content"]
text = base64.b64decode(raw).decode("utf-8", errors="replace")
preview = "\n".join(text.splitlines()[:14])
print(preview)
```

### 2.3 Provenance-safe file access pattern

**Never use `GET /repos/{owner}/{repo}/contents/{path}` for existence checks.** That endpoint can return `404` for files that do exist in git, due to API-surface divergence, content-generation backpressure, or abuse-prevention responses that do not consume rate-limit quota. Rate-limit headers will still show healthy quota during these false negatives, so do not conflate 404 with rate limiting.

Instead, for **existence/size/sha**: use `GET /git/trees/{branch}?recursive=1` once and build a path→{sha,size} map. The tree API is authoritative for path existence on that branch.

For **content retrieval**, use `GET /git/blobs/{sha}` and base64-decode the result. This avoids all `contents/{path}` 404 edge cases.

Because branch-divergence is common (some repos have files on `master` that don't exist on `main`, even when GitHub reports `main` as default), fetch trees in this order:
1. `master`
2. `main`
3. `develop`

Pick the first branch that returns a non-empty tree. Do not rely on `defaultBranchRef.name` to choose the branch first.

## 3. Platform caveats

- Windows / MSYS: `/tmp` does not exist. Do not write temp files to `/tmp` from shell. Use `%TEMP%`, `%LOCALAPPDATA%\\Temp`, or `execute_code` with in-memory Python.
- PowerShell shells do not process git-bash style paths; use `python` as the orchestration layer instead.
- `gh api` pagination: when a repo's commit list might exceed 5, append `?per_page=N`. Default is 30.

## 4. Output shape

For account audits, emit per-repo sections:

```
REPO: ZQM-Computing/<repo>
  Description  :
  Language     :
  Size (KB)    :
  Topics       :
  Default Br   :
  Open Issues  :
  Open PRs     :
  Archived     :
  Created      :
  Last Push    :
  Lang Bytes   :
  README preview:
  Top-level    :
  Recent 5 commits:
```

If a field is unavailable, write `-` instead of omitting the line.

## 5. Deep Diagnostics

When the user asks for a full in-depth investigation (e.g., "full diagnostics", "all of the above"), extend the basic inventory into a comprehensive report.

### 5.1 Batch pre-fetch pattern

Collect all data in Python using `subprocess.run` with `gh api` to avoid shell escaping issues on Windows:

```python
import subprocess, json, base64

def run(cmd):
    r = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    return r.stdout.strip(), r.stderr.strip(), r.returncode

# metadata per repo
out, _, _ = run(f"gh repo view owner/{repo} --json name,visibility,primaryLanguage,diskUsage,topics,defaultBranchRef,issues,pullRequests,createdAt,updatedAt,pushedAt,isArchived,stargazerCount,forkCount,watchers")
data = json.loads(out)

# languages endpoint (bypasses gh repo view field quirks)
out, _, _ = run(f"gh api repos/owner/{repo}/languages")
langs = json.loads(out)

# recursive git tree
branch = data.get('defaultBranchRef', {}).get('name', 'main')
out, _, _ = run(f"gh api https://api.github.com/repos/owner/{repo}/git/trees/{branch}?recursive=1")
tree_data = json.loads(out)
blobs = [t for t in tree_data.get('tree', []) if t.get('type') == 'blob']
total_bytes = sum(f.get('size', 0) or 0 for f in blobs)
blobs.sort(key=lambda x: x.get('size', 0) or 0, reverse=True)

# read arbitrary file by path
out, _, _ = run(f"gh api repos/owner/{repo}/contents/{file_path}")
item = json.loads(out)
text = base64.b64decode(item.get('content', '')).decode('utf-8', errors='replace')

# recent commits
out, _, _ = run(f"gh api repos/owner/{repo}/commits?per_page=5")
arr = json.loads(out)
msgs = [c.get('commit', {}).get('message', '').split('\n')[0] for c in arr[:5]]

# workflows
out, _, _ = run(f"gh api repos/owner/{repo}/actions/workflows")
wf_data = json.loads(out)
workflows = [w.get('name', '') for w in wf_data.get('workflows', [])]
```

### 5.2 Report structure

Produce a Markdown report saved to disk:

```
# ZQM-Computing Full Repo Diagnostics
Generated: <timestamp>
Account: <owner>
Total repos: <N>

## Summary
| Repo | Visibility | Lang (primary) | Size | Files | Issues | PRs | Archived | Last Push |

## Per-Repo Detail
### <repo>
- Visibility:
- Description:
- Primary language:
- Topics:
- Default branch:
- Stars / Forks / Watchers:
- Created / Last push:
- Open issues / PRs:
- Total tracked files (blobs):
- Total size:
- Top 8 files by size:
- Languages:
- GitHub Actions workflows:
- Recent commits:

## Security & Risk Flags
| Severity | Repo | Finding |

## Cross-Repo Dependency Map
- hermes-agent loads from hermes-config
- ...

## Local Clone State
| Repo | Local Path | Branch | Commit | Remote |
```

Write the report to disk at the user's `Documents` path, then print it to stdout for immediate review.

### 5.3 Redaction discipline

Files containing live credentials, LAN recon data, or large runtime state should be reported by **path and size only**, not printed verbatim, unless the user explicitly requests a full content dump. Sensitive indicators include:

- `findings.md` with hostnames, IPs, MACs, accounts, plaintext passwords
- `state.db`, `*.db-wal` runtime databases
- `adapter-routing.json` with verified tokens/identifiers
- `*_probe.ps1` / `*_bypass.py` live-security scripts
- `instances/*/state/` runtime state directories

Always flag these in the Security & Risk Flags table.

### 5.4 Workspace-dominant vs remote-only pattern

When the user asks "investigate all systems", also produce a separate **local vs remote** audit:
- Scan common roots: `~/Documents`, `~/repos`, `~/github`, and their Windows equivalents.
- List all repos cloned locally with branch, HEAD, remote, and ahead/behind counts.
- Remaining repos are remote-only; note that offline audits cannot inspect them.

## 6. Pitfalls

1. **Bound temp paths to real paths** — shell heredocs that write to `/tmp/...` fail on Windows.
2. **`gh repo view` is not stable across versions** — treat it as best-effort metadata, not authoritative.
3. **Large repos have large trees** — `gh api .../contents` returns only top-level; use `/git/trees/{branch}?recursive=1` for full trees. Check `truncated`.
4. **README with no base64 content** — some repos have no README; handle gracefully.
5. **Offline / rate limited** — when `gh api` returns 403 or network is restricted, fall back to local `git` introspection on clones.
6. **404s on recursive tree** — always resolve `defaultBranchRef.name` from metadata before constructing the tree URL. Some repos return 404 on the assumed default branch.
7. **Windows pathing** — do not use POSIX `/tmp` heredocs from shell on Windows. Use Python `execute_code` or `%TEMP%` / `%LOCALAPPDATA%`.
8. **Large output volume** — diagnostics across many repos and deep trees can produce 100+ KB reports. Write to disk first, then print.
9. **Shell quoting risks in `gh api`** — always quote the URL argument to `gh api` to prevent shell interpolation of API path characters.
10. **`gh api --jq` with quoted filters** — certain `--jq` expressions conflict with Windows shell quoting; prefer parsing with `json.loads` over `--jq` on Windows. See `references/github-api-field-compatibility.md` for detailed workarounds.
11. **404s on recursive tree** — always resolve `defaultBranchRef.name` from metadata before constructing the tree URL. Some repos return 404 on the assumed default branch; this is not fatal, just skip that repo's tree and note it.
12. **Workspace-dominant vs remote-only** — when asked "investigate all systems", also audit local clone state. Scan common roots (`~/Documents`, `~/repos`, `~/github`, and Windows equivalents), then clearly separate what is inspectable offline versus remote-only.
