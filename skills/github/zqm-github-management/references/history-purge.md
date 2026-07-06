# ZQM Credential History Purge — Runbook

Use this when a secret has been committed to private repo history and must be expunged.

## Order of operations

1. Rotate the exposed credential on every affected system.
2. Make a fresh clone of the repo into a new directory.
3. Rewrite history in that fresh clone.
4. Force-push with `--force-with-lease`.
5. Replace the old working directory with the rewritten clone.

If steps 2-4 fail at any point, stop. Do not retry with `--force` blindly.

## Fresh clone

Git filter-repo refuses to run inside a repo with normal reflog history. Always rewrite from a fresh clone.

```bash
cd C:\Users\zqmco
gh repo clone ZQM-Computing/zqm-localhost-findings zqm-localhost-findings-purge
cd zqm-localhost-findings-purge
```

If `gh repo clone` prompts, switch to HTTPS with the `gh` credential helper active:

```bash
git ls-remote https://github.com/ZQM-Computing/zqm-localhost-findings.git
```

## Pattern file

Write the replacement rules as a plain text file. Do not rely on bash process substitution `<(printf ...)` on Windows Git-Bash — it is unavailable.

```bash
cat > C:/Users/zqmco/zqm-localhost-findings-purge/.filter-patterns.txt <<EOF
regex:344SW00DL4nd!==>REDACTED
EOF
```

Use literal password string, not regex groups.

## Rewrite

Limit the rewrite to paths that actually contained the secret to keep the operation fast and to avoid rewriting unrelated binary blobs.

```bash
cd C:\Users\zqmco\zqm-localhost-findings-purge
git filter-repo --path-glob '*.md' --replace-text ./.filter-patterns.txt
```

Confirm:

```bash
git log --all -S '344SW00DL4nd!' --oneline
# expected: empty output
```

## Push

Use `--force-with-lease`, not `--force`. It refuses to push if the remote has advances you do not have locally.

```bash
git push --force-with-lease origin main
```

Completion criterion: response shows `main -> main`, no `rejected` or `non-fast-forward`.

## Swap working tree

After a successful push, retire the old working directory so future diffs cannot reintroduce the old history by accident.

```powershell
Move-Item -Force C:\Users\zqmco\zqm-localhost-findings C:\Users\zqmco\zqm-localhost-findings-old
Move-Item -Force C:\Users\zqmco\zqm-localhost-findings-purge C:\Users\zqmco\zqm-localhost-findings
```

## GitHub API content write alternative

If Git auth remains broken after `gh auth setup-git`, write files directly via the GitHub API as a temporary workaround. Do not leave repos in this state permanently.

```powershell
# PowerShell one-liner to write local file to repo root via API
gh api repos/ZQM-Computing/zqm-localhost-findings/contents/README.md -X PUT -f message="docs: refresh README" -f branch=master -f content="$(powershell -NoProfile -Command "[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:/Users/zqmco/zqm-localhost-findings/README.md'))")"
```

Caveat: API writes do not fix the underlying git auth path. Treat them as emergency writes only, and finish by restoring `git push`.

## Verification checklist

- [ ] Exposed credential rotated on all nodes/systems
- [ ] History rewrite done in a fresh clone
- [ ] `git log --all -S 'old-password'` returns empty
- [ ] Remote `origin/main` updated with `--force-with-lease`
- [ ] Old working directory retired or replaced
- [ ] API writes, if used, confirmed via new file SHA
