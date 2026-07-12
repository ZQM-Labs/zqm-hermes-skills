# DNS Authority / ICANN-IANA Investigation (live 2026-07-11)

Reusable method for grounding claims like "is DNS decentralized / US-controlled /
does example.com do a www-scheme flip" with REAL numbers instead of assertion.

## The three-layer authority split (never call DNS "centralized" or "decentralized" without naming the layer)
- ROOT ZONE: 13 named authorities (A-M), 12 independent operators, ~2,000 anycast
  instances globally. GOVERNANCE centralized (one IANA root file, ICANN multistakeholder);
  SERVING decentralized (anycast, many countries).
- TLDs: gTLDs centralized (ICANN + registries); ccTLDs decentralized (~200+ national NICs,
  each under its own law).
- NUMBER RESOURCES: 5 RIRs (ARIN/RIPE/APNIC/LACNIC/AFRINIC), regionally autonomous.

## Decisive live probes (run these, don't assert)
- Root operator count + country spread: https://root-servers.org (live "operational instances"
  + the 12 operator orgs) and https://www.iana.org/domains/root/servers (A-M -> operator map).
  REAL NUMBER this session: 10 of 12 root operators are US-headquartered
  (Verisign x2, USC-ISI, Cogent, UMD, NASA, ISC, DoD NIC, US Army ARL, ICANN); only Netnod
  (SE), RIPE NCC (NL), WIDE (JP) are non-US. "US orgs operate most root instances" = PROVEN.
- "US government controls root" = FALSE since 2016-10-01 (IANA stewardship transition; NTIA
  contract ended). Verify via ICANN/NTIA transition docs.
- ccTLD top list + national control: DNIB quarterly report (e.g. Q1 2025 top ccTLDs:
  .cn .de .uk .ru .nl .br .au .fr .in .eu).
- RIR split: https://www.nro.net/about/rirs (5 orgs, geographic regions).
- Reserved/example domains: RFC 2606 (BCP 32) + RFC 6761; IANA "Example Domains" page says
  example.com is "not available for registration or transfer," a best-effort doc service.
- Alt/sovereign roots: OpenNIC (volunteer alt root), China .chn (separate IoT root),
  Russia "Sovereign Runet" (national root law, in force 2019). These FRAGMENT the namespace —
  a resolver pointed at an alt root sees a different tree; opt-in, not interoperable.
- Blockchain DNS: Namecoin (2011), Handshake (blockchain root zone), ENS (.eth on Ethereum),
  Unstoppable Domains. Multiple 2024 surveys converge: "inadequate support and adoption,"
  limited browser/resolver support -> parallel namespaces, NOT a replacement for the IANA root.
- DNSSEC: root signed 2010; most TLDs signed; but end-user validation low (Verisign: .com
  signed domains ~1% of base, slow growth). DNSSEC = integrity lock on the existing chain,
  NOT decentralization.

## "www schema flip" / HTTPS-redirect audit (the URL-scheme recipe, concretely)
"schema flip" usually means URL-scheme (http<->https) + www-host canonicalization. Method:
1. Probe 4 forms single-hop (no -L) to capture the redirect HOP, not the final:
   `curl -s -D - -o /dev/null http://example.com` -> look for `Location:` and HSTS header.
2. Then `-L` follow to confirm final + num_redirects.
3. RDAP/WHOIS for reservation state: `curl https://rdap.verisign.com/com/v1/domain/example.com`.
4. TLS issuer: `echo | openssl s_client -connect example.com:443 -servername example.com`.
LIVE RESULT (example.com, 2026-07-11): NO flip — all 4 forms return 200 with ZERO redirects,
NO HSTS, plaintext http:// served. So "example.com does a www-scheme flip" = FALSE. It is an
RFC 2606 reserved doc domain fronted by Cloudflare; ICANN/IANA run no redirect on it.
CAUTION: do NOT use example.com as a secure-redirect reference — it serves plaintext.

## Reporting discipline for this class
- Always state PROVEN/FALSE per specific claim (decentralized-serving vs centralized-governance
  are DIFFERENT claims — grade each).
- "Fully decentralized globally" = FALSE for the main tree (by design one root).
- "US-controlled" = FALSE since 2016-10-01; only "US-orgs-operate-most-instances" is PROVEN.
- Keep the scorecard shape: Root serving / Root governance / gTLD / ccTLD / RIR / alt-roots,
  each tagged DECENTRALIZED | CENTRALIZED | FRAGMENTED.
