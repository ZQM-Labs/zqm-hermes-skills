# Genesis / Source-Hygiene Deep-Dive (read-only)

Use when the user says "genesis", "investigate <agent module>", or wants a
borrowed/first-party agent's source judged for security hygiene + provenance.
Companion to `artifact-provenance-review` (provenance) and `codebase-truth-audit`
(claims-true). This note records the concrete 2026-07-11 ZQM pass so future
agents don't re-derive it.

## What "genesis" meant here
`ZBit_api/ZBit_runtime/modules/qseal_recruitment.py` defines
`broadcast_recruitment()` — sends a fixed "genesis_recruitment" JSON message
(worldbuilding lore: "Genesis is energy. The half is found." + pseudo-physics
"laws" + "Per Ardua ad Astra") over UDP to:
  - 239.255.42.99:4299 / 239.255.42.100:42100 (private multicast)
  - 224.0.0.251:5353 (mDNS)
  - 255.255.255.255:4299 (broadcast)
`beacon.py` LANBeacon does the same for node-announce (every 5s, multicast
239.255.42.99:4299). Signing uses a hardcoded shared `INVARIANT` (SHA3-512
HMAC-style self-sign) present in 5 files.

## Egress classification = BENIGN (LAN self-promotion, not C2/exfil)
Evidence chain that proved it (all read-only):
1. `broadcast_recruitment()` fires ONLY under `if __name__=="__main__"` (module CLI).
   Grep the tree: no `import qseal` / `broadcast_recruitment()` call from any
   service path. `ZBit_runtime/__init__.py` RE-IMPLEMENTED the qseal_* logic with
   the real `cryptography` lib (Ed25519) and does NOT import the original's broadcast.
2. `app.py` only calls `beacon.py discover` (read-only scan) behind `_check_key`
   (X-Api-Key). No daemon auto-fires the UDP recruitment.
3. Content is fixed-string lore — no executable, no URL/callback, no encoded payload,
   no file/cred in the datagram.
=> INERT unless manually run. No remediation needed for safety.

## Hygiene flags the user actually cares about (the real ask)
- **INVARIANT symmetric shared secret** (forgeable signatures): hardcoded identical
  96-hex string in beacon.py / qseal_recruitment.py / hive_base.py / forensic_expand.py
  / app.py. Anyone with the source can forge "genesis" signatures. Fix = per-node
  Ed25519 (the `cryptography` Ed25519 machinery already exists in __init__.py for
  qseal_* — reuse it). Low priority.
- **FOREIGN-USER hardcoded paths** (provenance tell + minor info-leak):
  - hive_base.py:33   `DATA_DIR = C:/Users/AlexZelenski/Documents/FamilyHive`
  - forensic_expand.py:33  `CHAIN_FILE = C:/Users/AlexZelenski/Desktop/forensic-ledger-data/chain.json`
  Indicates code BORROWED from another dev's workstation. Dead on N1 (paths don't
  exist) but a hygiene flag — fix = relative/`Path.home()` config. NOTE: a 3rd
  "Alex Z" grep hit in venv/pygments AUTHORS is a FALSE POSITIVE; exclude it.
- **LAN scan noise**: `beacon.scan_lan()` loops `for i in range(1,255)` doing
  `connect_ex((ip,443))` across 192.168.*.0/24 (no auth, pure SYN probe). Reachable
  live via :8400 /v1/mesh/scan behind X-Api-Key. Fix = scope to fleet /24 (192.168.1.0/24)
  + opt-in flag.

## Recording
Write findings as F-IDs (INFO/LOW) with the read-only evidence string, then RE-HASH
the claim chain (see SKILL.md "Tamper-evident CLAIM CHAIN" + EXACT re-hash algorithm).
For this pass: F37 (genesis=benign LAN promo), F38 (INVARIANT shared secret),
F39 (broadcast not auto-invoked), F40 (scan_lan noise), F41 (foreign-user paths),
F42 (genesis content = benign worldbuilding).
