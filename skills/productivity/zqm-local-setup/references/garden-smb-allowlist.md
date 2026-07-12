# Garden SMB logon rejected from one node but not another (per-IP allowlist)

## Symptom
`net use \\<garden-ip>\share /user:azelenski <pw>` (or `New-SmbMapping`) works from Node-1 but
FAILS from Node-3 / Node-4 with:
- "System error 1312 has occurred. A specified logon session does not exist. It may already
  have been terminated."
- or "System error 67 ... network name cannot be found" (if the UNC got mangled in transit).

## Root cause
The Synology DSM box (e.g. Garden-01 `.173`, Garden-03 `.64`) **rejects the SMB logon from the
second node's SOURCE IP** even though the same `azelenski`/password works from Node-1. This is a
**Garden-side per-client IP allowlist / host restriction**, NOT a credential error. Proven by:
- TCP 445 OPEN from the blocked node → not a network/firewall block.
- Same cred works from Node-1 (different source IP) → cred is valid.
- `admin` + same password → "network password is not correct" → confirms real auth, just wrong
  user (so the box IS doing live auth, not dropping the connection).
- Every username format (`azelenski`, `WORKGROUP\azelenski`, `GARDEN-01\azelenski`) → 1312.

## This is a GARDEN-side gate, not a node bug
The fix lives on the Synology DSM: add the node's IP to the SMB / shared-folder allowed-hosts
for the `azelenski` user (or the whole `192.168.1.0/24`). The node cannot fix it from its side.

## Note (2026-07-12 session)
Garden-02 (`.40`) and Garden-04 (`.147` TerraMaster) accepted Node-3 fine. Only Garden-01 (`.173`)
and Garden-03 (`.64`) showed the per-IP restriction. Expect the same pattern on any node whose IP
was not in the Garden's original allowlist.
