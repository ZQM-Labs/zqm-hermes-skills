#!/usr/bin/env bash
set -euo pipefail

LOCAL_SKILLS="$LOCALAPPDATA/hermes/skills"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SKILLS="$REPO_ROOT/skills"
README="$REPO_ROOT/README.md"
REMOTE="origin"
BRANCH="main"

if [ ! -d "$LOCAL_SKILLS" ]; then
  echo "FAIL: local skills dir not found at $LOCAL_SKILLS"
  exit 1
fi

echo "== Syncing local skills -> $REPO_SKILLS"
rm -rf "$REPO_SKILLS"
mkdir -p "$REPO_SKILLS"
cp -a "$LOCAL_SKILLS/." "$REPO_SKILLS/"

# Re-write README with current local skill count
COUNT=$(find "$REPO_SKILLS" -mindepth 2 -maxdepth 2 -name 'SKILL.md' | wc -l | tr -d ' ')
cat > "$README" <<EOF
# ZQM Hermes Skills Library

Shared Hermes skills snapshot for the ZQM Windows homelab and \`ZQM-Computing\` GitHub workflow.

## What’s inside

- **All installed local skills** from \`C:\\Users\\zqmco\\AppData\\Local\\hermes\\skills\`
- **ZQM-local additions:**
  - \`productivity/windows-lan-investigator\` — evidence-gathering playbook for Windows LAN hosts
  - \`productivity/zqm-local-setup\` — entry-point skill routing for local setup, LAN investigation, and GitHub hygiene
- **Patched skills for Windows/ZQM:**
  - \`cli/networking-tools\` — Windows-primary networking CLI
  - \`software-development/python-debugpy\` — Windows-ready debugger skill
  - \`github/zqm-github-management\` — ZQM-specific GitHub workflow
  - \`github/zqm-repo-hygiene\` — ZQM repo cleanup/standards

## Canonical local skills to load on Windows

| Task | Skill |
|---|---|
| Broken \`.venv\`, Python 3.12 hardcoded paths, service scripts | \`python-windows-project-setup\` |
| Port scan / ping sweep / traceroute / DNS / HTTP probes | \`networking-tools\` |
| Localhost port conflicts / local server launch | \`localhost-management\` |
| Full LAN host investigation | \`windows-lan-investigator\` |
| Git auth / \`gh\` CLI / private repo edits | \`zqm-github-management\` |
| Repo naming / README / cleanup / commit discipline | \`zqm-repo-hygiene\` |
| PR workflow / branch strategy | \`github-pr-workflow\` |
| ZQM environment entry point | \`zqm-local-setup\` |

## Consuming this library

\`\`\`bash
git clone https://github.com/ZQM-Computing/zqm-hermes-skills.git
\`\`\`

Or cherry-pick individual skills by copying their folders into \`~/.hermes/skills/\`.

## Library size

Skills committed: $COUNT

## Maintenance

Run \`sync-skills.sh\` from this repo to update the snapshot from the local Hermes skills directory.

## License

MIT unless otherwise noted in individual skill folders.
EOF

cd "$REPO_ROOT"
git add -A
if git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

git commit -m "chore(skills): sync local Hermes skills snapshot"
git push "$REMOTE" "$BRANCH"
echo "OK: pushed skills snapshot."
