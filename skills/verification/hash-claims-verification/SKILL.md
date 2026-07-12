---
name: hash-claims-verification
description: Re-derive every factual claim about a system from LIVE state (not logs or memory), label each PROVEN / NOT PROVEN / FALSE, and persist a tamper-evident SHA-256 claim ledger. Use when the user says "verify claims", "hash claims", "genesis" (root-cause), or demands real numbers / proof before reporting. Catches the false-negative and per-session/visibility traps that make a naive check lie.
---

# Hash-Claims Verification (recreation tier)

The user requires REAL NUMBERS and proof, not assertions. When asked to "verify claims" /
"hash claims", NEVER restate prior logs as fact. Re-derive every claim from scratch against
live state, then persist a tamper-evident ledger.

## Non-negotiable rules
1. RECREATE, don't recall. Re-run the authoritative probe for each claim this turn. Logs from
   earlier turns are HINTS, not evidence.
2. Label every claim PROVEN / NOT PROVEN / FALSE with the live observation + evidence string.
3. Re-verify any NEGATIVE with the authoritative method before recording it. A "not found" is
   often a probe artifact, not reality (see Traps).
4. ENUMERATE ACCESS PATHS before declaring a TARGET unreachable / unauthenticatable / "can't
   be done". The owner pushed back when an agent said "can't reconcile Node-4 from another
   node or garden" after only a PARTIAL probe. Before any blocker claim, LIVE-TEST every path
   a human at the keyboard could use: all stored creds (DPAPI vaults, `cmdkey /list`), other
   nodes' local-admin accounts against the target (SSH + WinRM), garden/admin creds (NOTE:
   Synology/TerraMaster accounts are NOT Windows-local — structurally cannot administer a
   Windows node), target built-ins (`Administrator` over WinRM 5985 — avoid SSH 10054 throttle
   from retry bursts), scheduled tasks / mesh jobs, and any hypervisor/IPMI plane on neighbors.
   Only after ALL fail is "no stored credential exists; needs local console or owner-supplied
   pw" the proven conclusion — not "can't". Full probe sequence + Node-4 case study:
 references/credential-reconciliation.md.
5. Persist a tamper-evident **chained** SHA-256 ledger (NOT a single blob hash). Build a
   hash chain: `chain[0] = sha256("GENESIS" || content[0])`, then
   `chain[i] = sha256(chain[i-1] || content[i])` where
   `content = id|statement|status|observed|evidence|ts`. Emit `chain_root = chain[-1]`.
   Every entry commits to its predecessor, so reorder/insert/delete changes every downstream
   hash — tamper-evident by construction. Re-compute the chain on later runs; a mismatched
   `chain_root` = tamper / regression.
5. Never fabricate. If a probe can't run (gated cred, offline host), mark NOT PROVEN /
   UNRESOLVED and say why. Do not fill the gap with a plausible value.

## Procedure
1. Enumerate claims as a list (C1..Cn) with a one-line statement each.
2. For each, write the smallest authoritative probe (live command) that proves/refutes it.
3. Run all probes; capture observed value + raw evidence (command output, hash, status code).
4. Score each: PROVEN if live observation matches the statement; FALSE if it contradicts;
   NOT PROVEN if the probe itself failed/ambiguous.
5. Emit `claim_evidence.json` (array of {id,statement,observed,status,evidence}) and
   `claim_manifest.json` ({generated, evidence_sha256, claim_count, proven, false,
   not_proven, claims:[{id,status,statement,evidence}]}).
6. Report a plain-text scorecard: PROVEN=n FALSE=m NOT_PROVEN=k, then each claim.

## HASH-CHAIN LEDGER FORMAT
The user explicitly demands "hash claims" — a single evidence-blob hash is NOT enough; they
want a verifiable chain. Algorithm:
```python
import hashlib
def chain(claims, ts):
    prev = b"GENESIS"; out = []
    for c in claims:
        content = "%s|%s|%s|%s|%s" % (c['id'], c['statement'], c['status'], c['observed'], ts)
        h = hashlib.sha256(prev + b"|" + content.encode()).hexdigest()
        out.append({'id': c['id'], 'hash': h}); prev = bytes.fromhex(h)
    return out, prev.hex()          # chain_root = prev.hex()
```
- Re-walk for verification: re-run `chain()` on the stored claims with the stored `ts` and
  assert the recomputed `chain_root` equals the stored one. If it diverges, a claim was
  altered OR the `ts` changed — both are findings.
- Always emit `claim_manifest.json` = {generated, ts, chain_root, tally, claims[]} and a
  human `claim_manifest.md` scorecard.
- **Self-correction trap:** re-probe live state in the SAME breath as the write. A doc
  drafted mid-session claimed "ZBit+LiteLLM DOWN (000)" but a final re-probe showed
  "404/200/200 — manually up". If a number in your deliverable isn't from a probe in the
  same run, treat it as stale and re-verify before finalizing.

## AUDIT-CHAIN CONTIGUITY VALIDATION
When a system already keeps a claim ledger (e.g. `fleet_endpoint_audit.db` ->
`claim_hashes`), VALIDATE its chain before trusting it:
```python
rows = db("SELECT fid, claim_hash, prev_hash, chain_root FROM claim_hashes ORDER BY generated")
rec = b"GENESIS"
for fid, ch, ph, cr in rows:
    rec = sha256(rec + b"|" + ch.encode()).hexdigest()
    if rec != cr: flag(fid)                       # stored root != recomputed -> broken link
if len({r[3] for r in rows}) == 1: flag("all rows share ONE chain_root")   # placeholder chain
if len({r[2] for r in rows} & {r[3] for r in rows}) == 0: flag("prev_hash links to nothing")
```
- **Real finding (2026-07-12):** `fleet_endpoint_audit.db.claim_hashes` (68 rows) was
  NON-contiguous — every row stored the SAME `chain_root`, and 68 distinct `prev_hash`
  values matched NO stored root (0/68 link). The ledger's tamper-evidence was dead. Treat a
  non-contiguous audit chain as its own BLIND SPOT: the monitor that is supposed to prove
  claims were never altered CANNOT prove it. Emit a sound chain as the replacement until the
  table is re-chained.
- Re-chaining an existing broken table: DO NOT trust `ORDER BY generated` (constant for all
  rows) or numeric `fid` (non-sequential). Recover true order by WALKING the existing
  `prev_hash` pointers (the 2026-07-12 case: prev_hash was already correct, only the
  accumulated `chain_root` was a stale placeholder). Fix ONLY `chain_root[i] =
  sha256(chain_root[i-1] || claim_hash[i])`; leave prev_hash/claim_hash untouched. Use
  `scripts/repair_claim_chain.py` (default DRY-RUN, `--apply` after owner OK + auto-backup).
  The exact walker + the 2 bugs it took to get right are in references/audit-chain-contiguity.md.

## TRAPS that produce FALSE NEGATIVES (learned the hard way)
- SYSTEM-owned scheduled tasks are INVISIBLE to a non-elevated `Get-ScheduledTask`. A task
  registered as SYSTEM will read as "NOT FOUND" from a normal prompt even though it exists
  and runs. FIX: self-elevate the verifier (`Start-Process -Verb RunAs`) before probing, or
  check the task directly from an elevated context.
- Drive-letter mappings (Z:, Y:) and UNC mounts are PER-SESSION. A mount done by the SYSTEM
  self-heal task lives in SYSTEM's session; a different (even elevated-admin) token can't see
  the drive letter or write to the UNC without a credential. A "write FAILED" here is a
  session artifact. FIX: probe the UNC path WITH the credential supplied (`net use \\host\share
  /user:...` or mount-then-probe inside the same script), exactly as the self-heal does.
- DPAPI `LocalMachine` blobs are MACHINE-SCOPED. A credential encrypted on host A will NOT
  decrypt on host B. Pushing a cred file to another node requires re-encrypting it WITH that
  node's LocalMachine key (run the encryption ON the target).
- `New-ScheduledTaskAction` takes `-Argument` (singular). `-Arguments` yields a null Action
  and "Cannot validate argument on parameter Action" at Register-ScheduledTask.
- PowerShell 5.1 (Windows) has NO ternary operator. Use if/else.
- WinRM on workgroup peers often offers ONLY Negotiate; Negotiate from a SYSTEM/scheduled
  principal to a workgroup peer FAILS. SSH (OpenSSH) with a vaulted cred works headless
  because it's credential-based, not logon-identity-based.
- A phantom principal (e.g. running a task as `HOST\zqmlocal` when that local account does
  not exist) fails registration with "no mapping between account names and SIDs" and the task
  silently never runs. Verify the account exists (`Get-LocalUser`) before using it as a
  principal.
- **Probe helper must return bytes on BOTH branches.** A `socket.connect` probe that returns
  `s.recv(64)` (bytes) on success but `type(e).__name__` (a str) on the `except` branch crashes
  downstream with `TypeError` when you do `b"200" in resp` and `resp` is a string. FIX: return
  `b""` (or `b"ERR:"+str(e).encode()`) on the except branch so `resp` is always bytes. This
  exact bug crashed fleet `diagnostics.py` at the first closed port (N2:6379), so it never
  scanned N2/N4 and under-reported the fleet.
- **Service-down vs node-off escalation.** A negative service probe (port closed) is ambiguous:
  the service stopped, or the whole node is off. Before recording `service down` as drift, probe
  the host's OTHER management ports (SSH 22, SMB 445, WinRM 5985) from the same host. If those
  are ALSO closed → the node is off (whole-node outage; reframes `drift` as `node offline`). If
  they're open but the service port is closed → a real service-level change. (2026-07-12: N2
  Ollama+Redis `down` was actually N2 fully powered off — 22/445 both timed out — not a config
  change.)
- **SQLite tamper-evident ledgers: hash AFTER `PRAGMA wal_checkpoint(TRUNCATE)` + `con.close()`.**
  If the .db uses WAL mode, uncommitted-at-OS bytes live in `-wal`/`-shm`; hashing the .db file
  alone gives a NON-reproducible hash and breaks tamper-evidence. Fold the WAL into the db, close
  all connections, THEN hash the file; verify no `-wal`/`-shm` linger.
- **MSYS bash expands PowerShell automatic variables in double-quoted `-Command` strings.**
  `powershell -Command "Get-ScheduledTask | Where-Object { $_.TaskName ... }"` → bash rewrites
  `$_` to a path (e.g. `/c/WINDOWS/system32.TaskName`), yielding `CommandNotFoundException`. FIX:
  single-quote the ENTIRE PowerShell script (`-Command '...'`), or pass a `.ps1` via `-File`.
  Applies to `$_`, `$env:`, etc.
- **SECOND PowerShell-quoting bug (distinct from the `$_` trap): `\'` inside a Python
  RAW string `r'...'` is a LITERAL backslash + quote, NOT an escaped quote.** A probe
  like `sh(r'powershell ... -match \'ZQM|Stack|Autostart\' } ...')` passes `\'ZQM...\'`
  (literal backslashes) to PowerShell, which throws `Unexpected token '\'ZQM...\''
  in expression or statement`. FIX (verified standalone): delimit the Python raw string
  with DOUBLE quotes `r"..."`, keep the PS script in double quotes, and the INNER PS
  string in single quotes with NO backslash: `sh(r"powershell -Command \"... -match
  'ZQM|Stack|Autostart' } ...\"")`. Inside `r"..."` a `'` is a normal char and
  `$_` survives for PowerShell. Never use `\'` inside a raw string.
- **curl `%{http_code}` doubling produces 6-digit codes.** A probe like
  `curl -s -o /dev/null -w "%{http_code}" URL || echo 000` returns `200000` on a
  real HTTP 200 in MSYS/git-bash, because curl can exit non-zero even on success
  (so the `|| echo 000` fallback fires and concatenates). FIX: capture the code,
  then `c="${c:0:3}"` (trim to 3 digits) and treat any code that is not exactly 3
  digits as ambiguous. Never report a 6-digit http code as-is — it is an artifact
  of the fallback, not a measurement. Prefer `curl --max-time 5 -o /dev/null -w
  "%{http_code}"` and validate length before trusting it.
- **MSYS/Win32 PATH DUALITY (B17):** a file git-bash `curl -o /c/Users/.../x.json`
  writes is INVISIBLE to a Win32 Python process via a normal path lookup
  (`os.path.exists(r'C:\Users\...x.json')` returns False even though `ls` in the
  same MSYS shell sees it). The mount table says `C: on /c` (same physical volume)
  but the Win32 path resolver still misses it — a stale-directory-cache / reparse
  quirk. FIX: when crossing MSYS-curl → Win32-Python, either (a) write to an
  explicit Win32-absolute path that Python will resolve (`curl -o
  "C:/Users/.../x.json"`), or (b) read in Python with the `\\?\` long-path prefix
  (`open(r"\\?\C:\Users\...x.json")`). The `\\?\` prefix made the same file
  suddenly visible. Symptom that tipped it off: curl reports `bytes=NNNN` (file
  written) but Python raises FileNotFoundError for the identical Win32 path.

## API-DRIVEN ATTESTATION (serve claims over HTTP, on demand)
When the user says "api driven attestation" (or wants claims queryable rather than
a static doc), deliver a LIVE, HTTP-servable attestation. Stdlib-only is enough
(fastapi/uvicorn were NOT installed on this host) — use `http.server`.

Architecture that worked (2026-07-12):
- `claims_core.py` (scripts/claims_core.py): pure compute. `build_attestation()`
  is the ONLY public entry point — re-derives all claims from live state, builds
  the SHA-256 chain, returns a dict. NO file writes inside it.
- `verify_claims.py` (offline): imports `build_attestation()`, writes JSON+MD
  manifest. Same core as the server => the two delivery paths can't diverge.
- `api_server.py` (scripts/api_server_template.py): ThreadingHTTPServer on :8088,
  endpoints /attest, /attest/summary, /attest/claim/<ID>, /attest/chain,
  /attest/probes, /audit/chain. Read-only; never writes the audit DB.
- Build the attestation ONCE per request (it runs live probes, ~15s). Calling it
  multiple times per request times out under a short-capped client. Verified flow:
  single build, reuse for all branches.
  CLIENT-SIDE TIMEOUT RACE: /sitrep and /nodes build in ~15s (live probes: curl x6,
  redis, powershell x2, sqlite x3). A client `curl --max-time 30` can race and return
  empty/non-JSON even when the server is HEALTHY. Use `--max-time 45` for /sitrep; never
  fire concurrent /sitrep calls. A single empty response is almost always a client timeout,
  NOT a server fault — RE-PROBE (with --max-time 45) before concluding the server is down.
  Optional: cache the build for N seconds per process to make /sitrep snappy.
- **LIVE INSTANCE ON THIS HOST (ZQM Node-1):** the working, non-template files
  already exist at `C:\Users\zqmco\swarm\` — `api_server.py`, `claims_core.py`
  (with REAL ZQM-fleet probes, not demo data), and `verify_claims.py`. Built +
  live-verified 2026-07-12. To (re)serve attestation, just run
  `python api_server.py --host 127.0.0.1 --port 8088` from that dir — do NOT
  regenerate from the templates. Confirm the port is free via `netstat -ano |
  grep ":8088"` first; the single live listener's real PID comes from netstat,
  not the session map (see LIFECYCLE below).

## FULL SITUATIONAL AWARENESS (extend attestation with /sitrep + /nodes)
When the user says "full api driven situational awareness" (or wants the whole
fleet state queryable, not just claims), extend the same service with a live
SA surface. What shipped 2026-07-12 on this host (in `claims_core.py` +
`api_server.py`):

- `build_sitrep()` in the core: assembles nodes + audit ledger + session store +
  monitoring + ranked open gaps, all from the SAME live probes. One function,
  called once per request (reuse the single-build pattern above).
- Endpoint `GET /sitrep` -> full SA JSON. `GET /nodes` -> the live node/port
  reachability matrix only.
- NODE TOPOLOGY: keep a static `NODES` tuple list (id, ip, os, role,
  [(svc, port, note), ...]) in the core; overlay LIVE reachable codes from probes
  to compute `reachable_now` + per-port status. This separates the known fabric
  (static) from current reachability (live) — the SA view is the merge.
- SA payload shape (what proved useful): `nodes[]` (id/ip/os/role/reachable_now/
  ports{code,note}), `audit_ledger` (open_questions total+open + the questions
  themselves + reliability + remediations + chain_valid/chain_rows),
  `session_store` (total/cli/cron/subagent/tool/nested + the search-tool cap note),
  `monitoring` (audit_db_mtime + drift-watch note), `open_gaps[]` (id/severity/
  title/evidence/gate). Rank gaps by severity; carry the GATE that blocks each
  (UAC / N2 cred / N4 cred / consent) so the SA is actionable, not just descriptive.
- BUG (fixed live): the `NODES` port tuples are 3-tuples `(svc, port, note)` but a
  dict-comprehension that unpacked them as `for p, note in ports` raises
  "too many values to unpack (expected 2)". Unpack the leading name too:
  `for _name, p, note in ports`.
- BUG (fixed live): `api_server.py` must import every core entry point it calls.
  Adding `/sitrep` + `/nodes` without adding `build_sitrep` to the
  `from claims_core import ...` line yields a `NameError` at request time
  (banner lists the route, handler crashes). Import all used builders up front.

## LIFECYCLE / RELIABLE VERIFICATION (Windows background-process trap):
- The Hermes `process` tool's PID/session tracking is UNRELIABLE on this host.
  CORRECTED mechanism (2026-07-12, verified with taskkill + netstat): a
  `process kill <session_id>` DID terminate its OS process (taskkill returned
  "SUCCESS" and netstat showed the port free). The earlier claim "the OS process
  SURVIVED, the original kept serving across three kills" was a MISdiagnosis. What
  actually happened: each restart spawned a NEW OS PID, and only the NEWEST
  survived — at most ONE server ever ran at a time (a port can't double-bind). So
  kills worked; the persistent process was simply the latest spawn, not a zombie.
- **Zombie-session watch-pattern false alarms:** a `watch_patterns` match is NOT
  proof a process is alive. Each killed session's buffered startup line
  ("...attestation API on...") can RE-FIRE the watch pattern later even though the
  OS process is DEAD. In one session FOUR stale session records
  (proc_1887af582829, proc_6e3f73428cdf, proc_43b9bea051, proc_86e548808ce6,
  proc_1d4736834424, proc_9cd10e3bd50a) all re-fired "attestation API on" while only
  ONE real listener (PID 7204, then PID 18492 in a later turn) existed.
  RULE: before killing anything, PROVE liveness with netstat; a watch-pattern
  notification alone is insufficient and will send you chasing ghosts.
- TRUST `netstat` + Get-CimInstance, not the session map. In the MSYS/git-bash
  shell use `grep`, not `findstr`:
  - Find the real listener:  `netstat -ano | grep ":8088"`  -> PID in last column.
    (LISTENING = live server; TIME_WAIT = leftover socket from a curl, NOT a server.)
  - Corroborate process:     `powershell.exe -NoProfile -Command "Get-CimInstance
    Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine
    -like '*api_server*' } | Select-Object ProcessId"`  -> the ONE real PID.
  - Kill by REAL pid:        `taskkill /PID <pid> /F`
  - Confirm free:            `netstat -ano | grep ":8088"`  (empty = free)
  - Restart clean, then re-verify the served content reflects current code (Python
    imports the core once at startup, so a stale process serves stale claims).
  - STALE SESSION RECORDS RE-FIRE WATCH PATTERNS. A dead session's buffered stdout
    (e.g. "attestation API on") can re-match its watch pattern AFTER the OS process is
    gone, yielding a FALSE "still running" signal. A watch-pattern match is a HINT, not
    proof of a live process — always confirm with netstat. (Seen in one session: EIGHT
    "killed"/stale records all re-fired "attestation API on" while only ONE real listener
    ever existed on :8088 — proc_1887af582829, proc_6e3f73428cdf, proc_43b9bea051,
    proc_86e548808ce6, proc_1d4736834424, proc_9cd10e3bd50a, proc_d0997b73a17a (dead
    twins) + proc_848bbc1484d2 (the LIVE session re-firing its own buffered line — the
    watch re-fired even though the process was alive and correct).)
  - DISAMBIGUATE LISTENING vs TIME_WAIT. `netstat` may show the port with state TIME_WAIT
    and PID 0 — those are sockets from YOUR OWN curls, NOT servers. Only the LISTENING
    line with a real PID is the live server. There can be exactly ONE LISTENING process
    per port (SO_REUSEADDR blocks duplicates); any extra "killed" sessions are ghosts.
  - Confirm the real process + cmdline (not just the port) before killing, to avoid
    killing the wrong PID:
    powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -like '*<marker>*' } | Select-Object ProcessId,CommandLine"
    (Single-quote the whole -Command script so bash doesn't expand $_.)
- A running server loads `claims_core` at import; if you EDIT claims_core.py you
  MUST restart the server or it serves pre-edit claims. Always re-curl a known
  claim (e.g. /attest/claim/B4) AND /sitrep + /nodes after any restart to prove the
  new code is live — a stale process silently serves pre-edit claims/gaps.
- chain_root ROTATES per call (re-derived with a fresh timestamp => point-in-time
  signed snapshot). The audit-DB chain_root is STABLE; the manifest root rotates.
  Don't treat a differing manifest root as breakage.

Full pattern + the 3 bugs it took to get right: references/api-driven-attestation.md.

## BLIND-SPOT ENUMERATION (classify + quantify)
When the user asks for a "full blind spot enumeration", "verify claims and quantify", or
"review what we tried" across a system or body of work, the deliverable is NOT a flat
list — it is a CLASSIFIED, QUANTIFIED enumeration. Template + the proven ZQM example:
references/blind-spot-enumeration.md.

Structure:
1. Classify every item into orthogonal buckets (e.g. Tooling/Observability · Fleet/System
   State · Remediation Pipeline · Self-Discipline). Do not dump everything into one pile.
2. Per item: status (PROVEN/OPEN/UNVERIFIED/GATED) + the live proof source (command +
   observed value).
3. Quantify: per-class counts + overall total. Undercount multiplier = ground_truth /
   tool_reported. Report both numbers.
4. Top-3 leverage: the 3 highest-leverage items to close, each with exact closure path +
   the gate that blocks it.
5. Remediation vectors: enumerate EVERY vector, class it (Applied+Verified / Gated-Blocked
   / Drafted-Open / Rejected-Dead) with a per-class count. Do NOT report only successes;
   a "DEAD" vector map prevents wasted re-attempts.

Quantification technique (prove a tooling blind spot empirically):
- Ground truth: query the authoritative store directly (state.db `SELECT source,COUNT(*)
  FROM sessions`), not the tool's capped browse/discovery.
- Undercount multiplier = ground_truth / reported. Report both.
- Prove burying/skew via corpus composition: `SELECT source, COUNT(*) FROM messages GROUP
  BY source` + avg msgs/session per source. A cron/automation-heavy corpus out-ranks
  interactive content under per-session BM25 — that is the mechanism, not a broken index.

Pitfall (self-correction, 2026-07-12): re-verify the EXACT numbers you embed in a
deliverable immediately before finalizing it. A report drafted mid-session ("ZBit+LiteLLM
DOWN, 000") was disproven by a final re-probe ("404/200/200 — manually up"). Live state
moves; the doc numbers must match a probe run in the same breath as the write.

## Verification scripts pattern (Windows/PowerShell + paramiko)
- Decrypt a LocalMachine DPAPI blob:
    Add-Type -AssemblyName System.Security
    $raw=[Convert]::FromBase64String($o.data)
    $pw=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($raw,$null,'LocalMachine'))
- Headless node reachability without WinRM: paramiko SSH with the vaulted cred.
- End-to-end writability: mount UNC WITH cred, write+read a probe file, delete, unmount.
- Self-elevating verifier guard at top of the .ps1:
    $wp=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
      Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""; exit 0 }

## Output contract
Always end with a scorecard and, for any FALSE/NOT PROVEN, the ROOT CAUSE (real failure vs
probe artifact). Do not leave the user guessing whether a red result is a bug or a measurement
error.

## Support files
- `references/zqm-connectivity-claims.md` — the 15-claim ZQM Node<->Garden ledger (statement set + observed PROVEN results + the FALSE-NEGATIVE traps that bit the first run + manifest SHA-256). Reuse as the claim template for any "verify the fabric" task.
- `references/background-process-lifecycle.md` — CORRECTED Windows background-process lifecycle: process kill did work (taskkill SUCCESS, port freed), survivor was the newest spawn, watch-pattern re-fires are zombie session records. Always prove liveness with netstat + Get-CimInstance before killing. Replaces the stale OS-survived-kills misdiagnosis fixed 2026-07-12.
- `scripts/robust_probe.py` — copy-paste live-probe helpers: bytes-consistent `tcp_probe` (no bytes/str crash), `node_is_up()` to tell node-off from service-down, and `ollama_up`/`redis_state`/`litellm_up` claim probes.
- `scripts/claim_hash_chain.py` — generic chained SHA-256 claim-ledger generator: feed a claims list, get `claim_manifest.json` + `.md` with `chain_root` and a built-in re-walk self-check.
- `scripts/repair_claim_chain.py` — canonical re-chainer for an EXISTING broken `claim_hashes` table (e.g. fleet_endpoint_audit.db). Default DRY-RUN: walks prev_hash pointers to recover true order, recomputes chain_root only (leaves prev_hash/claim_hash untouched), prints new root + contiguous check. `--apply` backs up to `claim_hashes_bak_<ts>` then rewrites chain_root. Verified 2026-07-12 (new root dbd8bc73...). NOTE: the stored prev_hash pointers were already correct — only chain_root was a stale placeholder — so the repair WALKS pointers, never rewrites them. See references/audit-chain-contiguity.md "Repair" for the walker + the 2 bugs it took to get right.
- `scripts/claims_core.py` — GENERIC compute core for an API/attestation system. `build_attestation()` is the ONLY public entry point; both the offline manifest writer and the HTTP server import it so the two delivery paths can't diverge. Ships with a demo claim set + dummy probes (runs standalone, zero deps). Replace `gather_probes()` + `build_claims()` with real probes/claims.
- `scripts/api_server_template.py` — TEMPLATE stdlib HTTP server (no fastapi/uvicorn). Imports `build_attestation()` from `claims_core.py`; serves /attest, /attest/summary, /attest/claim/<ID>, /attest/chain, /attest/probes, /audit/chain. Builds the attestation ONCE per request (calling it multiple times times out under a short-capped client). Read-only.
- `references/audit-chain-contiguity.md` — the contiguity-check procedure + the 2026-07-12 `fleet_endpoint_audit.db.claim_hashes` broken-chain finding (shared root, dangling prev_hash).
- `references/api-driven-attestation.md` — API-driven attestation pattern (stdlib HTTP server), the build-once-per-request fix, the `\'` raw-string Powershell quoting bug (distinct from the `$_` trap), and the rotating-chain_root note.

## Cross-node push (Node-1 -> Node-3/4 via OpenSSH)
When replicating the link/monitor fabric to other ZQM nodes:
- DPAPI `LocalMachine` blobs are MACHINE-SCOPED. A cred encrypted on Node-1 will NOT
  decrypt on Node-3/4. Re-encrypt the credential ON the target with its own LocalMachine
  key. Before pushing Door A (garden links), confirm the target already has its own
  `zqm-cred-garden-admin.json`; if absent, that node's garden self-heal is GATED until
  the garden password is re-entered there. (Node-3 HAS node-local cred, MISSING garden cred.)
- Transfer via `scp.exe` (OpenSSH). MSYS path translation mangles backslash dests
  (`C:\zqm\link\` -> invalid); use forward-slash POSIX dest `C:/zqm/link/` and
  `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no`.
- `Start-Process -Verb RunAs` from a headless SSH session SILENTLY NO-OPS (no UAC
  surface). To register a scheduled task on a remote node, run `Register-ScheduledTask`
  DIRECTLY in the SSH session (works if the SSH login user is admin — `zqmlocal` is
  admin on Node-3).
- Node-3 has NO python on PATH and no `py` launcher. Scripts using paramiko/ssh_probe.py
  won't run there. A node does NOT need to run the fleet-health task (Node-1 is the
  manager); it only needs the Garden self-heal (Door A). Make python paths resolve
  dynamically (`Get-Command python/py` + venv search) so scripts survive on any host.
- Prefer native `ssh.exe` for remote commands; the paramiko python client intermittently
  throws "File is not open for reading" on these hosts (post-quantum key-exchange warning,
  harmless) while ssh.exe works fine.
