# DNS Authority — live-verified claim set

28 claims about global DNS authority, re-verified LIVE 2026-07-11 against
root-servers.org / iana.org / APNIC / Cloudflare Radar / ICANN / dig.watch.
Tagged PROVEN / NOT PROVEN / FALSE. Re-run before re-stating any of these.
Full ledger: see session artifact `omnimap_claims.db` (schema: claims(id,node,claim,
status,evidence,reverify_date), meta).

## PROVEN (25)
- Root: 13 named auths (A–M) / 12 orgs. 2003 anycast inst (root-servers.org, 2026-07-06).
  10/12 US-HQ (Verisign×2, USC-ISI, Cogent, UMD, NASA, ISC, DoD, Army, ICANN; non-US:
  Netnod SE, RIPE NL, WIDE JP). Root signed 2010. Root KSK = single trust anchor.
- KSK-2024 rollover EXACT: Publication 2025-01-11; RFC5011 trust ~2025-02-10;
  Rollover 2026-10-11 (current key stops signing). Source: iana.org/dnssec/files.
- gTLD: 1424 total TLDs in root zone. 1166 = 1151 generic + 14 sponsored + 1 infra(.arpa).
  All gTLDs signed. .com signed domains ~1% of base (Verisign, 2020 figure — stale, see below).
- ccTLD: 255 EXACT (IANA Root Zone DB, 2-letter grep).
- RIR: 5 orgs (ARIN/RIPE NCC/APNIC/LACNIC/AFRINIC). RPKI = DNSSEC analog for BGP.
- Alt roots: OpenNIC (volunteer); China .chn (own IoT root); Russia Runet national root
  servers (law 2019). NOT validatable vs IANA root (different zone file).
- Blockchain DNS: Namecoin(2011)/Handshake/ENS/Unstoppable EXIST; adoption LOW
  (MDPI/CEUR 2024: inadequate support). Does NOT replace ICANN.
- Validator: global resolver validation ~31.5% (EU 45.3%, JRC). End-to-end validated
  ~0.6% (Cloudflare Radar May 2026). 82% of resolvers fetch DNSSEC but only 12% validate
  (Chung USENIX'17). Fails OPEN.
- REAL-WORLD proof of fail-closed: .de TLD outage 2026-05-05 — DENIC published broken
  RRSIGs, validating resolvers returned SERVFAIL (Cloudflare blog).
- ZBit stack: PIDs 1908+19120 alive, loopback-only, no external egress, X-Api-Key on
  /v1/*, litellm open loopback, NOT a C2 node.

## NOT PROVEN (2) — re-verify before re-stating
- ccTLD ~58% signed: APNIC 2022 figure (144/248). Likely drifted; pull fresh from
  IANA/RSSAC before citing as current.
- "Omnimap" as a canonical tool: no such product. (Framing gap, not a factual claim.)

## FALSE (1)
- "US government controls the root": NTIA/USG IANA contract EXPIRED 2016-09-30;
  stewardship → global multistakeholder (PTI/ICANN) 2016-10-01. PROVEN FALSE by
  iana.org/help/pti-transition + ICANN 2016-10-01 announcement + dig.watch.

## Honest corrections vs earlier passes
- Root operator HQ stated "10/12 US" earlier — live IANA list CONFIRMS 10 US-HQ
  (incl. ICANN HQ US) + 3 non-US. Same count, now precise.
- ".com signed ~1%" is a 2020 Verisign figure — keep as PROVEN-WITH-STALENESS, do NOT
  upgrade to "current" without a fresh pull.
- KSK rollover dates tightened to EXACT IANA values (added RFC5011 2025-02-10).

## Re-usable live sources (bookmark these)
- https://root-servers.org                        (instance count, dated)
- https://www.iana.org/domains/root/servers       (12 operators + IPs)
- https://www.iana.org/domains/root/db            (TLD list; grep for counts)
- https://www.iana.org/dnssec/files               (KSK rollover schedule + trust anchors)
- https://stats.labs.apnic.net/dnssec             (country-level validation %)
- JRC "DNSSEC in the EU and globally" report      (31.5% global / 45.3% EU)
- Cloudflare Radar DNS analytics                  (end-to-end ~0.6% May 2026)
