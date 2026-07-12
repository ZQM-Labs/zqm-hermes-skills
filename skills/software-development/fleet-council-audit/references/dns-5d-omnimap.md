# DNS Authority 5D Omnimap — artifact pattern

Produced live 2026-07-11 when the user said "omnimap" / "5d mapping" against the global
DNS-authority topic. "Omnimap" is ambiguous (no canonical DNS-authority mapper tool exists —
closest: CAIDA topology maps, OMNI-Mapping/Buckminster Fuller project). So we BUILD the map
structurally from verified numbers instead of chasing a tool.

## 5 AXES (agent-defined; confirm if user meant a specific 5D methodology)
- D1 topological  — position in DNS hierarchy (root / TLD / SLD / resolver / alt-root)
- D2 geographic   — physical + legal jurisdiction (US-heavy / regional / national / state)
- D3 governance   — who decides what's in the zone (ICANN / national / RIR / blockchain / volunteer)
- D4 security     — DNSSEC signing + validation + trust-anchor concentration
- D5 temporal     — evolutionary stage / key date

## NODE SET (8) — each grounded in references/dns-authority-investigation.md numbers
1. root_zone   — L0, 12 orgs / 2,003 inst, 10/12 US-HQ, ICANN gov, KSK-2024
2. gtld        — L1, 1,166 of 1,424 TLDs, ICANN contracts, ~1% SLD signed
3. cctld       — L1, 255 national (EXACT), sovereign, ~58% signed
4. rir         — parallel, 5 regional, RPKI
5. alt_root    — OpenNIC / .chn / Runet (fragment)
6. blockchain_dns — Namecoin / Handshake / ENS (parallel)
7. validator   — L3, ~0.6% end-to-end validation (weak link)
8. zbit_stack  — app overlay, loopback, OFF the authority tree, C2=FALSE

## ARTIFACT SHAPE (emit both)
- `dns_5d_map.json` — machine-readable: dimensions, nodes[] (each with D1–D5 + verdict),
  scorecard, bottom_line. No secrets.
- `dns_5d_map.txt` — terminal tree: indented node graph with the D1–D5 annotations inline,
  then the SCORECARD, then the 1-line BOTTOM LINE.

## WHERE IT LIVES (this session)
C:\Users\zqmco\swarm\dns_omnimap\dns_5d_map.json
C:\Users\zqmco\swarm\dns_omnimap\dns_5d_map.txt

## REUSE
Copy the JSON/txt shape; refresh the numbers from the live sources before re-emitting
(IANA root DB for TLD counts, APNIC Labs for validation %, IANA for KSK rollover date).
Overlay whatever LOCAL stack the user is investigating as node 8 (loopback, C2=egress test).
