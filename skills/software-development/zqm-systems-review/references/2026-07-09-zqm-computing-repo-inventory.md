# ZQM-Computing repo inventory snapshot — 2026-07-09

Enumerated via `gh repo list ... --limit 1000` plus per-repo content reads.
All 18 repos are private; zero open issues and zero open PRs at time of capture.

Inventory table:
- hermes-config: Python/TeX/BibTeX/HTML/Shell; SOUL, config, gateway, skills, memories, cron, sessions, kanban. 3240 blobs, ~81MB; contains runtime artifacts including screenshots, cache subdirs, and bounty outputs.
- zqm-auth: Python/TeX/BibTeX/HTML/PowerShell; largest repo, ~193MB; `instances/zqmco/state/state.db` is ~95MB and checked into git with a 3MB WAL; multiple ~4MB dogfood evidence JSON catalogs; token probes, endpoint maps, scope datasets for GitLab, Instacart, Shopify, Valve, HackerOne.
- zqm-bounty-hub: Python ~107KB; routing config `adapter-routing.json` includes a live HackerOne identifier and verified endpoint list; Bugcrowd, Intigriti, and GitLab adapters are unverified; SKILL.md enforces compliance constraints before execution.
- hermes-agent: Python/TypeScript/JavaScript/TeX/Shell ~65MB; Nous Research upstream Hermes core, CLI, gateway, TUI, plugins, providers, docker/nix, docs, website.
- wiki: Markdown/JSON only; MATRIX.md dependency/classification matrix; SCHEMA.md; entities/; index.md session snapshots.
- zqm-localhost-findings: Markdown/JSON; `findings.md` contains detailed LAN recon for `192.168.1.218` Node-1 and `192.168.1.21` Node-2 including hostnames, MAC addresses, SMB/WMI findings, local accounts, hotfixes, credential matrix metadata; `management.md` is a remote WinRM/TrustedHosts remediation playbook; `inventory.json` is a per-repo catalog.
- zqm-hermes-skills: TeX/Python/BibTeX/HTML/Shell ~2.1MB; snapshot of installed Hermes skills by category; includes office OpenXML xsd schemas and research PDF examples; contains ZQM-local additions like windows-lan-investigator.
- ZQM-AI-Council: Python/PowerShell/Batchfile/Shell ~450KB; `council_engine.py` ~342 lines; `board.json` deliberation logs; many .md investigation artifacts; `llm_client.py`; `service.py`; expected FastAPI-style entrypoint on port 8000 with Ollama backend at 11434.
- Universal-Map: small placeholder skeleton created 2026-07-07; README says populate or delete.
- hermes: meta-repo scaffold; README documents ecosystem repos and relationships.
- comfyui-setup: slim; `install-comfyui.ps1` bootstrap with FARGO branding.
- bounty-tools: README mirrors upstream naabu project text; no code files at root; README exists in 9 languages; tests/ only.
- zqm-node-02-indexer: Python/HTML/PowerShell/Batchfile/Dockerfile; Whoosh+SQLite `app.py/indexer.py/mcp_server.py`; `config.json` shows last index stats.
- dev-setup: PowerShell bootstrap; Scoop, Git, Python, Node.js toolchain.
- dotfiles: PowerShell profile + gitconfig + scoop manifest + setup.ps1.
- zqm-node-01-indexer: Python/HTML/PowerShell/Batchfile/Dockerfile; same pattern as node-02; includes `register-task.ps1` and `zqm_node_service.pyw`.
- comfy-custom: Python/GLSL/Batchfile/Mako ~9.2MB; large ComfyUI fork with tokenizers, custom nodes, server, execution/API/middleware layers; AGENTS.md and CLAUDE.md durable engineering-style guidance.
- gemini-desktop: TypeScript/JavaScript/CSS/HTML/PowerShell ~4.4MB; upstream Ben Wendell fork; Electron + Vite build; includes `install-gemini-desktop.ps1` with ZQM branding.

Local clone state at capture:
- Only `bounty-tools` is cloned locally at `C:\Users\zqmco\Documents\bounty-tools`, branch `master`, HEAD `aefcdac479`.

Recent commit themes:
- Scaffold/bootstrapping wave: `license`, `CI workflow`, `tests/`, `CODE_OF_CONDUCT`, `SECURITY`, identity signing by `Alex Zelenski, GISP <ZQMComputing@gmail.com>`.
- Active work: `zqm-auth` token-secret workflow; `comfy-custom` upstream merge stream; `gemini-desktop` ZQM install wrapper plus upstream PR merges; `zqm-localhost-findings` password redaction plus management runbook.

Evidence sources:
- GitHub: repo list, `/languages`, `/readme`, `/contents`, `/git/trees/<branch>?recursive=1`, `/commits?per_page=5`
- Local filesystem scan under `~/Documents`, `~/repos`, `~/github`
