# Garden hardcoded-secret redaction (class: scrub plaintext creds from tooling)

Use this when "improve the garden" / any audit surfaces **plaintext passwords or
tokens committed in operational scripts** (deploy-*.py, test-*.py, *.ps1). This
fleet's `garden-mesh.ps1` + `deploy-garden-keys.py` + `deep-dive-node4.py` sprayed
two shared plaintext passwords (`344SW00DL4nd!` azelenski, `EllaRose89!` zqmco/node4)
across ~9 files, one with an active password-SPRAY list. That is a CRITICAL finding
worse than an unauth service — real reusable creds at rest on the control host.

## The redaction pattern (staged, non-destructive)
1. **Scan for literals** (read-only): `search_files` content mode for
   `password\s*=\s*["']|SSH_PASS|WIN_PASS|PASS =` across the tooling dirs.
2. **Stage, don't mutate.** Generate a `.redacted` sibling for each file that
   replaces every literal with an `os.environ["<ENV>"]` lookup (one env var per
   distinct secret). Python example:
   ```python
   ENV_MAP = {"344SW00DL4nd!":"GARDEN_SSH_PASS","EllaRose89!":"NODE_WIN_PASS"}
   out = src
   for pw,env in ENV_MAP.items():
       out = out.replace(f'password="{pw}"', f'password=os.environ["{env}"]')
       out = out.replace(f'SSH_PASS = "{pw}"', f'SSH_PASS = os.environ["{env}"]')
       # also PASS= / BASE_PASS= / ALT_PASS= / WIN_PASS= variants
       out = out.replace(pw, f'<<{env}>>')  # catch any stray literal
   if 'import os' not in out: out = 'import os\n'+out
   open(f+'.redacted','w').write(out)
   # assert: sum(out.count(pw) for pw in ENV_MAP) == 0  (zero literal leak)
   ```
3. **Verify the live originals are UNTOUCHED** before claiming success:
   `grep -l "344SW00DL4nd!" deploy-garden-keys.py` should still match (literal
   present = not yet modified).
4. **`--apply` only on user go.** Overwrite originals with the `.redacted` version,
   then have the user set the env vars ONCE (user env / vault / DPAPI store — see
   `references/secure-credential-handoff.md`). The scripts keep working with no
   plaintext. NEVER print the plaintext secret back into chat during the rewrite.

## Why staged + dry-run (not inline edit)
These are the user's LIVE operational deploy scripts. A wrong in-place edit breaks
the garden mesh. The `.redacted` sibling proves zero-literal-leak (parse the output
and assert 0 occurrences) WITHOUT touching the running tool. Apply is a separate,
explicit step.

## HardRule tie-in
This is the SAME class as the audit "verify every claim" mandate, applied to
SECRETS: a `search_files` hit is PROOF of exposure (read-only, no exec), not a
suspicion. Record it as a CRITICAL finding (F62-style) + staged remediation
(Q26-style) before any file change.

## Quarantine false-positive reminder
A `quarantine\*\\deploy.ps1` with a stale `$password = "..."` is usually a Defender
false-positive on first-party tooling (see windows-host-audit §0b) — still flag it
as a plaintext secret at rest, but note it's quarantined/lower-priority than live
operational creds.

## This-session concretes (2026-07-11)
- Live `search_files` scan of `C:\Users\zqmco\Desktop\*.py` + `*.ps1` confirmed the
  two literals across ~9 files: `deploy-garden-keys.py`, `deploy-windows-keys.py`,
  `test-node4-zqmcomputing.py`, `test-node4-zqmco.py`, `deep-dive-node4.py`,
  `test-node4-users.py`, `test-node4.py`, `pivot-node4-via-node2.py` (both passwords)
  + `quarantine/CVG-CONTAMINATED-oceans4/deploy.ps1` (`*bUO0Ks7qYCw40h2`).
- `deep-dive-node4.py` holds an active 5-entry spray list
  `["EllaRose89!","EllaRose!89","ellaRose89!","ELLAROSE89!","344SW00DL4nd!"]`
  against 192.168.1.215 — recorded F63 (HIGH). Stale quarantined secret = F64 (LOW).
- Recorded F61 (garden = 12-node Synology/Noon SSH fleet, 192.168.1.32–173, user
  `azelenski`) + F62 (CRITICAL hardcoded secrets) + Q26 (redaction staged).
- Verified redactor: `redact_garden_secrets.py` (under the swarm ledger dir, e.g.
  `C:\Users\zqmco\swarm\zbit-litellm-20260711\`) — TARGETS list + ENV_MAP, dry-run
  writes `.redacted` siblings, asserts 0 literal leaks, `--apply` overwrites. This
  session staged 8 `.redacted` copies (0 leaks) and left originals untouched.
- CLARIFY-TIMEOUT: when a clarifying question times out, proceed with the SAFEST
  scoped option (stage the redaction, touch nothing live) rather than stall or
  re-ask. The owner prefers a reversible artifact over a blocked wait.
- Ledger + re-hash: after recording F61–F64/Q26, re-walk the SHA-256 claim chain
  (references/claim-chain-hashing.md).
