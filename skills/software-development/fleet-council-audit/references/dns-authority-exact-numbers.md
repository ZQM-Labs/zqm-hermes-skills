# DNS Authority — EXACT VERIFIED NUMBERS (companion to dns-authority-investigation.md)

Enrichment pulled live 2026-07-11 so the three-layer decentralization story carries precise
figures, not "~200+". Loaded as a separate file because the parent reference is write-gated;
both live under fleet-council-audit/references/.

## ROOT ZONE (LAYER 1)
- 13 named authorities (A–M), **12 independent operators**, **2,003 operational anycast instances**
  (root-servers.org, 2026-07-06).
- Operators + HQ: Verisign(A,J) US · USC-ISI(B) US · Cogent(C) US · U.Maryland(D) US · NASA(E) US ·
  ISC(F) US · US DoD NIC(G) US · US Army ARL(H) US · Netnod(I) SE · RIPE NCC(K) NL · ICANN(L) US ·
  WIDE(M) JP. → **10 of 12 US-headquartered**.
- Governance: IANA/PTI (ICANN affiliate), multistakeholder, NO gov veto.
- **NTIA stewardship transition 2016-10-01** → "US-controlled" = FALSE since then.

## TLD LAYER (LAYER 2) — EXACT IANA COUNT (2026-07-11)
- **Total delegated TLDs = 1,424**: gTLD generic 1,151 · ccTLD 255 (EXACT) · sponsored 14 ·
  infrastructure 1 (.arpa).
- FETCH: web_extract `https://www.iana.org/domains/root/db`, count rows `| .xxx |`; 2-letter via
  `grep -E '^\| \[\.[a-z]{2}\]'`. (Old `data.iana.org/root/tlds-alpha-by-domain.txt` now 404s.)
- gTLD = CENTRALIZED (ICANN registry contracts). ccTLD = MOST DECENTRALIZED (255 national NICs).
- Top ccTLDs (DNIB Q1 2025): .cn .de .uk .ru .nl .br .au .fr .in .eu.

## NUMBER RESOURCES (LAYER 3)
- **5 RIRs**: ARIN(NA) · RIPE NCC(EU/ME/CAsia) · APNIC(AP) · LACNIC(LatAm/Carib) · AFRINIC(Africa).
  Regionally autonomous; RPKI = BGP's DNSSEC analog.

## DNSSEC — SIGNING vs VALIDATION GAP (the real weakness)
- Root signed 2010; Root KSK = **KSK-2024** (introduced 2025-01-11, full rollover 2026-10-11, IANA).
- ~all gTLDs signed; ~58% ccTLDs signed (APNIC 2022). SLD signing ~1% (.com) / ~5% global.
- Algorithm staleness: 92% of RSA ZSKs still 1024-bit; ~50% of signed zones now ECDSA P256/P384.
- **Validation collapse**: global resolver validation ~31.5% (EU 45.3%, JRC); **end-to-end validated
  queries ~0.6%** (Cloudflare Radar May 2026); 82% resolvers FETCH DNSSEC but only 12% VALIDATE
  (Chung USENIX'17). DNSSEC **fails OPEN**.
- VERDICT: DNSSEC **locks (does NOT decentralize)** the single root.

## SCORECARD (exact)
root serving DECENTRALIZED(2,003/12) · root gov CENTRALIZED(1 file) · root HQ US-HEAVY(10/12) ·
gTLD CENTRALIZED(ICANN+1,166) · ccTLD DECENTRALIZED(255) · RIR DECENTRALIZED(5) ·
alt/blockchain FRAGMENTED · DNSSEC validation WEAK(0.6% e2e).

## 5D OMNIMAP
See references/dns-5d-omnimap.md — builds the 8-node topology (root_zone/gtld/cctld/rir/alt_root/
blockchain_dns/validator/zbit_stack) as dns_5d_map.json + .txt. Agent defines 5 axes; flag it.
