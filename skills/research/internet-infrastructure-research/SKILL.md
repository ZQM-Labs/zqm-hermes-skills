---
name: internet-infrastructure-research
description: Research method for internet-governance / DNS-authority / RIR / DNSSEC topics. Use when the user asks about decentralization of DNS, root servers, TLDs, ccTLDs, RIRs, DNSSEC adoption, alt/sovereign roots, or maps local findings onto macro internet topology. Emphasizes authoritative live sources, exact numbers, and PROVEN/FALSE tagging. Recurring user interest — treat as first-party.
---

# Internet Infrastructure Research

## When to use
User pivots to global internet-governance topology (DNS root/TLD/RIR, DNSSEC, alt/sovereign roots) or asks for REAL NUMBERS on internet identifiers. This is a recurring, first-party interest — engage at depth, not a one-off.

## Method (non-negotiable for this user)
1. LAYER the analysis. "Decentralized" means different things per layer — always split SERVING (who answers) from GOVERNANCE (who decides what's in the zone):
   - L0 root zone (13 named / 12 orgs / anycast instances)
   - L1 TLDs (gTLD vs ccTLD)
   - number resources (5 RIRs)
   - alt/sovereign roots + blockchain DNS (parallel/fragmenting)
   - validators (the DNSSEC weak link)
2. GROUND every structural claim with a LIVE source before asserting. Prefer pulling the authoritative data file, not a blog summary.
3. REPORT EXACT figures, not estimates. If you wrote "~X", pull the authoritative count and correct it inline. User will not accept a standing approximation.
4. TAG every claim PROVEN / NOT PROVEN / FALSE with the source. Unresolved = UNRESOLVED; never fabricate.
5. For "hash claims / investigate fully" on a research product: re-verify each claim against a fresh source, persist a verdict ledger (SQLite), note any corrections vs earlier passes.

## Authoritative sources (verified live 2026-07-11)
- Root operator list + 13 named A-M / 12 orgs: https://www.iana.org/domains/root/servers
- Live instance count ("As of <date> ... N operational instances operated by the 12 independent root server operators"): https://root-servers.org
- Exact TLD count: IANA Root Zone DB https://www.iana.org/domains/root/db — grep `| .<tld> |` rows; 2-letter rows = ccTLD count.
- DNSSEC trust anchors / KSK rollover schedule: https://www.iana.org/dnssec/files
- DNSSEC validation %: Cloudflare Radar (technologychecker.io/blog/dnssec-adoption) — end-to-end ~0.6% (May 2026); resolver validation 31.5% global / 45.3% EU (JRC/EU Commission).
- RIRs: https://www.nro.net (+ APNIC/RIPE/LACNIC/ARIN/AFRINIC). RPKI = BGP integrity analog to DNSSEC.
- ICANN/NTIA transition: https://www.iana.org/help/pti-transition ; ICANN 2016-10-01 announcement.

## Baseline verified numbers (2026-07-11) — see references/dns_authority_baseline.md
- Root: 13 named / 12 orgs; 10/12 US-HQ; 2003 anycast instances; ICANN/IANA/PTI multistakeholder since 2016-10-01 (US-control FALSE); root signed 2010; KSK-2024 rollover 2026-10-11.
- TLDs: 1,424 total; 1,166 gTLD; 255 ccTLD (EXACT).
- RIRs: 5 (ARIN/RIPE NCC/APNIC/LACNIC/AFRINIC).
- DNSSEC: ~31.5% resolver validation; ~0.6% end-to-end; fails open; .de outage 2026-05-05 proof.

## Common claims → verdicts
- "US controls the DNS root" → FALSE (NTIA contract ended 2016-10-01).
- "US orgs operate most root servers" → PROVEN (10/12 US-HQ) — distinct from control.
- "DNS fully decentralized" → FALSE (one root by design).
- "Blockchain DNS replaced ICANN" → FALSE (parallel, low adoption).
- "DNSSEC makes DNS decentralized" → FALSE (locks the single root; integrity not distribution).
- "Single global DNS is the only DNS" → FALSE (OpenNIC/.chn/Runet alt roots exist) but "IANA root dominates" = PROVEN.

## Pitfalls
- Don't conflate root OPERATOR HQ nationality with root CONTROL. Post-2016 control = global multistakeholder, not US gov.
- Alt/sovereign roots fragment the namespace; parallel, not replacements.
- ccTLD signing % drifts — re-pull; don't reuse stale (~58% was 2022 APNIC).
- Coined verbs ("omnimap", "5d mapping"): define the framing autonomously, flag the assumption, proceed. User expects autonomous expansion, not clarification.
