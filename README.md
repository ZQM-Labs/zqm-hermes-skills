# zqm-hermes-skills

[![CI](https://github.com/ZQM-Labs/zqm-hermes-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/ZQM-Labs/zqm-hermes-skills/actions/workflows/ci.yml) [![Tests](https://github.com/ZQM-Labs/zqm-hermes-skills/actions/workflows/tests.yml/badge.svg)](https://github.com/ZQM-Labs/zqm-hermes-skills/actions/workflows/tests.yml) [![Ruff](https://github.com/ZQM-Labs/zqm-hermes-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/ZQM-Labs/zqm-hermes-skills/actions/workflows/ci.yml) [![mypy](https://github.com/ZQM-Labs/zqm-hermes-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/ZQM-Labs/zqm-hermes-skills/actions/workflows/ci.yml)


Shared Hermes skills snapshot for the ZQM Windows homelab and `ZQM-Computing` GitHub workflow.

## About

`zqm-hermes-skills` is a curated library of Hermes skills mirrored and patched for the ZQM homelab. It includes canonical local skills for Windows system administration, LAN investigation, networking, GitHub hygiene, and repo management, plus ZQM-local additions for environment entry points and evidence gathering.

## Installation

```bash
git clone https://github.com/ZQM-Computing/zqm-hermes-skills.git
```

Copy individual skills into `~/.hermes/skills/`, or load the full tree into a Hermes profile.

## Usage

Use the skill list below as a lookup for task routing on Windows:

| Task | Skill |
|---|---|
| Broken `.venv`, Python paths, service scripts | `python-windows-project-setup` |
| Port scan / ping / DNS / HTTP probes | `networking-tools` |
| Localhost port conflicts / server launch | `localhost-management` |
| Full LAN host investigation | `windows-lan-investigator` |
| Git auth / `gh` CLI / private repo edits | `zqm-github-management` |
| Repo naming / README / cleanup | `zqm-repo-hygiene` |
| PR workflow / branch strategy | `github-pr-workflow` |
| ZQM environment entry point | `zqm-local-setup` |

## Features

- Full Windows/ZQM-patched skill snapshot
- Productivity skills for setup, LAN investigation, and repo hygiene
- GitHub management and PR workflow skills
- CLI, networking, media, research, and devops skills
- Open source skill governance via `CODE_OF_CONDUCT.md`
- Automated sync workflow via `scripts/`

## Integration: zqm-intel-platforms

This repo is part of the `zqm-intel-platforms` stack and consumed by Hermes intel, GitHub, and LAN workflows.

## License

MIT unless otherwise noted in individual skill folders.

## Contact

zqmcomputing@gmail.com

## Related Repositories

- [ZQM-Computing/hermes-agent](https://github.com/ZQM-Computing/hermes-agent) — upstream Hermes CLI runtime and mesh agent
- [ZQM-Computing/hermes-config](https://github.com/ZQM-Computing/hermes-config) — Hermes profiles, skills, and MCP server configs
- [ZQM-Computing/mesh-forensics](https://github.com/ZQM-Computing/mesh-forensics) — ZQM LAN evidence collection and incident response
- [ZQM-Computing/swarm](https://github.com/ZQM-Computing/swarm) — multi-agent mesh orchestration for distributed Hermes workloads
- [ZQM-Labs/ollama-bridge](https://github.com/ZQM-Labs/ollama-bridge) — Ollama MCP bridge for local inference
