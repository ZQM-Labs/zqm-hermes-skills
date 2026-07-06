---
name: github-repo-management
description: "Create, configure, remediate, and maintain GitHub repositories and their local git state. Covers setup, clone/fork, release management, Windows Git credential fixes, merge-conflict recovery, branch protection, secret rotation, and history purge workflows."
version: 2.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [GitHub, Repositories, Git, Releases, Secrets, Configuration, Remediation, Windows]
    related_skills: [github-auth, github-pr-workflow, github-issues]
---

# GitHub Repository Management

Create, configure, remediate, and maintain GitHub repositories. Each section shows `gh` first, then `git` + `curl` fallback.

## When to Use
- Create, clone, or fork a repo
- Edit repo settings after creation (visibility, default branch, wiki, issues, topics)
- Resolve Windows Git credential or merge-conflict failures
- Manage releases or GitHub Actions workflows
- Remediate exposed secrets or rotate credentials
- Clean git history and push clean state to remote

Don't use for: GitHub Actions authoring, PR review, issue triage (`github-issues`, `github-code-review`, `github-pr-workflow`).

---

## Prerequisites

- Authenticated with GitHub (see `github-auth` skill)

### Setup

```bash
# Prefer gh auth everywhere
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  AUTH="gh"
  gh auth setup-git
else
  AUTH="git"
  if [ -z "$GITHUB_TOKEN" ]; then
    if _hermes_env="${HERMES_HOME:-$HOME/.hermes}/.env"; [ -f "$_hermes_env" ] && grep -q "^GITHUB_TOKEN=" "$_hermes_env"; then
      GITHUB_TOKEN=$(grep "^GITHUB_TOKEN=" "$_hermes_env" | head -1 | cut -d= -f2 | tr -d '\n\r')
    elif grep -q "github.com" ~/.git-credentials 2>/dev/null; then
      GITHUB_TOKEN=$(grep "github.com" ~/.git-credentials 2>/dev/null | head -1 | sed 's|https://[^:]*:\([^@]*\)@.*|\1|')
    fi
  fi
fi

if [ "$AUTH" = "gh" ]; then
  GH_USER=$(gh api user --jq '.login')
else
  GH_USER=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | python3 -c "import sys,json; print(json.load(sys.stdin)['login'])")
fi

# Inside an existing repo
REMOTE_URL=$(git remote get-url origin)
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/]||; s|\.git$||')
OWNER=$(echo "$OWNER_REPO" | cut -d/ -f1)
REPO=$(echo "$OWNER_REPO" | cut -d/ -f2)
```

---

## 1. Repo Configuration

Run after creation to set standard defaults. Use `gh` when available, `curl` otherwise.

```bash
# Default branch, visibility, auto-merge, wiki, issues
gh repo edit "$OWNER/$REPO" --default-branch main --enable-auto-merge --enable-wiki=false --enable-issues=true --visibility private

# Topics/tags
gh repo edit "$OWNER/$REPO" --add-topic "automation,windows,homelab"
```

With curl:

```bash
curl -s -X PATCH \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$OWNER/$REPO \
  -d '{
    "name": "'"$REPO"'",
    "default_branch": "main",
    "has_wiki": false,
    "has_issues": true,
    "allow_auto_merge": true,
    "private": true
  }'
```

## 2. Merge Method and Auto-Delete

```bash
# Prefer squash merging, delete head branches after merge
gh repo edit "$OWNER/$REPO" --merge-method squash --delete-branch-on-merge
```

`merge-method` accepts: `merge`, `squash`, `rebase`.

## 3. Branch Protection

```bash
# View current protection state
gh api repos/$OWNER/$REPO/branches/main/protection --jq .

# Require 1 approval, no strict status checks yet
gh api repos/$OWNER/$REPO/branches/main/protection -X PUT -f required_pull_request_reviews[required_approving_review_count]=1
```

Common full block:

```bash
gh api repos/$OWNER/$REPO/branches/main/protection -X PUT -f required_status_checks[strict]=true \
  -f required_status_checks[contexts][]=ci/lint \
  -f required_status_checks[contexts][]=ci/test \
  -f required_pull_request_reviews[required_approving_review_count]=1 \
  -f enforce_admins=false \
  -f restrictions=null
```

## 4. Clone, Create, Fork

```bash
# Clone
gh repo clone owner/repo-name
git clone https://github.com/owner/repo-name.git

# Create private repo from existing dir
cd existing-dir
git init && git add . && git commit -m "Initial commit"
gh repo create new-project --private --source . --push

# Fork
gh repo fork owner/repo-name --clone
```

## 5. Releases

```bash
gh release create v1.0.0 --title "v1.0.0" --generate-notes
gh release download v1.0.0 --dir ./downloads
gh release list
```

With curl:

```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$OWNER/$REPO/releases \
  -d '{
    "tag_name": "v1.0.0",
    "name": "v1.0.0",
    "body": "## Changelog\n- Feature A\n- Bug fix B",
    "draft": false,
    "prerelease": false,
    "generate_release_notes": true
  }'
```

## 6. GitHub Actions (run/list/replay only)

```bash
gh workflow list
gh run list --limit 10
gh run view <RUN_ID>
gh run view <RUN_ID> --log-failed
gh run rerun <RUN_ID>
gh run rerun <RUN_ID> --failed
gh workflow run ci.yml --ref main
```

Workflow authoring is out of scope; use `github-pr-workflow` for CI config review.

---

## 7. Windows Git Remediation

These fix the most common failure modes on Git-Bash / `cmd` / PowerShell.

### 7.1 HTTPS credential helper broken (`credential-manager-core` missing)

Symptom: `gh` is logged in, but `git push` fails with `could not read Username` / `git-credential-manager` missing.

```bash
gh auth setup-git

# If git config is stale, force the absolute helper path
git config --global credential.helper "'C:\\Program Files\\GitHub CLI\\gh.exe' auth git-credential"

# Verify
git config --global --list | grep credential
git ls-remote https://github.com/$GH_USER/$REPO.git
```

### 7.2 Branch mismatch: local `main` vs remote `master`

Symptom: `fatal: The upstream branch of your current branch does not match the name of your current branch.`

```bash
git push origin HEAD:master
# Or change upstream to match local branch
git branch --set-upstream-to=origin/main main
```

### 7.3 Non-fast-forward push rejected

Symptom: `Updates were rejected because the remote contains work that you do not have locally.`

```bash
git checkout main
git pull origin main --no-rebase
# If merge attempt leaves a conflict, prefer merge over rebase on Windows
git merge origin/main --no-edit
# resolve conflicts, git add, git commit
git push origin main
```

Use `--force-with-lease` only if you are certain no one else pushed:

```bash
git push --force-with-lease origin main
```

Never use plain `--force` on shared branches.

### 7.4 Merge conflict in README.md after `git pull`

On Windows, edit conflicts conservatively:

1. If possible, `git checkout origin/main -- README.md` to start from remote version.
2. Append local-only additions with `cat >> README.md` or targeted `patch`.
3. `git add README.md && git commit -m "docs: merge README revisions"`
4. `git push origin main`

Avoid `git rebase` on Windows for long-lived branches; `merge --no-edit` is safer.

### 7.5 Stale lock files / askpass errors

Symptom: `error: cannot spawn /mingw64/bin/git-askpass.exe: No such file or directory`

```bash
git config --global --unset core.askPass
git config --global credential.helper "'C:\\Program Files\\GitHub CLI\\gh.exe' auth git-credential"
git credential-cache exit 2>/dev/null || true
```

---

## 8. Secret Remediation and History Purge

When a credential or secret has been committed to any visible file.

### 8.1 Immediate rotation

1. Rotate the exposed credential on every system where it is used.
2. Commit the rotated credential reference or removal in a new commit:

```bash
git add README.md
git commit -m "chore: replace live credential with reference to secrets manager"
git push origin main
```

### 8.2 Purge from history

After rotating, remove the secret from history with one of:
- `git filter-repo` (preferred, modern)
- `bfg --delete-files` or `bfg --replace-text`
- `git rebase -i` for small, recent changes

Example `git filter-repo`:

```bash
pip install git-filter-repo 2>/dev/null || python -m pip install git-filter-repo
cd repo
git filter-repo --path-glob '*.md' --replace-text <(printf 'PASSWORD==>REDACTED\n')
git push --force-with-lease origin main
```

Completion criterion: `git log --all -S 'old-password' | wc -l` returns `0`.

---

## 9. Cleanup of Orphaned Authenticated Sessions (Windows)

Symptom: `net use` shows stale connected sessions after credential rotation or decommission.

```powershell
# List SMB sessions
net use

# Disconnect a specific session
net use \\192.168.1.218\IPC$ /delete

# Close all managed connections
net use * /delete
```

Completion criterion: `net use` shows only intended connections.

---

## Quick Reference Table

| Action | `gh` | `git` + `curl` |
|---|---|---|
| Clone | `gh repo clone o/r` | `git clone https://github.com/o/r.git` |
| Create repo | `gh repo create name --private` | `POST /user/repos` + `git push` |
| Create from existing dir | `gh repo create name --source . --push` | `git init && git remote add && git push` |
| Fork | `gh repo fork o/r --clone` | `POST /repos/o/r/forks` then `git clone` |
| View info | `gh repo view o/r` | `GET /repos/o/r` |
| Edit settings | `gh repo edit --...` | `PATCH /repos/o/r` |
| Set default branch | `gh repo edit --default-branch main` | `PATCH /repos/o/r` with `default_branch` |
| Merge method | `gh repo edit --merge-method squash` | `PATCH /repos/o/r` with `allow_squash_merge` |
| Auto-delete branches | `gh repo edit --delete-branch-on-merge` | `PATCH /repos/o/r` with `delete_branch_on_merge` |
| Branch protection | `gh api repos/o/r/branches/main/protection -X PUT` | `PUT /repos/o/r/branches/main/protection` |
| Create release | `gh release create v1.0.0` | `POST /repos/o/r/releases` |
| List workflows | `gh workflow list` | `GET /repos/o/r/actions/workflows` |
| Re-run CI | `gh run rerun ID` | `POST /repos/o/r/actions/runs/ID/rerun` |
| Set secret | `gh secret set KEY` | `PUT /repos/o/r/actions/secrets/KEY` (+ NaCl encryption) |
| Fix HTTPS auth (Windows) | `gh auth setup-git` | configure `credential.helper` to absolute `gh.exe` path |
| Force-push after purge | `git push --force-with-lease origin main` | same |

---

## Verification Checklist

- [ ] `gh auth setup-git` succeeded if local `git push` was broken
- [ ] Repo settings verified (`gh repo view`)
- [ ] Default branch and merge method confirmed after edit
- [ ] Branch protection enabled via `gh api` or web UI
- [ ] No plaintext secrets in recent commits (`git log -S 'secret-name'`)
- [ ] Exposed credential rotated on all systems before history purge
- [ ] History purge run only after rotating the secret
- [ ] `--force-with-lease` used in place of `--force` for any rewrite
- [ ] README working-tree conflicts resolved without leaving `<<<<<<<` markers
- [ ] Remote `HEAD` matches local `main`/`master` cleanly on Windows
