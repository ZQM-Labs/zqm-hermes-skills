# URL-Scheme / Redirect-Chain / Reserved-Domain Audit

Reusable recipe for when the user asks to investigate a domain's "www schema flip",
HTTPS redirect behavior, or an ICANN/IANA/reserved-domain claim. Live-tested
2026-07-11 against `example.com` (the "www schema flip" prompt).

## What "schema flip" usually means
Almost always URL **scheme** (`http:`↔`https:`) plus `www` canonicalization —
the pattern where `http://`→`https://` (upgrade) and/or apex↔`www` (host flip),
often with HSTS forcing HTTPS at the client. SEO/security guides describe exactly
this. Confirm empirically; do NOT assume.

## Probe recipe (bash + curl, MSYS-safe)
```bash
for u in "http://example.com" "https://example.com" \
         "http://www.example.com" "https://www.example.com"; do
  echo "--- $u (single hop, no -L) ---"
  curl -s --max-time 8 -D - -o /dev/null "$u" 2>&1 | grep -i "^HTTP/\|^location:\|^strict-transport-security:"
done
# then a -L follow to see where it finally lands:
for u in "http://example.com" "http://www.example.com"; do
  curl -s --max-time 8 -o /dev/null -w "%{url_effective} code=%{http_code} redirects=%{num_redirects}\n" -L "$u"
done
```
Decision rules:
- NO `Location:` on any single hop + NO HSTS header ⇒ there is NO scheme/host flip.
  The domain serves http and https as independent endpoints. (example.com: TRUE — no flip.)
- `http://` → 301/302 `Location: https://...` ⇒ scheme upgrade present.
- `http://www.` → `https://` (apex or www) ⇒ canonical host flip present.
- `Strict-Transport-Security` present ⇒ client-side HTTPS enforcement (HSTS).

## TLS sanity (who issued, CN/SAN)
```bash
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -issuer -subject
```

## DNS (do A/AAAA match across apex + www?)
```powershell
Resolve-DnsName example.com -Type A ; Resolve-DnsName www.example.com -Type A
```
If apex and www resolve to the SAME IPs, a single CDN/edge fronts both (Cloudflare
ranges here) — the "flip" is handled by edge config, not the origin.

## Reserved-domain / ICANN-IANA triage
When the target is `example.com/.org/.net` or `.example`/`.test`/`.invalid`/`.localhost`:
- These are RESERVED per **RFC 2606** (BCP 32) + **RFC 6761** — "not available for
  registration or transfer." Maintained by IANA (an ICANN affiliate, PTI).
- ICANN/IANA do NOT operate a web server or redirects on them. Don't attribute any
  HTTP behavior to "ICANN doing a flip."
- The actual HTTP service is IANA "best effort," explicitly "not designed to support
  production applications."
- Verify registration/reservation state via RDAP (not legacy WHOIS):
  ```bash
  curl -s https://rdap.verisign.com/com/v1/domain/example.com \
    | python -c "import sys,json;d=json.load(sys.stdin);print(d.get('status'),[e.get('roles') for e in d.get('entities',[])])"
  ```
  Expect statuses like `client delete prohibited` / `client transfer prohibited` +
  a registrar entity — i.e. held in reserved/locked state.
- Source of truth: https://www.iana.org/help/example-domains , https://www.rfc-editor.org/rfc/rfc2606

## Output discipline
- State PROVEN/NOT PROVEN/FALSE per claim. "example.com does a www/scheme flip" →
  FALSE (no redirect, no HSTS, observed live).
- Separate ICANN's ROLE (reserve the name) from any HTTP behavior (it runs none).
- If the user meant a DIFFERENT "schema" (RDAP/WHOISH schema, SVCB/HTTPS DNS record,
  a tool's output flip), ask for the source — don't force the URL-scheme reading.
