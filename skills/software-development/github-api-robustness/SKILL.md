---
name: github-api-robustness
description: Canonical methodology for verifying files, branches, and live repo state against GitHub. Use when existence checks return false negatives, when auditing non-default branches, or when building repo inventories against GitHub REST.
---

# GitHub API Robustness

Canonical methodology for verifying files, branches, and live repo state against GitHub. This skill exists because GitHub's REST endpoints are not consistent, and naive calls produce false negatives that look like missing content.

## When to use this skill

- Verifying file existence/content in private repos
- Proving code/signatures exist without clone
- Auditing file presence across multiple branches with diverged defaults
- Windows-local verification where TEMP-path execution or global `python` resolution is unreliable

## Golden rule

**Never rely on `GET /repos/{owner}/{repo}/contents/{path}` for existence checks.** It can return `404` for files that do exist on non-default branches. It is not authoritative.

## Authoritative verification stack

1. **Tree API** — `GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1`
   - Authoritative for path existence, size, and SHA in one call.
   - Use this first; cache `sha` values for later content retrieval.
   - Scan the returned `tree` array for paths you care about.

2. **Blob API** — `GET /repos/{owner}/{repo}/git/blobs/{sha}`
   - Use this for content retrieval when you need file body but want to avoid contents-API canonicality issues.
   - Returns base64 `content`.

3. **Repo metadata** — `gh repo view ... --json ...` or `/repos/{owner}/{repo}`
   - Fine for metadata: `diskUsage`, `primaryLanguage`, `defaultBranchRef`, `visibility`, timestamps.
   - Trust `defaultBranchRef` only as a hint. See branch fallback below.

## Branch fallback order

Do not trust GitHub's reported default branch for file existence. Some repos have files on `master` that are absent from `main`, even when GitHub says `main` is default.

Use this probe order for any target path:
1. `master`
2. `main`
3. `develop`

Stop on first branch that contains the path in its tree.

## Practical command recipe

```bash
# 1. Get tree (try fallbacks)
for branch in master main develop; do
  if gh api "/repos/ZQM-Computing/<repo>/git/trees/${branch}?recursive=1" >/dev/null 2>&1; then
    TREE_BRANCH="$branch"
    break
  fi
done

# 2. Find a file's SHA from the tree
FILE_SHA=$(gh api "/repos/ZQM-Computing/<repo>/git/trees/${TREE_BRANCH}?recursive=1" \
  | jq -r '.tree[] | select(.path=="<path>") | .sha')

# 3. Get content by blob SHA
if [ -n "$FILE_SHA" ]; then
  CONTENT=$(gh api "/repos/ZQM-Computing/<repo>/git/blobs/${FILE_SHA}" \
    | jq -r '.content' | base64 -d)
fi
```

## Pitfalls

- **False 404s** — contents API conflates missing paths with branch/cache quirks. Do not treat its 404 as authoritative negative.
- **Rate limit confusion** — if tree API still works after contents 404, the problem is API-surface not quota.
- **Schema drift** — `primaryLanguage` can be null. Guard `.get('primaryLanguage', {})` with `or {}`.
- **Branch divergence** — default branches lie. Always probe `master → main → develop` when finding files.
- **Language fields** — `gh repo view --json diskUsage` returns kilobytes; `.json sizeKB` does not exist. Use `diskUsage` and divide manually.
- **isEmpty / isDisabled** — these fields are not in the current `gh repo view` schema. Drop them from scripts.
- **Repo-root config.json** — checking out a config file does not guarantee `json.load()` will succeed if it contains Windows backslashes. Fix the file contents or normalize invalid escapes before parsing, e.g. by rewriting unescaped backslashes then re-serializing.
- **Config path hygiene** — mutable runtime config should live under the user-profile data dir, not the repo tree, so rewrite paths do not fight the VCS tree. On Windows, prefer `os.path.expanduser("~")` over shell `~`/`$HOME` expansion for file paths.

## Windows verification runtime

- Prefer repo-local interpreter: `.venv/Scripts/python.exe`
- If `%TEMP%` script execution fails, run `hermes-verify-*.py` from the repo/project tree instead.
- Do not rely on global `python` on Windows host setups that activate another venv first.
- Windows shell path resolution varies between MSYS `/c/...` and native `C:\...`; after 2 identical failures, rerun the runner once before changing strategy.

## Support files

- `references/api-verification-playbook.md` — condensed reproduction recipes and provider quirk notes.
- `references/windows-verification-runtime.md` — Windows-specific Python execution patterns and failures recovered during ZQM node indexer verification.