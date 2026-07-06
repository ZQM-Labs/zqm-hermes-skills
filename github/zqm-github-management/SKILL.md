---
name: zqm-github-management
description: "Use when working inside ZQM-Computing GitHub repos on Windows. Fixes local git push auth with gh CLI, edits private repo files safely without echoing credentials, and covers Windows-specific GitHub workflow pitfalls."
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [github, windows, zqm, credentials, git, gh]
    related_skills: [github-repo-management, zqm-repo-hygiene, github-pr-workflow]
---

# ZQM GitHub Management

ZQM-tailored GitHub workflow for Windows: fix broken git push/auth, prefer `gh` CLI over raw `git` HTTPS, and keep private repo edits clean.

## Overview

Use this skill when normal `git push` is failing on Windows, when you want the fastest safe path to read/write private repo content, or when enforcing ZQM-specific credential and repo standards. It assumes `ZQM-Computing` org, `zqmco` local user, and private repos.

## When to Use

- Local `git push` exits 128 or prompts for credentials
- You need to write a file to a private repo without fixing git first
- Setting repo topics, descriptions, or default branches
- Deciding whether to delete or archive empty/duplicate repos
- Auditing auth paths, secrets handling, or Windows-specific git behavior

Don't use for: PR review, issue triage, or general git tutorial content (`github-pr-workflow`, `github-issues`, `github-code-review`).

---

## 1. Fix Windows git push auth

Symptom: `git push` exits 128 from any `ZQM-Computing` repo.
Cause: local Git credential helper is absent or misconfigured.

```powershell
winget install --id GitHub.GitCredentialManagerCore
git config --global credential.helper manager-core
gh auth setup-git
git ls-remote https://github.com/ZQM-Computing/<repo>.git
```

Alternative: switch remote to SSH after adding an SSH key to GitHub.
Completion criterion: `git ls-remote ...` returns refs without password prompt.

## 2. Preferred auth path

Preferred: `gh` CLI. It bypasses local git credential issues for repo/API work.

```powershell
& 'C:\Program Files\GitHub CLI\gh.exe' auth status
& 'C:\Program Files\GitHub CLI\gh.exe' api repos/ZQM-Computing/<repo>/contents/<path> --method PUT -f message="..." -f content="$(powershell -NoProfile -Command \"[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:/...'))\")" -f branch=master
```

Avoid embedding raw tokens in HTTPS URLs.

## 3. Repo inventory and cleanup

Empty/no-op repos to consider deleting:
- `hermes`
- `comfy-custom`

Overlap candidates:
- `zqm-auth` and `hermes-config` duplicate webhook/config-fixer scripts.

Completion criterion: after deletion or restructuring, `inventory.json` in `zqm-localhost-findings` reflects current state.

## 4. Standards

- Default branch: `main` for new repos.
- License: MIT unless research/bounty terms differ.
- Topics: add 3-5 concise tags via `gh repo edit --add-topic "..."`.
- README: one sentence purpose, setup, run, API/auth, troubleshooting, license.
- LICENSE: present unless repo is purely internal audit artifacts.
- Secrets: only in `.github/` automation or local OS-backed stores; never committed files.

Completion criterion: repo metadata, README, and LICENSE exist and are consistent.

Windows PowerShell can introduce escaping issues for shell-style heredocs. Use absolute paths with forward slashes in `gh api` file reads when necessary.
- Don't rely on shell heredocs in PowerShell.

Completion criterion: API write lands without escaping errors; response includes new file SHA.

## 6. Verification before marking done

1. JSON: `python -c "import json,sys; json.load(open(sys.argv[1]))" <path>`
2. Markdown: file exists, non-empty, no secret markers unless intended
3. API writes: confirm new file SHA via `gh api contents/<path> --jq '.sha'`

Completion criterion: JSON parses, Markdown is non-empty, API SHA returned.

Pushing via GitHub API does not constitute a passing git-push workflow. Fix credential helper to restore normal workflow.

---

## Common Pitfalls

1. Forcing credential manager install and skipping `gh auth setup-git`. On Windows, `gh.exe` path-based credential helper is often the working fix.
2. Editing repos without first checking for empty shells that should be deleted or archived.
3. Hardcoding secrets in README or script files and then pushing to private repos. Privacy does not remove the obligation to rotate and remove secrets.
4. Using PowerShell heredocs or single-quoted escaping for Base64 `content` fields; use explicit PowerShell `[Convert]::ToBase64String(...)` instead.
5. Assuming GitHub API writes mean git is healthy. They are a workaround, not a replacement.

## Verification Checklist

- [ ] `git ls-remote` works without password prompt after remediation
- [ ] `gh auth setup-git` succeeded if git credentials were broken
- [ ] API writes confirmed via new file SHA
- [ ] JSON files parse cleanly before commit
- [ ] No secrets, tokens, or cookies in committed files
- [ ] `inventory.json` updated after repo cleanup
