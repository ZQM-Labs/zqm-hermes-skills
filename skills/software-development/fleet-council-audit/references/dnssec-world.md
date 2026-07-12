# The DNSSEC World (2026 snapshot)

Knowledge bank for the "look at the DNSSEC world" / "is DNS decentralized" thread
(2026-07-11). Condensed, sourced, with PROVEN numbers. Pair with
`dns-authority-investigation.md` (the global-authority extension).

## WHAT DNSSEC IS (and isn't)
- Adds cryptographic signatures (RRSIG) + chain of trust (DNSKEY/DS) from root down.
  Proves a DNS answer wasn't tampered in transit (kills cache-poisoning / hijack).
- Does NOT provide: confidentiality (queries still plaintext), encryption (that's
  DoH/DoT), or anonymity. Integrity-only.
- TWO halves: SIGNING (zone publishes sigs) + VALIDATION (resolver checks them).
  Both required for protection. THE SPLIT explains the adoption gap.

## SIGNING COVERAGE (PROVEN)
- Root zone signed 2010. Current KSK = KSK-2024, introduced 2025-01-11; full
  rollover 2026-10-11 (IANA scheduled). Trust anchor in IANA root-anchors.xml.
- All gTLDs signed; ~144/248 ccTLDs signed (APNIC 2022 "majority").
- IANA root DB: 1,593 TLDs (Feb 2026).
- Second-level domains signed: ~18M ~= 5% of global delegations (APNIC 2022).
  .com signed domains ~1% of base (Verisign, slow ~0.1%/yr growth).
- Algorithm hygiene: 92% of RSA ZSKs still 1024-bit (no longer recommended);
  ~50% of signed zones now ECDSA P256/P384 (alg 13/14). Verisign .com/.net/.edu
  alg-update 2023+.

## VALIDATION COVERAGE -- the real gap (PROVEN)
- Global resolver validation rate: ~31.5% global, 45.3% EU (JRC/EU Commission).
- APNIC Labs world map: country-level validation %, 30-day avg (live source).
- End-to-end VALIDATED queries: Cloudflare Radar May 2026 = 0.60% (up 5 straight
  months from 0.41% Jan); ~8% of queries reach signed domains but only ~0.47-0.60%
  validated end-to-end; resolver support slipped to ~11%.
- Classic study (Chung USENIX'17): 82% of resolvers REQUEST DNSSEC records but only
  12% actually VALIDATE.

## WHY THE SPLIT (structural)
- Signing = registry/operator job (top-down, easy to mandate).
- Validation = resolver/USER job (bottom-up, opt-in). A signed domain protects
  NOBODY unless the user's resolver validates.
- Big public resolvers (8.8.8.8, 1.1.1.1) DO validate; many ISP resolvers don't.
- Economic disincentive: signing costs operators, users can't see the benefit, no
  visible failure when off. "DNSSEC works against its own adoption" (ISOC 2024).

## WEAKNESSES / VULNERABILITIES (PROVEN)
- Algorithm staleness: 1024-bit RSA ZSKs still widespread (weak vs modern compute).
- NSEC3 zone-walking: signed zones leak their ENTIRE name list (enumeration) unless
  NSEC3 opt-out/padding used. Privacy downside of signing.
- Rollover fragility: 2018 first root KSK rollover POSTPONED -- measurements showed
  many resolvers hadn't fetched the new key (risk of breaking validation for large
  populations). KSK-2024 rollover is the careful successor.
- Amplification/DDoS: DNSSEC responses large (signatures) -> historically abused for
  reflection amplification. Mitigated by anycast + RRL, but a real ops cost.
- "Validation fails open": broken/unavailable signature -> most resolvers SERVE the
  data anyway (no protection) rather than hard-fail. Partial deployment = false sense.

## SCORECARD
  Root signed            : YES (since 2010, KSK-2024 rolling)   STRONG
  gTLD/ccTLD signing     : ~all gTLD, ~58% ccTLD                STRONG-ish
  SLD signing (.com etc) : ~1%                                  WEAK
  Resolver validation    : ~31% global / 45% EU                MODERATE
  End-to-end validated   : ~0.6% of queries                    VERY WEAK
  Algorithm hygiene      : 1024b RSA still 92% of ZSKs         WEAK

## DECENTRALIZATION ANGLE (ties to dns-authority-investigation.md)
- DNSSEC does NOT decentralize authority -- it cryptographically LOCKS the existing
  single-root chain of trust. The root KSK is THE single trust anchor for the whole
  signed Internet. Whoever controls root key ceremonies (ICANN/IANA + Root KSK
  Ceremony custodians, multi-party, HSM, offline) is the apex of DNS trust.
- Sovereign/blockchain alt-roots (Runet, .chn, Handshake) can't be validated against
  the IANA root -- they trade global interoperability for independence.
- Claim "DNSSEC makes DNS decentralized" = FALSE. "DNSSEC makes the single root
  tamper-evident" = PROVEN.

## BOTTOM LINE
- DNSSEC widely DEPLOYED at the top (root + TLDs), barely USED at the bottom
  (end-to-end ~0.6% of queries). A roof with no walls for most users.
- Weakness isn't the crypto (mostly) -- it's the validation gap + algorithm staleness
  + fail-open behavior. It is integrity infrastructure for the existing hierarchy,
  not a decentralization mechanism.

## OPEN / UNRESOLVED (re-check live if precision needed)
- Exact 2026 signed-ccTLD count (have ~144/248 from 2022).
- Country-level validation % (APNIC Labs stats.labs.apnic.net/dnssec).
- Does the user's LOCAL resolver validate DNSSEC? Testable from Node-1 with a
  known-signed name + DO/CD flag check.
