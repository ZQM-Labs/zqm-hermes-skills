# Software Management Workflow for ZQM Private Repos

Use this when the user wants commit history cleanup, repo hygiene, branch standardization, or to "properly" manage code across private GitHub repos.

## Audit order
1. Enumerate local repos by `.git` presence, not just known roots.
2. For each repo: branch, remote, ahead/behind counts, dirty paths, untracked runtime files.
3. Separate intentional drift from environment pollution: backups, caches, logs, memory `.bak.*`, node zips, `__pycache__`, `.venv`, OneDrive sync debris, secrets.

## `.gitignore` retrofit
- Add missing ignore groups first: runtime scratch, cache/terminal, cron/output, backup/corrupt configs, bundled runtimes, secrets.
- Verify with `git check-ignore -v <sample paths>`.
- Then propose `git rm --cached` for already-tracked paths that should now be ignored.
- Do not run `git rm --cached` without explicit user approval; it mutates the index.

## Commit rules
- Stage only intentional changes.
- Use conventional commits: `feat(scope):`, `fix(scope):`, `chore(scope):`
- One logical change per commit.
- Do not bulk-commit prebuilt binaries, zip archives, runtime tooling, or platform bins.

## Push rules
- Push after commit.
- If behind a trusted owned remote: `git pull --rebase` then push.
- If force is required for owned repos: `git push --force-with-lease`.
- Never force-push to shared forks or upstreams.

## Branch hygiene
- Keep local default branch tracking the remote default branch.
- If renaming, use `git branch -m` and `git branch -u origin/<new> <new>`.
- Normalize names only after confirming remote default branch names.

## Hermes config corruption quirk on this host
- Live `config.yaml` can parse cleanly while backup/corrupt siblings fail.
- If Hermes warns about parse failure, validate live path and inspect backup files separately.
- Do not delete user config; rely on Hermes automatic `.bak` snapshots.
