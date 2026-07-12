# DNS Authority 5D Omnimap (reference)

Reusable deliverable shape when the user asks about "the global decentralization of
DNS", "omnimap", "5d mapping", or any "is DNS centralized / US-controlled?" question.
Built live 2026-07-11; grounded in PROVEN figures.

## The 5 axes (agent-defined — "5d mapping" is ambiguous; own the framing)
- D1 topological : position in DNS hierarchy (root / TLD / SLD / resolver / alt-root)
- D2 geographic  : physical + legal jurisdiction (US-heavy / regional / national / state)
- D3 governance  : who decides what's in the zone (ICANN / national / RIR / blockchain / volunteer)
- D4 security    : DNSSEC signing + validation + trust-anchor concentration
- D5 temporal    : evolutionary stage / key date (e.g. 2016 NTIA transition, 2025/26 KSK)

NOTE: "Omnimap" is NOT a canonical DNS tool. Closest real things: CAIDA internet
topology maps, the OMNI-Mapping (Buckminster Fuller Institute) project, arXiv "OmniMap"
(3D scene mapping — unrelated). When the user says "omnimap", build the map
STRUCTURALLY from verified data; don't hunt for a product.

## The 8 nodes (each with D1–D5)
1. root_zone     — L0, 13 named / 12 orgs / 2003 anycast inst, 10/12 US-HQ, ICANN gov,
                    KSK-2024 rolling. Single trust anchor.
2. gtld          — L1, 1166 TLDs (1151 generic + 14 sponsored + 1 infra .arpa), ICANN
                    contracts, ~1% SLD signing.
3. cctld         — L1, 255 national (ISO 3166-1 alpha-2, EXACT IANA count), sovereign.
4. rir           — parallel, 5 orgs (ARIN/RIPE/APNIC/LACNIC/AFRINIC), RPKI.
5. alt_root      — OpenNIC / China .chn / Russia Runet(2019). Fragment the namespace.
6. blockchain_dns— Namecoin/Handshake/ENS. Parallel, low adoption.
7. validator     — L3, ~31% global / 45% EU validation, ~0.6% end-to-end. Weak link.
8. zbit_stack    — app overlay on ZQM-NODE-1, loopback, OFF the authority tree, C2=FALSE.

## Scorecard (verbatim, live-verified)
  root serving      DECENTRALIZED (2003 inst / 12 orgs)
  root governance   CENTRALIZED (1 root file, ICANN multistake)
  root operator HQ  US-HEAVY (10/12 US-HQ)
  gTLD authority    CENTRALIZED (ICANN + 1166 registries)
  ccTLD authority   DECENTRALIZED (255 national NICs, EXACT)
  IP/ASN authority  DECENTRALIZED (5 regional RIRs)
  alt/blockchain    FRAGMENTED (parallel)
  DNSSEC validation WEAK (0.6% end-to-end)

## Bottom line
HYBRID. Edges (255 ccTLDs, 5 RIRs) decentralized; apex (1 root, ICANN, root KSK)
centralized. "Fully decentralized" = FALSE. "US-controlled" = FALSE since 2016-10-01.
"US orgs run most root instances" = PROVEN (10/12). DNSSEC locks (not decentralizes)
the single root.

## Artifact template
Emit two files: `<dir>/dns_5d_map.json` (machine-readable, per-node D1–D5 + verdict)
and `<dir>/dns_5d_map.txt` (terminal tree). Then run the "hash claims" verb over the
numeric claims (see hashed-claim-manifest.md) to tag each PROVEN/NOT PROVEN/FALSE.

## Re-usable live probes (re-verify before each render)
- Root instance count + 12 orgs: `https://root-servers.org` (header line, dated).
- Root operator list: `https://www.iana.org/domains/root/servers`.
- TLD counts (EXACT): cache `https://www.iana.org/domains/root/db`, grep
  `^\| \[\.[a-z0-9-]+\]` (total) and `^\| \[\.[a-z]{2}\]` (ccTLD).
- DNSSEC trust anchors / KSK rollover dates: `https://www.iana.org/dnssec/files`.
- Validator %: APNIC Labs `stats.labs.apnic.net/dnssec` + Cloudflare Radar May-2026
  end-to-end ~0.6%.
