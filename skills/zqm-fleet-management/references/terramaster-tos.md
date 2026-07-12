# TerraMaster TOS NAS — management notes (ZQM GARDEN-04)

GARDEN-04 (192.168.1.144 / .147) are **TerraMaster** NAS running TOS (TerraMaster
Operating System), NOT Synology. MAC `6C:BF:B5` = Noon Technology Co., Ltd (OEM/MAC
assignment; the device itself is TerraMaster). Different management plane than the
Synology Gardens.

## Verified facts (this session)
- Port 5443 OPEN, valid TLS 1.2 (ECDHE-RSA-AES128-GCM-SHA256, self-signed cert).
- HTTP :80 returns 301 redirect to HTTPS. HTTPS :5443 GET / returns 200 with page
  title **"TOS Loading"** (confirms TOS). BUT PowerShell 5.1 Invoke-WebRequest/
  Invoke-RestMethod GETs to :5443 fail with "connection closed on a send" — a PS 5.1
  TLS-layer quirk. **Use Python (execute_code, ssl context) to probe — it works fine**
  and returns the real page.
- SMB (445) open; the Synology-style `web` share is NOT present. Plain net use /
  New-SmbMapping to \\ip\web fails ("network name cannot be found").
- DSM endpoints (/webapi/auth.cgi, Synology API) -> 404. TerraMaster is not DSM.

## Login / API — UNRESOLVED
The TOS login API route was NOT determined by probing. Tried and all 404'd:
/api/login, /module/api.php?api=login, /webapi/login, /login, and many /databack/...
and /api/v1|v2/... variants. The SPA bootstrap loads /databack/complete (app shell
prefix is /databack/), but the actual login POST route could not be guessed.

**To finish GARDEN-04 management, get ONE of:**
1. The TOS version (login page / UI — TOS 4.x vs 5/6/7 use different APIs).
2. The real login URL from the browser: open https://192.168.1.144:5443, log in,
   DevTools -> Network -> copy the login POST URL + body shape. Replicate exactly.
3. Confirm the admin account name (TerraMaster default is often admin/admin; the
   Synology azelenski cred may or may not apply — they are separate devices).

## Security check (do this first — CVE-2022-24990)
TerraMaster TOS <= 4.2.29 has CVE-2022-24990: an UNAUTHENTICATED info-disclosure
where a GET with User-Agent: TNAS to the API endpoint leaks the admin password/hash.
Read-only, no creds needed. Test (Python):
    import ssl, http.client
    def check(ip, port=5443):
        for path in ["/module/api.php?api=login","/module/api.php","/api.php"]:
            ctx=ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
            c=http.client.HTTPSConnection(ip,port,context=ctx,timeout=8)
            c.request("GET",path,headers={"User-Agent":"TNAS"})
            r=c.getresponse(); b=r.read(2000).decode("utf-8","replace"); c.close()
            if "PWD" in b or "password" in b.lower(): return f"LEAK on {path}: {b[:200]!r}"
        return "no leak on tested paths (patched / TOS5+)"
Session result: GARDEN-04 144 & 147 returned CLEAN on tested paths. Still worth
confirming the TOS version / firmware currency.

## Reference vs Synology skill
Full Synology DSM login (form-encoded body, error-code table) lives in
references/synology-dsm-api.md and devops/synology-dsm-management. TerraMaster is a
distinct device class — do NOT assume DSM endpoints work here.
