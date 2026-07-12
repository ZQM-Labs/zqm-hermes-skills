# Coined verbs → method map (ZQM fleet audits)

The ZQM user issues terse coined verbs. Expand each into a defined method on first
use and state the framing + any assumption. Do NOT re-ask for clarification on these.

## diagnostics
Read-only LIVE re-probe of every flagged finding + an ESTABLISHED-connection hunt.
- Re-run the original probe (port connect, service banner, auth test) to confirm the
  finding is still live, not stale.
- Hunt ACTIVE sessions: `netstat -ano | grep ESTABLISHED` filtered to the exposed ports
  (11434/4001/8400/5985/445/135/6379). Flag any peer that is neither loopback
  (127.x) nor a known fleet IP (192.168.1.218/21/46/215) nor a known external endpoint
  as `*** ANOMALOUS REMOTE ***`.
- CRITICAL DISTINCTION to report explicitly:
    • ACTIVE anomalous activity  = intrusion/beacon/exfil riding a port RIGHT NOW.
    • CONFIG-LEVEL exposure      = open unauth service with ZERO live sessions.
  "Exposed" ≠ "invaded". Always state both: which findings are still open vs which have
  an active session on them. If none active → "no active anomaly, only config-level exposure."

## genesis
Root-cause trace of each finding. Split every item into:
- BY-DESIGN  = intended, serves the architecture.
    e.g. Ollama :11434 LAN-exposed on N1/N2/N4 = the ZBit fleet inference fabric.
    Evidence: ZBit config.yaml enumerates N1/N2/N4:11434 (LAN) + N3:127.0.0.1 (localhost);
    litellm_config.yaml comment "secure LB fabric … open nodes N2/N3 live".
    Remediation: add auth at a proxy, do NOT yank the LAN bind (that breaks the mesh).
- ACCIDENTAL = default drift / setup omission, no intent.
    e.g. N2 Redis :6379 unauth = no `requirepass` + non-loopback bind. Redis protected-mode
    only guards you when left unbound+no-pass; setting `bind 0.0.0.0` without a password
    drops the guard. This is the ONLY true mistake in the fleet.
    Remediation: close it (the urgent one).
- PARTIAL = framework/OS default, low urgency due to loopback.
    e.g. N1:4001 LiteLLM open/unkeyed (no master_key) — loopback-only; N1:8400 ZBit open
    docs (FastAPI default) — loopback-only, /v1/* key-gated; :5985 WinRM-HTTP = OS default.
This split drives remediation priority: fix ACCIDENTAL first, auth-proxy the BY-DESIGN.

## investigate all possibilities
For a finding's remediation, enumerate EVERY vector; prove each with evidence:
  VIABLE          = works now (e.g. operator self-runs the staged script on the node).
  VIABLE-BLOCKED  = correct path, needs a missing input (e.g. WinRM open + in TrustedHosts
                    but needs per-node break-glass cred). State the exact blocker.
  DEAD            = proven unreachable (SSH/RDP filtered; no mesh foot; no cached cred;
                    no fleet cred in agent config).
  REJECT          = a "fix" that is actually the vulnerability or non-durable
                    (e.g. "configure Redis via the unauth channel" = the RCE itself,
                     non-persistent across restart).
Never stop at the first blocked path — show the full matrix.

## hash claims
Persist every load-bearing claim to SQLite with a SHA-256 (or truncated) hash, a
PROVEN / NOT PROVEN / FALSE / UNRESOLVED status, the evidence source, and a re-verify
date. Re-derive from live output; never fabricate. Unresolved stays UNRESOLVED.

## github community review / omnimap / 5d mapping
These are ambiguous coined verbs — CLARIFY or define a framing and flag the assumption.
- "github community review": options = (a) push audit artifacts to GitHub for peer review,
  (b) do a GitHub-PR-style code/security review of the stack, (c) open a PR with new
  skills. NEVER `git add .` in the ZQM-Computing/hermes repo (SECRETS in tree).
- "omnimap": no canonical DNS-authority mapper product exists; build the map structurally
  (root→TLD→ccTLD→RIR→alt/blockchain) from proven numbers. Closest real tools: CAIDA
  topology maps, OMNI-Mapping (Buckminster Fuller) project.
- "5d mapping": define the 5 axes (suggested: topological / geographic / governance /
  security / temporal) and flag if the user meant a specific framework.

## Remediation gating reframe (behavioral)
When the investigation is COMPLETE but an optional APPLY is blocked on a per-node
break-glass credential, do NOT validate "dead in the water / stuck" framing.
- DELIVERABLE COMPLETE: ledger + claim-hash + genesis persisted. That IS the product.
- APPLY BLOCKED: state the 1–2 real doors:
    (1) user self-runs staged script on the node (secret never crosses wire) — preferred;
    (2) user hands the per-session break-glass → agent runs `-WhatIf` first, then applies
        + verifies + closes the finding.
- Per-node passwords DIFFER (N2 ≠ N4 ≠ others); one wrong guess proves it — do NOT re-loop.
