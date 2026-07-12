# API-Driven Attestation & the `\'` Raw-String Powershell Quoting Bug

(2026-07-12, ZQM fleet claim attestation. Reuse for any "serve the verified
claims over HTTP so they can be queried/attested on demand" task.)

## Pattern: API-driven attestation
- Deliver claims as a LIVE, queryable HTTP API, not just a static markdown file.
  The user's "api driven attestation" terse directive expanded to exactly this.
- Architecture (stdlib-only, zero deps — fastapi/uvicorn were NOT installed):
    1. `claims_core.py` — pure compute core. `build_attestation()` is the ONLY
       public entry point; it re-derives all claims from live state and builds the
       SHA-256 chain. NO file writes inside it.
    2. `verify_claims.py` (offline) — imports `build_attestation()`, writes
       JSON + MD manifest. SAME core as the server => paths can't diverge.
    3. `api_server.py` — `ThreadingHTTPServer` on :8088, serves
       `/attest`, `/attest/summary`, `/attest/claim/<ID>`, `/attest/chain`,
       `/attest/probes`, `/audit/chain`. Read-only; never writes the audit DB.
- Endpoints return the chained `chain_root` + per-claim status, so a caller can
  independently re-walk and verify tamper-evidence over HTTP.

## Pitfall 1: build the attestation ONCE per request
First server version called `build_attestation()` up to 3x per `/attest/claim/<ID>`
request. Each build runs live curl/redis/powershell probes (~15s). A 15s-capped
curl client then timed out (exit 28, empty body). FIX: build ONCE into a local
var, reuse for all branches. Verified: single build ~15s, client `--max-time 40`.

## Pitfall 2 (NEW, distinct from the `$_` trap in SKILL.md): `\'` in a Python raw string
The existing SKILL.md has the MSYS `$_`-expansion trap. A SECOND, separate bug
bit the B4 Powershell probe this session:

  sh(r'powershell.exe ... -Command " ... -match \'ZQM|Stack|Autostart\' } ..."')

In a Python **raw** string `r'...'`, `\'` is a literal backslash + quote — it is
NOT an escaped quote. So the shell received `\'ZQM|Stack|Autostart\'` with
LITERAL backslashes, and PowerShell threw:
  Unexpected token '\'ZQM|Stack|Autostart\'' in expression or statement.

FIX (the form that actually worked, verified standalone):
  sh(r"powershell.exe -NoProfile -Command \"Get-ScheduledTask | Where-Object { $_.TaskName -match 'ZQM|Stack|Autostart' } | Select-Object -ExpandProperty TaskName\"")

Key: delimit the Python raw string with DOUBLE quotes `r"..."`, keep the
PowerShell script in DOUBLE quotes, and the inner PS string in SINGLE quotes
(`'ZQM|...'`) with NO backslash. Inside `r"..."` a `'` is a normal char and
`$_` is left for PowerShell. Never use `\'` inside a raw string.

## Pitfall 3: chain_root rotates per call (document it)
Because `build_attestation()` stamps a fresh `ts` each call, the emitted
`chain_root` is DIFFERENT on every HTTP request — that is CORRECT point-in-time
attestation (each response is a self-signed snapshot). The AUDIT-DB chain_root
(from `claim_hashes`, repaired 2026-07-12 -> dbd8bc73...) is STABLE; the
live manifest root rotates. If a STABLE published root is wanted, add a
`--fixed-ts` mode or persist the last root to disk.

## Verification of the live server (what to re-run)
  curl -s --max-time 40 http://127.0.0.1:8088/attest/summary
  curl -s --max-time 40 http://127.0.0.1:8088/attest/claim/B4
  curl -s --max-time 20 http://127.0.0.1:8088/audit/chain
Expect: summary {claim_count, tally, chain_root, audit_db_chain.valid=true};
single-claim returns {id,claim,status,evidence}; audit/chain {valid:true,rows:68}.
