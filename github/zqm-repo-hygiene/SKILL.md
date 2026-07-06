---
name: zqm-repo-hygiene
description: "Use when cleaning up ZQM-Computing repos, standardizing README/branch/commit conventions, or keeping findings artifacts free of secrets."
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [github, cleanup, hygiene, standards, zqm]
    related_skills: [zqm-github-management, github-pr-workflow]
---

# ZQM Repo Hygiene

Standards for cleaning up and keeping `ZQM-Computing` repos consistent.

## Overview

Use this skill when auditing repo inventory, deleting empty shells, merging duplicate scripts, normalizing README/branch/commit conventions, or scrubbing findings artifacts.

## When to Use

- Cleaning or deleting empty/duplicate repos
- Standardizing repo naming, README structure, and branch conventions
- Reviewing commit discipline or topics/metadata
- Preparing findings artifacts for publication or sharing

Don't use for: cloning, forking, PR creation (`github-pr-workflow`), or auth fixes (`zqm-github-management`).

---

## 1. Cleanup targets

Empty shells:
- `hermes`
- `comfy-custom`

Overlap candidates:
- `zqm-auth` and `hermes-config` duplicate webhook/config-fix scripts.

Action:
- Delete empty repos only after confirming no open issues/secrets/workflows.
- Do not delete a repo before checking for webhooks, Actions secrets, or pending PRs.

Completion criterion: deletion confirmed via `gh repo list`; if preserved, archived under `deprecated/`.

## 2. Naming and branches

- Repo names: kebab-case, noun-first, location-scoped if node-specific.
  - Good: `zqm-node-01-indexer`, `bounty-tools-naabu`
  - Avoid vague names or internal codenames unless documented.
- Branches:
  - `main` as default for new repos.
  - Feature branches: `feat/<short>`, `fix/<short>`, `docs/<short>`, `refactor/<short>`
  - No long-lived feature branches unless lifecycle is tracked.

Completion criterion: new repo names and default branches are consistent.

## 3. README template

All active repos should include:

```md
# <Repo Name>

One sentence: what this is.

## Setup
Prereqs, commands.

## Run
How to start/use it.

## Auth
If applicable: local account expectations, token paths, secrets policy.

## Troubleshooting
3-6 bullets for the most common failure modes.

## Status
Active / Deprecated / Experimental
```

Keep findings READMEs short: purpose, file index, security note if credentials were ever present.

Completion criterion: README exists and contains every top-level section above.

## 4. Commit discipline

- Use conventional commits: `type(scope): short summary`
  - `feat`, `fix`, `refactor`, `docs`, `test`, `ci`, `chore`, `perf`
- Body wrapped at 72 chars when needed.
- Never commit secrets, cookies, or live tokens.
- Findings updates should be atomic: one logical change per commit.

Completion criterion: recent commits follow conventional format; no secrets in history.

## 5. Repo metadata

- Add 3-5 topics.
- Set description to one line.
- Disable wiki/issues/actions only if needed; default to enabled.

Completion criterion: `gh repo view` shows topic count >= 3 and non-empty description.

## 6. Cleanup checklist

1. Identify empty repos via `gh repo list`.
2. Check for secrets/workflows/issues before deletion.
3. Record deletion in `zqm-localhost-findings management.md`.
4. Remove duplicate script copies or archive them under `deprecated/` before deleting.
5. Update `inventory.json` in findings repo after cleanup.

Completion criterion: every item above checked off.

---

## Common Pitfalls

1. Deleting repos before checking Actions secrets, webhooks, or workflows.
2. Forgetting to update `zqm-localhost-findings/inventory.json` after repo changes.
3. Leaving duplicate script copies in multiple repos instead of deduping.
4. Using vague repo names that don't reveal purpose or owner.
5. Committing findings without scrubbing embedded credentials first.

## Verification Checklist

- [ ] Empty/duplicate repo inventory current
- [ ] README sections present for all active repos
- [ ] Recent commits use conventional format
- [ ] No secrets in committed files or recent history
- [ ] Topics and descriptions set on all active repos
- [ ] `inventory.json` matches live repo list
