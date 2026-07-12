# Strict leak-sweep (reusable method)

When auditing a knowledge base / repo for credential or PII leakage, a NAIVE
grep for `password|secret|api_key` produces massive FALSE POSITIVES. The point
of a sweep is to find REAL secrets that survived sanitization — so tighten the
regex.

## False positives to EXCLUDE (these are NOT leaks)
- `password` inside prose headings: "Password Management Solutions",
  "password-management-systems" -> docs, not secrets.
- `Bearer ${process.env.GITHUB_TOKEN}` / `Authorization: Bearer ${...}` ->
  env-var references, no literal token.
- `sk-ant-...`, `sk-...` -> masked placeholders, not real keys.
- `test@test.com`, `test@example.com`, `careers@zqmgeo.com` -> fake/test data.
- Docker subnets `172.20.0.0/16`, `172.25.0.0/16` -> not real LAN IPs.
- `OPENAI_API_KEY="sk-..."` in a commented example block -> placeholder.

## Real leak patterns (flag these)
- Plaintext NAS/SMB cred: `user/pass#...$` e.g. `azelenski/e5Bi6#g7*7qB3Zr$`.
- Real phone numbers OTHER than the redaction-fake `555` blocks:
  `+1 (386) 265-9994`, `+1 (386) 957-2314` (the user's REAL numbers).
- Real API keys: `sk-[A-Za-z0-9]{20,}`, `sk-ant-[A-Za-z0-9]{20,}`,
  `ghp_...`, `xox[baprs]-...`.
- Old-host REAL IP: `192.168.1.241` (invented host) vs the verified `192.168.1.0/24`.
- Any `azelenski` token even inside a path: `azelenski/e5Bi6...`,
  `azelenski@[redacted]:/Vol...`, SSH username `azelenski` in a table.

## Procedure (Python, zip-aware)
```python
import zipfile, re, glob, os
ZDIR = r"C:\Users\zqmco\.sanitize_work\03_zqm_ready"
real = re.compile(r"(e5Bi6|265-9994|957-2314|azelenski"
                  r"|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}"
                  r"|192\.168\.1\.241)")
for z in sorted(glob.glob(os.path.join(ZDIR,"*.zip"))):
    zf = zipfile.ZipFile(z)
    for it in zf.infolist():
        if it.is_dir(): continue
        try: t = zf.read(it.filename).decode("utf-8","replace")
        except: continue
        for ln in t.splitlines():
            if real.search(ln) and "[REDACTED" not in ln:
                print(f"  LEAK {z}:{it.filename}: {ln.strip()[:90]}")
```

## Re-scrub (when a cleaned zip still leaks)
Zip is immutable per-entry; rebuild it:
```python
import zipfile, os
zp = os.path.join(ZDIR, "ZQM-Zbit-Knowledge-Base.zip")
tmp = zp + ".tmp"
REDACT = ["+1 (386) 265-9994","+1 (386) 957-2314","azelenski","e5Bi6"]
with zipfile.ZipFile(zp) as zin, zipfile.ZipFile(tmp,"w",zipfile.ZIP_DEFLATED) as zout:
    for it in zin.infolist():
        data = zin.read(it.filename)
        try:
            t = data.decode("utf-8"); o = t
            for s in REDACT: t = t.replace(s, "[REDACTED]")
            if t != o: data = t.encode("utf-8")
        except: pass
        zout.writestr(it, data)
os.replace(tmp, zp)
```
Then RE-RUN the strict sweep and assert 0 unredacted lines. (The redaction
LABEL `[REDACTED:azelenski]` will match the naive `azelenski` regex — exclude
lines already containing `[REDACTED` so you don't false-positive on your own
placeholder.)

## Lesson from live run (2026-07-11)
A sanitize pipeline had REDACTED most tokens but MISSED the NAS password +
real phones in `USER.md`/`DFORGE-11-HISTORY.md`/`knowledge.py`/`Modelfile` of
two "cleaned" zips. The strict sweep caught it; re-scrub + re-verify = 0 leaks.
The raw + declassified GDrive copies still carry the NAS pw (CRITICAL) — those
are out of scope unless the user explicitly approves purge.
