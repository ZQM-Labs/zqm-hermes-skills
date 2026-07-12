# GitHub API Verification Playbook

Condensed reproduction recipes and provider-specific quirks discovered during repo audits.

## False-negative root cause: contents API 404

Symptom: `gh api /repos/ZQM-Computing/<repo>/contents/<path>` returns `404 Not Found` for a file that exists in the repo.

Root cause: GitHub contents API can return 404 for existing files on non-default branches. Rate limit was ruled out because remaining quota stayed high (`X-RateLimit-Remaining: 4872`) after repeated failures.

Fix: switch to tree API + blob API with master-first branch fallback.

## Branch divergence observation

Several ZQM-Computing repos have divergent branch trees:
- `hermes-config`: `main` has 3688 paths, `master` has 12470 paths
- `zqm-localhost-findings`, `zqm-auth`, `comfyui-setup`: files present on `master`, absent from `main`
- GitHub `gh repo view` reports `main` as default branch even when `master` contains authoritative files

Fix: probe `master` first, then `main`, then `develop`. Stop when tree succeeds.

## Schema drift notes

- `gh repo view ... --json isDisabled` → unknown field error; field does not exist in current schema. Remove.
- `gh repo view ... --json sizeKB` → does not exist. Use `diskUsage` instead; it returns raw bytes.
- `primaryLanguage` can be `null`; always use `(info.get('primaryLanguage') or {}).get('name', '?')` guard pattern.
- `defaultBranchRef` can be `null`; guard with `info.get('defaultBranchRef') or {}`.

## Token economy tip

Large blob fetches across 18 repos time out at 180s and 300s. Switch to metadata-only passes (`/languages` endpoint) when you do not need full file bodies.

## Windows path/temp execution quirk

Symptom: `write_file` creates a temp `.py` under `C:\Users\<user>\AppData\Local\Temp\`, but executing that exact path via terminal can resolve to `C:UserszqmcoAppDataLocalTemp...` and fail with `No such file or directory`.

Fix/resolution:
- Prefer `cp -f` with POSIX `/c/Users/...` source and target together, then execute the copied path.
- If temp execution fails, fall back to repo-local copy execution rather than inventing a pathless rerun.
- Do not assume multiple identical-path reruns will recover; change path form once instead of repeating.
