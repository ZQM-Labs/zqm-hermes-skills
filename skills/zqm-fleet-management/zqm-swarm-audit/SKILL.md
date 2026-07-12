---
name: zqm-swarm-audit
description: "Verification of claims about the ZQM environment — read-only repo audits (garden redaction, repo secret-free, Genesis patch presence+compile, backup integrity) AND the standing 'hash claims' / 'verify claims' directive: re-derive every claim from LIVE state and persist a tamper-evident SHA-256 ledger. Use for COUNCIL / SECRETS / GARDEN / GENESIS audits and any 'verify claims' task that ends with 'Report verdicts + evidence.'"
---

# ZQM Swarm Audit — Read-Only Claim Verification

Use this skill when asked to verify claims about the ZQM swarm audit repository
(`swarm/zbit-litellm-<date>/` on the Windows host) — typically phrased as a
"COUNCIL-N SECRETS/GARDEN" or "verify Q26 / Genesis Q17-19" style task that ends
with "Report verdicts + evidence." These are **read-only** recon audits: inspect,
grep, compile — never edit, never source credentials.

## Standard 4-claim verification pattern

A council security/secret audit usually decomposes into these independent claims.
Verify each and report a PASS/FAIL verdict with concrete evidence.

1. **Garden redaction — 0 literal leaks.** The live garden scripts (typically on
   `Desktop/`, e.g. `deploy-garden-keys.py`, `deploy-windows-keys.py`,
   `pivot-node4-via-node2.py`, `test-node4*.py`, `deep-dive-node4.py`,
   `garden-mesh.ps1`) must read secrets from `os.environ[...]`, never inline
   literals.
2. **Repo secret-free.** The audit repo itself (`.py`, `.yaml`, `.ps1`, `.md`,
   `.json`) must contain no stray literal creds (API keys, `sk-…`, plaintext
   `password=`).
3. **Genesis patches present + compile.** The 4 Genesis modules
   (`beacon.py`, `qseal_recruitment.py`, `hive_base.py`, `forensic_expand.py`
   under `ZBit_api/ZBit_runtime/modules/`) must carry their Q17/Q18/Q19 markers
   AND `python -m py_compile` cleanly.
4. **Backups intact.** The `garden_backup_<ts>/` and `genesis_backup_<ts>/`
   directories must exist and hold the original (pre-redaction) files.

## Tool sequence (fast, parallelizable)

- `mcp_filesystem_directory_tree` (exclude `.git`, `__pycache__`) to map the repo
  and confirm backup dirs exist.
- `search_files` with `target=content` regex to grep for literal leaks — run the
  repo-wide scan and the live-script scan in the same turn (independent).
- `terminal`: `cd <modules dir> && python -m py_compile beacon.py qseal_recruitment.py hive_base.py forensic_expand.py && echo COMPILE_OK` — one command, single PASS/FAIL signal.
- For full file reads use `read_file` (NOT cat/head).

### Regex recipes (see references/verify-recipe.md)

### Live LAN recon support files
- references/network-recon.md — command sequence, device fingerprint tells, OUI table, drift classification.
- scripts/sa_probe.py — full threaded discovery + HTTP/SSH/NetBIOS/OUI fingerprint.
- scripts/sa_reconcile.py — re-scans DB-recorded ports, classifies MATCH/DRIFT/UNVERIFIABLE.
- Literal leak in live scripts: `(pass|cred|pwd|password)\s*=\s*["'][^"']+["']`
- Inline secret scan repo-wide: `sk-[A-Za-z0-9]{10,}|password\s*=\s*["'][^"']+["']|api_key\s*=\s*["'][^"']{8,}["']`
- Patch markers: `Ed25519` (Q17/F38), `/24` + `FLEET_SUBNET` (Q18/F40), `Path.home()` (Q19/F41).

## Pitfalls (read these before reporting)

- **Backup dirs intentionally hold plaintext originals.** The `garden_backup_*/`
  dir contains the un-redacted scripts with real passwords (e.g. `BASE_PASS="EllaRose89!"`).
  This is EXPECTED for reversibility — do NOT flag backup-dir literals as a leak.
  A leak is only counted in the *live redacted* scripts and the audit repo proper.
- **`redact_garden_secrets.py` is a false positive.** Its body contains
  `out.replace(f'password="{pw}"', ...)` — that's remediation code, not a leak.
  Exclude the redactor script itself from the "secret-free" verdict.
- **Exclude unrelated tool dirs.** `Desktop/john/` (john the ripper) matches
  `password =` in code comments — not a leak. Scope greps to the relevant files
  with `file_glob` or targeted paths.
- **`.git` / `__pycache__` noise.** Exclude them in directory_tree; don't grep
  `.pyc` (compiled) or `.git` objects for "secrets" — stale/duplicate content.
- **Redaction is env-var indirection, not removal.** Verified by confirming
  `os.environ["NODE_WIN_PASS"|"GARDEN_SSH_PASS"]` replaces every literal. Count
  `os.environ[` lookups to prove completeness.

## RECREATION + tamper-evident ledger (the "hash claims" method)
The standing user directive "hash claims" / "verify claims" / "investigate fully"
means: re-derive EVERY claim from LIVE state and persist a tamper-evident
SHA-256 record. Do NOT trust prior logs or the agent's own earlier output.
This caught real drift on 2026-07-12: a verify run reported 4 claims
FALSE that were actually verification ARTIFACTS (non-admin couldn't see SYSTEM
tasks; UNC writes failed cross-session), not real fabric failures. After
correction, 15/15 were PROVEN.

Recreation procedure:
1. For each claim, write a probe that re-establishes it from scratch against
   live state (fresh Get-ScheduledTask, fresh net use, fresh SSH/WinRM,
   fresh topology read). Never cite a prior session's log as proof.
2. Distingish VERIFICATION-ARTIFACT from REAL failure BEFORE flagging FALSE.
   Two artifact classes burn cycles if unknown:
   - SYSTEM-owned scheduled tasks are INVISIBLE to a non-elevated
     Get-ScheduledTask (returns "NOT FOUND" even though the task exists and
     ran result 0). FIX: self-elevate the verifier
     (Start-Process powershell -Verb RunAs -File $PSCommandPath) or check the
     task from an elevated context. A "task missing" claim is unproven until
     checked elevated.
   - Drive-letter mounts AND bare UNC writes are PER-SESSION. A drive
     mapped by SYSTEM (or any other logon token) is not visible to your
     session; a bare \\host\share write with no cached cred is DENIED even
     though the share is reachable + writable in the session that holds the
     cred. FIX: prove writability the way the self-heal task does it — mount
     the UNC WITH the stored cred (net use \\host\share /user:<cred> <pw>),
     write+read a probe file, then /delete. That is the authoritative test.
3. Persist a tamper-evident ledger:
   - Emit claim_evidence.json (array of {id, statement, observed, status,
     evidence}) with status in {PROVEN, FALSE, NOT PROVEN}.
   - Compute SHA256(claim_evidence.json) and write claim_manifest.json with
     {generated, generated_by, evidence_sha256, claim_count, proven,
     false, not_proven, claims[]}. Recompute the hash on every re-run; a
     mismatch vs a stored manifest = tamper/drift evidence. Re-run after any
     claimed state change and re-flag drift.
   - Reusable harness: scripts/verify_claims_harness.ps1 (self-elevating
     recreation template + SHA-256 ledger emit). Copy it and fill the
     per-claim probe block.

PITFALL — do not convert a verification artifact into a FALSE claim. If a
probe returns negative, ask "would this negative also occur in a healthy
system due to session/visibility context?" and re-verify with the
authoritative method (elevated read, cred-supplied UNC, fresh
connection) before recording FALSE.

## Live network / endpoint reconciliation (the "full SA" pattern)

When "verify claims" spans the live LAN (not just repo state), extend the
recreation method with an actual network probe and reconcile it against the
recorded `fleet_endpoint_audit.db`. This is what a "full api driven situational
awareness" / "arp the network" task needs. Pattern proven 2026-07-12:

1. **Capture ARP** (`arp -a`) + interfaces (`ipconfig`) to see what's actually
   on the wire from the probe host. Cross-reference against the known fleet
   map (Node-1 .218, Node-2 .21, Node-3 .46, Node-4 .215, Garden .144).
   Any fleet node MISSING from ARP + not answering ping = DOWN (host absent,
   NOT config drift).
2. **Port discovery** — threaded TCP connect-scan a curated port list per live
   host (socket.connect_ex with short timeout ~0.35s; parallel threads). See
   scripts/sa_probe.py (full discovery: HTTP/HTTPS fingerprint via urllib +
   ssl CERT_NONE, SSH banner grab, NetBIOS via `nbtstat -A`, OUI vendor lookup).
3. **Fingerprint open services** — for web ports grab status + `Server:` +
   `<title>`; for :22 grab the SSH banner (OpenSSH-for-Windows vs dropbear vs
   ASUSWRT httpd/3.0 are strong device tells). Reused OUI table + macvendors.com
   fallback (rate-limited — space requests 3-4s apart or you get 429).
4. **Reconcile vs the audit DB** — DO NOT infer from your own scan. Re-read the
   DB's recorded `endpoints`/`nodes` tables and re-scan EACH recorded port live
   to classify MATCH / DRIFT-OPEN (new exposure) / DRIFT-CLOSED (removed) /
   UNVERIFIABLE (host down). See scripts/sa_reconcile.py. This makes every
   endpoint claim PROVEN/FALSE/NOT PROVEN with a live socket result, not a
   guess. 2026-07-12 result: 35 recorded fleet ports re-scanned, DRIFT=0 on
   all live nodes, N2 (down) left its CRITICAL claims NOT PROVEN (evidence gap,
   not contradiction) → ledger Q4 correctly stays OPEN.
5. **Report classified + quantified** — group into named classes (Fleet-state /
   Reconciled-claims / Perimeter / Exposure / New-drift), give per-class counts
   + TOTAL, and surface OPEN ledger items explicitly. Label every claim
   PROVEN / NOT PROVEN / FALSE.

### Pitfalls specific to LAN recon
- **arp -a only shows recently-talked hosts.** A device that hasn't exchanged
  packets with the probe host won't appear. If you need a true /24 inventory,
  run a ping sweep (icmp) or full TCP scan first to populate ARP.
- **macvendors.com 429s** on rapid sequential calls — space them or use an
  embedded OUI table for known fleet MACs.
- **nbtstat -A returns nothing for non-Windows / NetBIOS-off devices** — normal,
  not a failure. Fall back to HTTP banner / SSH banner / OUI.
- **A host DOWN ≠ port closed.** Distinguish "RST from a live host on a
  filtered port" (closed/filtered) from "no host at all" (every port closed
  because the box is dark). The latter makes CRITICAL claims UNVERIFIABLE, not
  FALSE — keep the ledger item OPEN pending host recovery (e.g. WoL on Node-2).
- **HTTP fingerprinting needs CERT_NONE for self-signed gear** (ASUS/TerraMaster/
  Synology all serve self-signed TLS on :443/:8443) — wrap urlopen in
  `ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE`.
- **curl on the git-bash terminal works for HTTP headers** (`curl -sI`), but
  Python urllib is more controllable for TLS + banner + threading in one pass.

### Continuous watchdogs (Hermes cron, both read-only, both local-deliver)

Two independent 15-minute monitors now run against the fleet. They write to
DIFFERENT tables in `swarm/fleet_endpoint_review/fleet_endpoint_audit.db` so
neither clobbers the other's ledger.

1. **Hash-drift monitor** — job `d7db290059f7` → runs `hash_drift_check.py`.
   Re-probes the 7 hashable claims (N2 Redis unauth, N1/N2/N4 Ollama, N1
   LiteLLM/ZBit, active anomalous sessions) and writes STABLE/DRIFT counts to
   `hash_drift_log`. Catches CLAIM-ledger drift (a recorded fact no longer true).

2. **Reachability watchdog** — job `2bc934334939` → runs
   `scripts/sa_watchdog.py`. Probes the 4 nodes + critical ports (22/135/139/
   445/5985/5986/6379/11434) and appends a reachability row to
   `sa_watchdog_log`, tracking a last-state signature in `sa_watchdog_state`.
   Prints ONLY on a state change (node up/down, Ollama/Redis port flip); silent
   when stable (watchdog pattern → quiet cron). Catches INFRA drift (a box went
   dark, a port opened/closed) independent of the claim ledger. This closes
   open-question Q7 (mesh/scan fidelity — inventory was 443-only, missing the
   AI/Redis fleet).

Both together give: claim-drift (does the recorded truth still hold?) +
reachability-drift (did the physical/logical topology move?). N2 being DOWN is
now auto-tracked by the watchdog; when N2 returns, the watchdog will flag the
state change and Q4's Redis claim can finally be re-verified live.

Reusable harnesses: scripts/sa_probe.py (discovery), scripts/sa_reconcile.py
(DB-port reconciliation), scripts/sa_watchdog.py (continuous reachability
watchdog). Copy + adjust host/port lists. Condensed recipe and device-
fingerprint tells in references/network-recon.md.

Operational detail for adding/extending monitors (separate-DB-table rule,
silent-when-stable watchdog pattern, verify-after-create, DB-inspection query):
references/fleet-monitoring-ops.md.

## Evidence format
Report each claim as a one-line verdict + the concrete evidence (grep hit count,
`COMPILE_OK`, backup file list). End with an overall `N/N PASS` line. Keep it
terse: verdict table, no narration. Example shape from the July-11 run:

```
CLAIM 1 Garden Q26 redaction 0 leaks | PASS  (19 os.environ lookups, 0 literal assigns)
CLAIM 2 Repo secret-free          | PASS  (hits only in backup dir + redactor code)
CLAIM 3 Genesis Q17-19 + compile  | PASS  (COMPILE_OK; Ed25519/Path.home markers present)
CLAIM 4 Backups intact            | PASS  (garden_backup_*, genesis_backup_* present, originals inside)
Overall: 4/4 PASS.
```

## Scope guard

Read-only only. Do not edit scripts, do not set/echo the secrets, do not commit.
If you find a *live* (non-backup) literal credential, report it as a FAIL with the
path:line — do not "fix" it silently.
