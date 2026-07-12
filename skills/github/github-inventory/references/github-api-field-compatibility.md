# GitHub API Field Compatibility Issues

Resolved during ZQM-Computing org inventory runs on Windows + gh CLI.

## 1. `gh repo view --json language` 404s

**Symptom:** `Unknown JSON field: "language"`

**Fix:** Do not request `language` from `gh repo view`. Use the REST endpoint instead:

```bash
gh api repos/OWNER/REPO/languages
```

Returns raw byte counts per language as JSON: `{"Python": 12345, "JavaScript": 6789}`.

## 2. `gh repo view` metadata schema is incomplete

Some fields that appear in GitHub docs (`size`, `createdAt`, `updatedAt`, `pushedAt`) may all return `null` or be absent from the wrapper's JSON schema.

**Fix:** When a metadata command returns a JSON parse or schema error, fall back to the raw REST endpoint:

```bash
gh api repos/OWNER/REPO --jq '{name, visibility, created_at, updated_at, pushed_at}'
```

## 3. Recursive tree 404s

**Symptom:** `gh: Not Found (HTTP 404)` when calling:

```
gh api https://api.github.com/repos/OWNER/REPO/git/trees/main?recursive=1
```

**Causes:**
- Default branch is not `main` or `master`.
- Repo has no commits on the expected branch.

**Fix:** Read `defaultBranchRef.name` from repo metadata first:

```bash
BRANCH=$(gh repo view owner/repo --jq '.defaultBranchRef.name' 2>/dev/null || echo main)
gh api "https://api.github.com/repos/owner/repo/git/trees/$BRANCH?recursive=1"
```

If the default-branch query also fails, try `master`, `develop`, and the most-recent commit SHA from the commits endpoint.

## 4. `gh api` jq compatibility on Windows

**Symptom:** `failed to parse jq expression (line 1, column 1): '.content'`

**Cause:** On some Windows `gh` builds, inline `--jq` arguments are not parsed correctly when passed inside `subprocess.run` with `shell=True`.

**Fix:** Fetch raw JSON via `gh api ...` without `--jq`, then parse with Python:

```python
import json
out, _, _ = run("gh api repos/OWNER/REPO/readme")
data = json.loads(out)
content = data.get("content", "")
```

## 5. `gh api --jq` with quoted filters

Certain `--jq` expressions contain `'` or `"` characters that conflict with Windows shell quoting. Use Python API calls via `subprocess.run` instead, or escape with backslash in git-bash.

**Preferred:** omit `--jq` entirely from `gh api` calls and filter in Python.

## 6. GitHub API rate limits

Authenticated requests: 5000/hr. Public requests: 60/hr. Org-wide scans of 18 repos with ~10 API calls each consume ~180 requests, well within limits under normal use. If rate-limited, insert exponential backoff between calls.
