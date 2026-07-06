# ZQM Hermes Skills Library

Shared Hermes skills snapshot for the ZQM Windows homelab and `ZQM-Computing` GitHub workflow.

## What’s inside

- **All installed local skills** from `C:\Users\zqmco\AppData\Local\hermes\skills`
- **ZQM-local additions:**
  - `productivity/windows-lan-investigator` — evidence-gathering playbook for Windows LAN hosts
  - `productivity/zqm-local-setup` — entry-point skill routing for local setup, LAN investigation, and GitHub hygiene
- **Patched skills for Windows/ZQM:**
  - `cli/networking-tools` — Windows-primary networking CLI
  - `software-development/python-debugpy` — Windows-ready debugger skill
  - `github/zqm-github-management` — ZQM-specific GitHub workflow
  - `github/zqm-repo-hygiene` — ZQM repo cleanup/standards

## Canonical local skills to load on Windows

| Task | Skill |
|---|---|
| Broken `.venv`, Python 3.12 hardcoded paths, service scripts | `python-windows-project-setup` |
| Port scan / ping sweep / traceroute / DNS / HTTP probes | `networking-tools` |
| Localhost port conflicts / local server launch | `localhost-management` |
| Full LAN host investigation | `windows-lan-investigator` |
| Git auth / `gh` CLI / private repo edits | `zqm-github-management` |
| Repo naming / README / cleanup / commit discipline | `zqm-repo-hygiene` |
| PR workflow / branch strategy | `github-pr-workflow` |
| ZQM environment entry point | `zqm-local-setup` |

## Consuming this library

```bash
git clone https://github.com/ZQM-Computing/zqm-hermes-skills.git
```

Or cherry-pick individual skills by copying their folders into `~/.hermes/skills/`.

## Library size

Skills committed: 3

## Maintenance

Run `sync-skills.sh` from this repo to update the snapshot from the local Hermes skills directory.

## License

MIT unless otherwise noted in individual skill folders.
