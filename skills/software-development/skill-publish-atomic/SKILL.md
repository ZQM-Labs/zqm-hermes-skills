---
name: skill-publish-atomic
description: 'Enforce the user''s standing publishing rule: consolidate related changes
  into ONE atomic commit and push to the CORRECT branch — never blind, never separate
  per-file commits. Covers the pre-publish consolidation pass, cross-reference wiring,
  branch verification (tree/blob API, not contents API), and the atomic commit+push
  sequence for Hermes skills and ZQM repos. Use when shipping skills, docs, or repo
  changes the user wants ''pushed properly after merged together correctly''.'
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - git
    - publish
    - atomic-commit
    - skills
    - branch-verify
    related_skills:
    - audit-sqlite-sink
    - fleet-council-audit
    - github-api-robustness
    - github-pr-workflow
    - github-repo-management
    - hermes-agent-skill-authoring
    - runtime-codebase-verification
    - verified-repo-diagnostics
    - zqm-repo-inventory-verification
    - zqm-systems-review
---
# Skill / Repo Publishing — Atomic & Correct-Branch

## When to use
- User says "push properly", "after merged together correctly", "ship these as one",
  or any publish of skills/docs/repo changes.
- You have multiple related edits (e.g. a new skill + its references + a cross-link in
  another skill) that must land together.

## RULES (standing, from user)
1. CONSOLIDATE first. Gather every related change (new SKILL.md, reference files,
   cross-reference edits in sibling skills) into ONE working set.
2. CROSS-REFER. Every new skill lists its `related_skills`; existing skills that should
   point at the new one get a `related_skills` patch. No orphan skills.
   **SAFE-EDIT THE FRONTMATTER — never regex it (HIT 2026-07-11).** YAML frontmatter must
   be mutated with PyYAML, NOT string/regex replacement: split on `^---\n(.*?)\n---\n`,
   `yaml.safe_load`, merge `metadata.hermes.related_skills` (union of existing + desired
   partners), `yaml.safe_dump(sort_keys=False, allow_unicode=True, default_flow_style=False)`,
   rejoin. Regex edits silently corrupt — a dangling `metadata:` block BEFORE `---` breaks
   skill loading (17 files corrupted this way; fixed only by restore-from-backup + PyYAML
   rewrite). Reusable method in `references/safe_frontmatter_edit.md`. Before ANY bulk
   frontmatter edit: `cp -r` the skills tree to a backup. After: validate EVERY SKILL.md
   with `yaml.safe_load` (one broken `---` = that skill fails to load). If corruption is
   found, restore from backup and re-run with the PyYAML method — do NOT hand-patch a
   dangling block.
   **CROSS-REFERENCE COMPLETION — full bidirectional verification (HIT 2026-07-11):**
   After the PyYAML mass-edit, the job is NOT done. Two failure modes surfaced this run:
   - **DANGLING-`metadata:` CORRUPTION VARIANT:** the safe-edit script's fallback branch
     (`re.sub(r"(---\s*\n)", block+"\n\\1", txt)`) can PREPEND a stray `metadata:` block
     BEFORE the opening `---`, leaving a dangling block that breaks the frontmatter of
     files whose existing shape didn't match the expected `metadata.hermes.related_skills`
     pattern. SYMPTOM: a file starts with `metadata:\n  hermes:\n    related_skills: [...]`
     and THEN the real `---` block. FIX: never use a regex insertion fallback — only mutate
     the parsed frontmatter dict and re-dump. If a dangling block appears, restore from the
     pre-edit backup and re-run with the dict-only method (no string insertion anywhere).
   - **UNVERIFIED EDGES / EXTERNAL DANGLING:** a forward edge (new skill lists partner X)
     is only HALF a link. After editing, VERIFY each edge is bidirectional: for every
     `related_skills` entry Y in skill X, confirm X is also in Y's `related_skills`. Build a
     small checker: parse all SKILL.md frontmatters into a name→set map, then assert
     `Y in fm[X] ⇒ X in fm[Y]` for every edge, EXCEPT skills that live in a STALE/duplicate
     tree (e.g. `agent-kb-audit` exists only under `~/.hermes/skills`, not the canonical
     `C:\Users\zqmco\AppData\Local\hermes\skills`) — those are EXTERNAL dangling refs; drop
     them from the forward list rather than editing a tree you don't own. Report the final
     edge count + any UNRESOLVED external dangles honestly (don't fake a back-link).
   - **POST-EDIT YAML VALIDATION IS MANDATORY:** after ANY bulk frontmatter change, parse
     every SKILL.md with `yaml.safe_load` and fail the run if any is unparseable. One broken
     `---` = that skill silently fails to load. This caught both corruption modes above.
3. VERIFY THE BRANCH before pushing. Use the GitHub tree API to confirm the target
   branch exists and you're on it — NOT the contents API for existence checks.
   ```bash
   gh api repos/<owner>/<repo>/branches/<branch> --jq '.name'
   git rev-parse --abbrev-ref HEAD   # must equal the target
   ```
4. ONE atomic commit. `git add` the whole consolidated set, `git commit` once with a
   message that names all the pieces. NEVER one-commit-per-file for a related set.
5. PUSH the correct branch. `git push origin <verified-branch>`. Confirm the remote
   ref moved. Do NOT push to main/master if the work belongs on a feature branch the
   user named.

## Pre-publish checklist
- [ ] All related files staged together (no stragglers in a later commit)
- [ ] New skill frontmatter valid (name/description/version/metadata.hermes.tags)
- [ ] `related_skills` wired both ways (new → siblings, siblings → new)
- [ ] Target branch confirmed via tree API, not guessed
- [ ] Commit message enumerates the consolidated changes
- [ ] Push target = verified branch; remote ref moved
- [ ] **On the Windows host: after `write_file`, verify the file actually landed in
      `C:\Users\zqmco\AppData\Local\hermes\skills\...` (see MSYS path trap below)**

## MSYS path trap on the Windows host (verify after EVERY write_file)
The `write_file` tool can mangle an MSYS-style path (`/c/Users/...`) into a PHANTOM
directory `C:\c\Users\...` (prepends `C:\` to the MSYS path). The write "succeeds" and
returns a `resolved_path` pointing at `C:\c\...` — but that tree is NOT the live skills
dir, and the registration/agent loader never sees it.

**Symptom:** `write_file` of `.../devops/ollama-fleet-lb/SKILL.md` reports success but
`skills_list` / `read_file` on the real path show the file missing; a probe reveals the
file sitting under `C:\c\Users\zqmco\AppData\Local\hermes\skills\...`.

**Fix (reliable sequence):**
1. After `write_file`, confirm the real location, not the returned `resolved_path`:
   ```bash
   find "/c/Users/zqmco/AppData/Local/hermes/skills" -name SKILL.md -newermt '-5 min'
   # if missing there but present under /c/c/..., relocate:
   mv "/c/c/Users/zqmco/AppData/Local/hermes/skills/<cat>/<name>" \
      "/c/Users/zqmco/AppData/Local/hermes/skills/<cat>/"
   ```
2. Convert paths for Windows-native tools (python.exe) with `cygpath -w` — bare `/c/...`
   is misread as `C:\c\...` by `python.exe` on this host too.
3. `bash`/`find` resolve `/c/...` correctly; the danger is the `write_file` tool's path
   normalization AND Windows-native binaries reading the path. **`git` and `gh` are
   Windows-native** — they ALSO misread an MSYS `/c/Users/...` arg as the phantom
   `C:\c\Users\...` tree. Pass `C:/Users/...` (forward slashes, no leading slash-drive
   confusion) to `git`/`gh` commands, exactly like `python.exe`. Symptom this session:
   `git -C /c/Users/zqmco/...` failed with "not a git repository" until switched to
   `C:/Users/zqmco/...`. The hermes config repo root is `C:/Users/zqmco/AppData/Local/hermes`
   (the `.git` is the PARENT of `skills/`).

**Stale duplicate tree (do not trust it):** `C:\c\Users\zqmco\AppData\Local\hermes\skills\`
exists as a SEPARATE pre-existing copy (NOT a junction to `C:\`, confirmed distinct:
different SKILL.md count). It is a stale parallel tree that drifts from the real one.
My authored skills are NOT in it. Before trusting any on-disk skill content, confirm the
path starts with `C:\Users\zqmco\...` (real), not `C:\c\Users\zqmco\...` (stale duplicate).

## SECRET-HYGIENE — the skills tree often lives INSIDE the larger config repo (HIT 2026-07-11)
On this host `C:\Users\zqmco\AppData\Local\hermes\skills\` is a SUBDIR of the whole
`hermes` config dir, whose working tree ALSO holds secret-bearing untracked files:
`auth.json`, `auth.json.corrupt`, `ca`, `cache/`, `SOUL.md`, `config.yaml*`,
`channel_directory.json`, `gateway_state.json`, plus `*.db` state files. A blanket
`git add .` / `git add skills` would commit live credentials.
**RULE: stage ONLY the explicit skill subdirs you authored** — never the whole tree:
  git add skills/<cat>/<name> skills/<cat>/<name> ...   # ×N, explicit
Then SANITY-GREP the staged set before commit:
  git diff --cached --name-only | grep -iE "auth\.json|\.corrupt|/ca|cache/|SOUL\.md|config\.yaml"
If that prints ANYTHING, you have a secret staged — `git reset -q <file>` it before commit.
The 8-skill publish this run committed only `skills/<cat>/<name>` paths and the sanity
grep came back CLEAN; the secret files stayed untracked. That is the only safe pattern.

## DETACHED HEAD / empty-bootstrap repo (HIT 2026-07-11)
If `git rev-parse --abbrev-ref HEAD` prints `HEAD` (not a branch name), the repo was
initialized EMPTY — `main` exists only remote-side (`gh api .../branches` → just `main`,
tree API shows 0 files). `git status` shows the entire `skills/` as `??` (untracked) and
0 files tracked. Pushing in this state strands the commit off `main`.
**ANCHOR before push:**
  git fetch origin
  git checkout -B main origin/main      # set local main to track remote main
  git rev-parse --abbrev-ref HEAD        # must now print 'main'
Then stage (explicit dirs) + commit + push. Verify the remote ref moved
(`git push` prints `main -> main`) and confirm via tree API that your paths landed on `main`.

## Branch verification idiom (authoritative)
The user's hard rule: tree API then blob API; branch fallback master→main→develop;
NEVER use contents API for existence checks.
```bash
# confirm branch exists
gh api repos/ZQM-Computing/<repo>/branches  --jq '.[].name'
# confirm a path exists on that branch (tree API)
gh api repos/ZQM-Computing/<repo>/git/trees/<branch>?recursive=1 --jq '.tree[].path' | grep -F "skills/..."
```

## Pitfalls
- Separate commits per file = the user's explicit anti-pattern ("never blind/separate").
- Pushing to the wrong branch (e.g. main when it belongs on a feature branch) — verify
  first, the user has been burned by this.
- Leaving a new skill unreferenced by siblings → orphan; cross-link both directions.
- Using `gh api .../contents/<path>` to check existence — unreliable; use tree/blob.
- **write_file path mangling on this host:** a `/c/Users/...` path can be rewritten to
  `C:\c\Users\...` (phantom). Always verify the real `C:\Users\zqmco\...` location after
  writing and relocate if it landed in the stale `C:\c\...` duplicate tree.
- Reading from / trusting the stale `C:\c\Users\zqmco\AppData\Local\hermes\skills\`
  duplicate tree — it is NOT the live registry source; the real one is `C:\Users\...`.
- **SECRET-HYGIENE in the hermes config repo:** the skills tree often sits INSIDE the
  larger `AppData\Local\hermes` config dir, whose working tree also holds secret-bearing
  untracked files (`auth.json`, `auth.json.corrupt`, `ca`, `cache/`, `SOUL.md`,
  `config.yaml*`, `channel_directory.json`). NEVER `git add .` / `git add skills` blindly —
  it would commit credentials. Stage ONLY the explicit skill subdirs
  (`git add skills/<cat>/<name>` ×N). Before commit, sanity-grep the staged set for
  secret patterns: `git diff --cached --name-only | grep -iE "auth\.json|ca|cache/|SOUL\.md"`.
- **DETACHED HEAD / empty-bootstrap repo:** if `git rev-parse --abbrev-ref HEAD` prints
  `HEAD` (not a branch), the repo was initialized empty (e.g. `main` exists remote-only).
  Anchor before push: `git fetch origin && git checkout -B main origin/main`
  (branch confirmed via tree API), THEN stage + commit + push. Pushing a detached HEAD
  strands the commit off `main`.

## References
- hermes-agent-skill-authoring (SKILL.md format the commit must satisfy)
- github-api-robustness (the canonical verification methodology)
- zqm-repo-inventory-verification (which repos/branches are real)
- references/safe-frontmatter-crossref.md + references/safe_frontmatter_edit.md (the PyYAML cross-ref method + recovery)
