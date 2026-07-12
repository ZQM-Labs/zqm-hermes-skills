# Sensitive Data Handling for ZQM-Computing Repos

## Verified sensitive artifacts (2026-07-09)

| Repo | File | Finding | Severity | Action taken |
|------|------|---------|----------|--------------|
| zqm-localhost-findings | findings.md | Live LAN recon: hostnames, OS builds, MACs, SMB/RPC surface, local accounts, ZeroLogon providershots, KDC exposure for Node-1 (192.168.1.218) and Node-2 (192.168.1.21) | CRITICAL | Plaintext password replaced with [REDACTED] in markdown output; omit full recon from reports |
| zqm-localhost-findings | management.md | Remote management playbook (WinRM, TrustedHosts, credential passthrough, WMI) | CRITICAL | Do not expose playbook steps verbatim |
| zqm-auth | instances/zqmco/state/state.db | ~95MB SQLite runtime state DB committed into git history (~95MB binary) | HIGH | Flag in reports; do not download/execute |
| zqm-bounty-hub | adapter-routing.json | HackerOne token identifier "zqm-computing" with 15 verified endpoints | MEDIUM | Mention identifier exists; omit endpoint list and token details from reports |
| zqm-hermes-skills | history-purge.md | Literal password reference in history | MEDIUM | Confirmed REDACTED in latest commit |
| dev-setup | bootstrap.ps1 | Downloads and executes remote unsigned PowerShell via Net.WebClient | MEDIUM | Flag fetch source; omit exact URL if possible |

## Redaction rules

- Replace plaintext passwords with [REDACTED]
- Replace commit emails with [REDACTED]
- Replace API keys/tokens/token_identifier_value references with [REDACTED]
- Omit endpoint lists that could enable unauthorized access
- Omit MAC addresses, host credential tables, ZeroLogon evidence details

## What is safe to report

- File paths, sizes, SHAs, commit SHAs, authors (name only), dates
- Presence/absence of sensitive patterns ("contains REDACTED marker: True")
- Token identifier existence without value disclosure
- Code-signing cert fingerprint (public info)
- Service UP/DOWN state without auth details