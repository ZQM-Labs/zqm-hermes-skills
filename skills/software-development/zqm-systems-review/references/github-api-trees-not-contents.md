# GitHub contents API 404 vs git tree API

**Date:** 2026-07-09
**Repro:** `gh api repos/ZQM-Computing/hermes-config/contents/check_npcap.ps1` returned HTTP 404,
even though `gh api repos/ZQM-Computing/hermes-config/git/trees/master?recursive=1`
lists `check_npcap.ps1` at path `check_npcap.ps1`, mode `100644`, size 2385, sha `e3a36ace1c...`.

## Root cause

This is not a rate-limit problem. `X-RateLimit-Remaining` was ~4872 at time of test.
The failure class is **API-surface mismatch**:

- `GET /repos/{owner}/{repo}/contents/{path}` can return `404` for files that exist in git,
  due to path encoding differences, content-generation backpressure, or abuse-prevention 404s.
- `gh repo view ... --json defaultBranchRef` reported `main` for `hermes-config`, but the
  file exists only on `master`. Querying the wrong branch first produced an empty tree, which
  the script then classified as "not found".

## Fix pattern

1. **Existence checks:** use `GET /git/trees/<branch>?recursive=1` first. The tree is
   authoritative for path, size, sha. Check whether `path in [t['path'] for t in tree]`.
2. **Content checks:** once the path is found in the tree, read its `sha`, then fetch
   `GET /git/blobs/<sha>` for base64-encoded content.
3. **Branch fallback order for this org:** `master` -> `main` -> `develop`. Some ZQM-Computing
   repos have files on `master` that are absent from `main`, even if GitHub reports `main`
   as the default branch.

## When to use which API

| Goal | Use |
|---|---|
| Does path X exist in repo? | `/git/trees/<branch>?recursive=1`, scan for path |
| What is the size/sha of path X? | Same tree response, read `size` and `sha` |
| Read file contents | `/git/blobs/<sha>`, base64-decode `content` |
| Enumerate top-level directory | `/contents/<dir>` is fine for directories |
| Get raw README preview | `/contents/README.md` + base64 decode |