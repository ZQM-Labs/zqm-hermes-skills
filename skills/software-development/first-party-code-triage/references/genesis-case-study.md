# Genesis Case Study — ZQM first-party code triage (2026-07-11)

## The ask
User: "hash claims investigate genesis" — investigate the `genesis` broadcast
mechanism flagged earlier as F29/F30 (ZBit `qseal_recruitment.py`).

## Files read (read-only)
- `ZBit_api/ZBit_runtime/modules/qseal_recruitment.py` (161 lines)
- `ZBit_api/ZBit_runtime/modules/beacon.py` (289 lines)
- `ZBit_api/ZBit_runtime/modules/hive_base.py` (partial, 710 lines)
- `ZBit_api/ZBit_runtime/__init__.py`
- `ZBit_api/app.py`

## What "genesis" actually is
`qseal_recruitment.broadcast_recruitment()` sends a UDP datagram carrying a
fixed `RECRUITMENT_MESSAGE` ("Genesis is energy. The half is found." + pseudo
"physics laws" + "Per Ardua ad Astra") to:
- `239.255.42.99:4299` / `239.255.42.100:42100` (private multicast)
- `224.0.0.251:5353` (mDNS)
- `255.255.255.255:4299` (broadcast)
`beacon.py` LANBeacon does the same for node-announce every 5s
(multicast `239.255.42.99:4299`). Signing uses a hardcoded shared `INVARIANT`
(SHA3-512 HMAC-style self-sign).

## Triage verdict: BENIGN LAN SELF-PROMOTION — NOT C2, NOT EXFIL
Proofs (file:line):
- qseal_recruitment.py:102-129 `broadcast_recruitment()` — only UDP send of a
  fixed string; NO file/cred read, NO TCP, NO foreign IP.
- qseal_recruitment.py:131 `if __name__ == '__main__':` — broadcast only runs
  under manual CLI, NOT imported/auto-invoked.
- ZBit_runtime/__init__.py — "re-implemented here with the real `cryptography`
  lib instead of importing the broken originals"; qseal_* re-done with Ed25519,
  original broadcast NOT wired in.
- app.py — only calls `beacon.py discover` (read-only scan) behind X-Api-Key.
- hive_base.py:33 — hardcoded `C:/Users/AlexZelenski/Documents/FamilyHive`
  (foreign-user path) = copied code, non-existent on N1 → hygiene flag, not active.
- Content = fixed worldbuilding (matches the agent's own CVG lore KB in
  `quarantine/CVG-CONTAMINATED-*`, which is benign Defender FP).

## Egress classification (rubric applied)
1. Transport: UDP multicast/broadcast, LAN-only → low-signal.
2. Payload: fixed lore string → no data harvest.
3. Auto-invoked: NO (`__main__` guard only).
4. Credential touch: NO real creds; INVARIANT is symmetric self-sign only.
5. Exfil path: NONE.
6. Foreign-user paths: present (AlexZelenski) → hygiene flag.

## Findings recorded (ledger F37-F42)
- F37 genesis = LAN UDP-multicast self-promo, not C2/exfil (INFO, PROVEN)
- F38 hardcoded INVARIANT shared secret across modules (LOW)
- F39 qseal broadcast NOT auto-invoked → inert at runtime (INFO)
- F40 beacon.scan_lan() TCP-scans 192.168.*.0/24:443 (LOW)
- F41 foreign-user hardcoded paths in hive_base/forensic (LOW)
- F42 genesis content = first-party worldbuilding, benign (INFO)

## Reusable takeaways for future triage
- A module DEFINING a send function is harmless unless imported-and-run by a
  daemon. Always check `__main__` guards + import graph before alarming.
- Scary vocabulary ("genesis", "recruitment", "beacon") in first-party agent
  code is usually worldbuilding, not malice — judge by transport+payload+auto-
  invocation, not by the words.
- Symmetric INVARIANT self-signing = forgeable but benign; recommend asymmetric
  per-node keys as optional hardening, never as "compromised".
