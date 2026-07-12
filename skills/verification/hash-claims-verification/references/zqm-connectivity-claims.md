# ZQM Connectivity Claim Ledger — 15 claims (recreation tier, 2026-07-12)

Reusable claim set for "verify the ZQM Node<->Garden fabric". Each claim is re-derived from LIVE
state every run; the ledger is SHA-256 over `claim_evidence.json` -> `claim_manifest.json`.

## The 15 claims (C1..C15)
C1  Node-1 has a persistent mount to Garden-01 (Z: -> \\192.168.1.173\web)          PROVEN
C2  Node-1 has a persistent mount to Garden-02 (Y: -> \\192.168.1.40\web)           PROVEN
C3  Garden-01 share is WRITABLE from Node-1 (write+read+delete probe)             PROVEN
C4  Garden-02 share is WRITABLE from Node-1                                      PROVEN
C5  Garden-03 share is WRITABLE from Node-1 (X: -> \\192.168.1.64\web)            PROVEN
C6  Garden-04 share is WRITABLE from Node-1 (W: -> \\192.168.1.144\public)        PROVEN
C7  ZQM-Garden-Link self-heal scheduled task exists on Node-1 (SYSTEM, boot+15m) PROVEN
C8  Garden-04 TerraMaster SSH reachable on .144 + .147 (protocol-aware fallback)  PROVEN
C9  Garden-01 has an HA member pair (.52/.53, MAC 90:09:D0:4B:D1:6B)              PROVEN
C10 Node-2 (.21) is OFFLINE (ping + TCP 445/22 down) — dead box                  PROVEN (down, expected)
C11 Node-3 (.46) reachable via SSH with vaulted zqmlocal cred                    PROVEN
C12 Node-4 (.215) reachable (ports open) BUT zqmlocal cred REJECTED              PROVEN (gate)
C13 ZQM-Garden-Link self-heal task registered on Node-3                           PROVEN
C14 Garden-02 + Garden-04 mount on Node-3 (Y:/W:)                                 PROVEN
C15 Topology JSON parses with `members` key (not `ips`) per garden               PROVEN

Result: 15/15 PROVEN. Manifest SHA-256: df9bcc4894b03dda62ac0c9bcd0bd4795d6c52d80ce4a1d98889563aa930053e

## Per-session/visibility traps that produced FALSE NEGATIVES during the first run
(These made a naive check report C3-C6 FALSE and C1/C7 NOT FOUND — all artifacts, not real
failures.) See SKILL.md TRAPS section for fixes.
- C1/C7 "NOT FOUND": the verify script ran non-elevated; SYSTEM tasks invisible to
  non-elevated `Get-ScheduledTask`. Self-elevate the verifier.
- C3-C6 "WRITE_FAIL": drive-letter mounts are per-session; the elevated token couldn't see
  SYSTEM's Z:/Y:/X:/W:. Re-probe the UNC path WITH the garden cred (net use \\host\share /user:).
- C15 "ips=0": topology JSON uses `members` for the IP array, not `ips`. Parse the right key.
- Python paramiko SSH reads need a channel drain or use `ssh.exe` (paramiko intermittently
  "File is not open for reading" on these hosts).

## Ledger regen recipe
1. Run the self-elevating `verify_claims.ps1` (elevated) -> writes claim_evidence.json.
2. `gen_ledger.ps1` -> claim_manifest.json with SHA-256 over the evidence blob.
3. On later runs, recompute the hash; drift = regression / tamper-evidence.
