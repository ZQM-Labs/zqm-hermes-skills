# GitHub Push-Time Blocker Taxonomy

## `Repository not found`

Cause: remote repo does not exist or was moved/renamed.

Fix: verify repo existence first, then recreate or repair the remote URL before retrying.

## `pre-receive hook declined` due to file size

Cause: tracked file exceeds GitHub 100MB limit.

Fix: migrate to Git LFS or remove the oversized path from history with `git filter-repo`/BFG, then force-with-lease-push only after confirming local intent.

## `fetch first`

Cause: remote contains commits the local branch does not have.

Fix: `git pull origin <branch> --rebase`, resolve conflicts, then push.

## `refusing to merge unrelated histories`

Cause: branches were created independently without shared history.

Fix: set branch tracking explicitly or create an explicit merge commit that preserves both histories, then sign and push.
