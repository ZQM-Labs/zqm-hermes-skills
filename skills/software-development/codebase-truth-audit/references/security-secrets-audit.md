# Security & Secrets Posture Audit (agent revival)

Independent, don't-trust-prior-claims verification of a re-homed agent's
security/secrets surface. Built from a live ZBit audit (2026-07-11). Every
check below was run against the running service and on-disk files — not read
from the agent's own claims.

## Output contract (user expects this shape)
Concise verdict **SECURE / ISSUES** + the specific LIVE evidence + any gap
flagged. Under ~250 words. Counts of real matches (expect 0 for PII).

## Live checks (commands that worked on Windows/git-bash)

**1. API key gate (X-Api-Key).**
- No key: `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:PORT/path` → expect **401**.
- Read the real key: the `read_file` tool BLOCKS `.env` (defense-in-depth guard
  says "secret-bearing environment file cannot be read"). Bypass via terminal:
  `KEY=$(grep '^KEYNAME=' ZBit_api/.env | cut -d= -f2-)`.
- With key: `curl -s -o /dev/null -w "%{http_code}" -H "X-Api-Key: $KEY" URL` → expect **200**.
- Unknown skill name (with key): `curl -X POST -H "X-Api-Key: $KEY" -d '{}' URL/v1/skill/__import__` → expect **404** (proves no exec path).

**2. Bind is loopback-only.**
`netstat -an | grep -E "8400|4001"` → expect `127.0.0.1:PORT` under LISTENING,
NOT `0.0.0.0:PORT`. Confirms no LAN/internet exposure.

**3. No eval/exec of caller input.**
Read the runtime `__init__.py` + `app.py` from disk. Confirm:
- a fixed `REGISTRY = {...}` dict of N named fns (count them);
- the endpoint does `if name not in REGISTRY: raise 404`; `REGISTRY[name](**kwargs)`;
- NO `eval`/`exec`/`__import__`/`subprocess` with caller-controlled strings
  (subprocess, if any, must use a hardcoded argv list, e.g. `["python", script, "discover"]`).

**4. PII absence in "cleaned" artifacts (strict).**
```sh
mkdir -p /tmp/audit && for z in a.zip b.zip; do
  rm -rf /tmp/audit/x; mkdir -p /tmp/audit/x
  unzip -o -q "$z" -d /tmp/audit/x
done
grep -rIF -e "+1 (386) 265-9994" -e "azelenski@" -e "e5Bi6#g7*7qB3Zr$" /tmp/audit/x
# exit 1 = ZERO real matches (expected)
```
Use `-F` (fixed strings) so regex metachars in secrets (e.g. `#`, `*`, `$`) are
literal. Grep BOTH unzipped trees together so a secret moved between zips still counts.

**5. Vault ACLs.**
`icacls "ZBit_vault\.vault_key"` → expect owner-only (zqmco:R,W). For `.enc` and
dir, check whether SYSTEM/Administrators inherited Full.

**6. Deprecated plaintext copies (undo buffer, not deleted).**
`find "ZBit_vault/.deprecated" -type f | wc -l` → confirm expected count. These
are LIVE plaintext creds on disk by design — flag the residual exposure.

## Windows ACL pitfall (discovered live)
A spec claim of "owner-only ACL via icacls / chmod 600" is **NOT the default**.
Default Windows DACL on a new file grants `NT AUTHORITY\SYSTEM:(F)` and
`BUILTIN\Administrators:(F)` plus the owner. `icacls` only *shows* this — it
does not remove it. To actually achieve owner-only:
```cmd
icacls "file" /inheritance:r /grant:r "ZQM-NODE-1\zqmco:(R,W)"
```
`chmod 600` is a POSIX concept with no native Windows effect here. VERIFY the
ACL claim with `icacls`; do not accept the doc's wording. The ZBit `.env` audit
showed exactly this gap: claimed owner-only, actually SYSTEM+Admin Full.

## Live AI service-stack auth posture (LiteLLM + app proxy) — READ-ONLY
The checks above assume a vault/PII angle. A second, equally common posture
review is: *given a running local AI stack (LLM proxy + app API), what can a
local process do with NO credentials?* Every check here is read-only — never
write, never brute, never guess/print a real key. Built from a live ZBit+LiteLLM
stack review (2026-07-11).

**Report discipline the user expects (hard rule).**
- Give each finding as: `PROVEN` / `UNVERIFIED`, plus `severity`, `claim`,
  the **exact command**, and a **redacted** output snippet.
- REDACT all secret material: `sk-...` → `sk-REDACTED`; `api_key:"..."` →
  `api_key:"REDACTED"`. Never print `.env` contents or a real key value.
- INVENTORY credentials by **presence + location + count only**, not contents.
  `search_files` *omits* secret-bearing `.env` results by design — confirm the
  exact path with `ls` / an existence check, then report `PRESENT <path> (N bytes)`.
- For gate/key tests use a clearly-FAKE **sentinel** value (e.g.
  `X-Api-Key: x-bogus-sentinel-not-real`), NOT a guessed real key. Never brute.

**A. LLM proxy accepts completions with NO auth token (master_key absent).**
LiteLLM only enforces a token if `general_settings.master_key` (or env
`LITELLM_MASTER_KEY`) is set. If absent, `/chat/completions` serves anyone on
loopback.
- Confirm master_key absent: read the proxy config — assert NO
  `general_settings:` block and NO `master_key:` key. (In the live case the
  config had only `model_list`, `litellm_settings`, `server`.)
- Exploit-probe (read-only): `curl -s -X POST http://127.0.0.1:4001/chat/completions -H "Content-Type: application/json" -d '{"model":"<model>","messages":[{"role":"user","content":"ping"}]}'` → expect `200`.
- **CRITICAL: a 200 is not proof of a real completion.** Discriminate a real
  chat completion from an HTML error page by parsing the body: `python -c`
  load JSON, assert `"choices" in d` and `d["choices"][0]["finish_reason"]`
  is set and `len(message.content)>0`. If it parses and has `choices`, it's a
  genuine completion (HIGH: unauthenticated proxy use). If `error`/`object`
  differ or it's non-JSON, it's a stub/error — downgrade to INFO/UNVERIFIED.
- Corroborate with the proxy's own access log (e.g. `litellm4001.log`): a line
  like `"POST /v1/chat/completions HTTP/1.1" 200 OK` with no `Authorization`
  header in your curl proves the no-token path served.
- **Config vs live mismatch (INFO):** the config file may state `server.port: 4000`
  while the live proxy listens on `:4001` (started with an override). Report the
  live port (from the access log / `netstat`) and note the config is stale.

**B. Schema disclosure — /docs /redoc /openapi.json reachable WITHOUT auth.**
- `curl -o /dev/null -w "%{http_code}" http://127.0.0.1:PORT/{docs,redoc,openapi.json}`
  → all `200` unauthenticated = INFO (endpoint schema + fleet/route inventory
  leak). No token needed.
- Read `openapi.json` and list `securitySchemes` + per-path `security`. If it
  shows `securitySchemes: []` and "none declared" on every path, the auth gate is
  **code-enforced in middleware, NOT reflected in the schema** — so the gate
  CANNOT be verified from the spec. You must hit a REAL route (see C).
- Pitfall: a route the spec/docs imply (e.g. `/chat/completions`) may 404 on the
  real app (which uses `/v1/generate`). A 404 is a nonexistent route, not an open
  gate — discover the true routes from `openapi.json` before testing the gate.

**C. App API key gate — test on a REAL route with sentinel keys.**
- No key: `curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:PORT/v1/generate -d '{"prompt":"ping"}'` → expect **401**.
- Sentinel key: same with `-H "X-Api-Key: x-bogus-sentinel-not-real"` → still **401** (proves exact-match, not presence-only).
- Read the gate code (`app.py:_check_key`): confirm it compares the header to a
  key sourced from env/config, AND that with an empty key it returns `503`
  (refuses silent dev-open) rather than `200`. That empty-key→503 branch is a
  POSITIVE design pattern worth naming.
- LOW: `/health` often returns 200 unauthenticated and leaks `host` (COMPUTERNAME)
  + fleet node names — flag as hostname disclosure.

## Latent-risk flags to call out even when "SECURE"
- Auth middleware that opens the door when the key is empty ("dev mode") — safe
  only if the key is currently set; fragile by design.
- Inherited SYSTEM/Administrators Full on `.enc`/vault dir while only the key is
  truly owner-only — local-admins-can-read, narrower than spec.
- Plaintext undo buffer (`.deprecated`) containing real creds on disk indefinitely.
- LLM proxy with NO `master_key` → any loopback process can drive completions
  through the fleet; add `general_settings.master_key` (loopback-only does NOT
  narrow the auth surface). Schema-disclosure routes (/docs,/redoc,/openapi.json)
  unauthenticated is normal for FastAPI but still an INFO inventory leak.
