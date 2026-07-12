# Identify an unknown listening port / service (Windows, MSYS/bash host)

Use when a stray `LISTENING` line or a "Started server process [N]" / uvicorn log
appears and you must name the owning service, who launched it, and whether it is
first-party. PROVEN live 2026-07-11 on the :8400 "ZBit Agent API" case (a
re-homed first-party agent runtime, loopback-bound, key-gated — benign).

## Recipe
1. Map port -> PID (bash):
   `netstat -ano 2>/dev/null | grep -i :<port>`
2. Pull the process. Write a `.ps1` and run with `-File` (never inline
   `powershell -Command` with loops/vars — MSYS still mangles `$`):
   ```powershell
   $TargetPid = <pid>
   $p = Get-CimInstance Win32_Process -Filter "ProcessId = $TargetPid"
   $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.ParentProcessId)"
   $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner
   $ownerStr = "$($owner.Domain)\$($owner.User)"
   # emit: $p.CommandLine, $p.ExecutablePath, $p.CurrentDirectory,
   #       $parent.CommandLine, $p.CreationDate, $p.SessionId, $ownerStr
   ```
3. Walk the parent chain to attribute launch:
   - `cmd.exe` -> `start_x.bat` = manual/script launch
   - ScheduledTask host process = auto-start (verify: `Get-ScheduledTask | Where-Object { $_.TaskName -match 'x' }`)
   - Startup `.lnk` = logon auto (verify by listing the two Startup folders)
4. Name the service: read the CommandLine entrypoint (`app:app`, `litellm --config`,
   `ollama serve`). For FastAPI/uvicorn hit `/openapi.json` (title + routes) and
   `/health` (open status) to enumerate the API surface + auth model.
5. Grade: `127.0.0.1` bind = not off-box reachable; `/health` open + `401` on
   everything else = fail-closed auth (good); REGISTRY of named functions
   (no eval/exec) = contained write blast radius.

## Gotchas (both hit live)
- **`$PID` is a read-only automatic variable** (case-insensitive).
  `$pid = 1908` -> `Cannot overwrite variable PID because it is read-only or
  constant`. Rename to `$pId` / `$TargetPid`.
- **`CimInstance` has no `.InvokeMethod()`**. `$p.InvokeMethod("GetOwner", $null)`
  -> `MethodNotFound`. Use the cmdlet: `Invoke-CimMethod -InputObject $p -MethodName GetOwner`.
- **Two `python.exe` for one uvicorn = parent + worker, NOT a fork bomb.**
  The parent (venv python) spawns the worker that actually binds the port. Count
  distinct `CommandLine` entries, not PID count.
- Inline `powershell -Command` with `$` loops/variables still gets mangled by MSYS
  bash even outside heredocs — write the `.ps1` with `write_file` and run `-File`.

## C2 DETERMINATION (HIT 2026-07-11, "are these c2 nodes?" question)
When the user asks whether a discovered LOCAL service is command-and-control malware, the
decisive evidence is the CONNECTION TOPOLOGY, not the service name. A first-party/local agent
is NOT C2 when ALL hold:
  (1) it binds LOOPBACK-ONLY — `netstat -ano` `LISTENING` shows `127.0.0.1:<port>`, NOT
      `0.0.0.0`/LAN-IP;
  (2) it holds ZERO `ESTABLISHED` connections to non-local IPs — grep its PID's conns and expect
      only `127.0.0.1` self-pairs (a uvicorn worker↔local call);
  (3) it initiates NO egress to external/foreign IPs.
Live proof this session: ZBit-stack PIDs 1908/19120 showed only `127.0.0.1 ↔ 127.0.0.1` pairs
and the non-loopback egress grep was BLANK — definitively NOT C2.
TRUE C2 hallmarks (absent here): outbound beacon to a foreign/external IP on a non-standard
port, periodic polling, encrypted exfil channel.
Also: cross-service 404 noise on a co-located stack = misrouted LOCAL client, not C2 (see
evolving-state-reprobe.md). Don't mistake "unexpected service" for "malware" — name it via this
recipe, grade it via agent-service-log-audit.md, confirm with topology before any C2 claim.
Second reading of "are these C2?" (e.g. "is the DNS root/RIR/ccTLD infrastructure C2?") is
category confusion: those are public registries under published policy, not malware — answer
plainly.

## LIVE EXAMPLE (2026-07-11, :8400)
- netstat: `TCP 127.0.0.1:8400 LISTENING 1908`.
- PID 1908 = `python.exe -m uvicorn app:app --host 127.0.0.1 --port 8400`, owner ZQM-NODE-1\zqmco.
- Parent chain: cmd.exe -> `C:\Users\zqmco\ZBit_api\start_zbit.bat` -> venv python (5312) -> uvicorn worker (1908).
- `Get-ScheduledTask` ZBit* = empty => manual launch (consistent with app.py header "Service is NOT auto-started").
- `/openapi.json` => title "ZBit Agent API v0.1.0"; routes health + /v1/*.
- `/health` open; `/v1/agent/status` => 401 with no key AND with wrong key => fail-closed auth.
- Verdict: first-party re-homed ZBit agent runtime, loopback-only, key-gated, no eval/exec, writes confined to local ledger + keypair. LOW risk / benign.
- Persisted to SQLite: `C:\Users\zqmco\swarm\uvicorn8400\zbit8400_audit.db` (run_meta/services/probes[10]/open_questions[4]).

## MULTI-PASS FOLLOW-UP (the "investigate further" shape, capstone 2026-07-11)
When the user pastes MORE logs after the first pass (or the SAME service re-logged), do NOT restart
the identify-from-scratch dance. Extend the existing ledger and sweep for the surfaces the FIRST
pass didn't hit. The recurring gaps in a key-gated FastAPI service:
- **Doc-route disclosure sweep** (often missed on pass 1 because the first probe only checks
  `/openapi.json`): hit `/docs`, `/redoc`, `/openapi.json` with NO key. All three return 200 on a
  stock FastAPI app and render the full schema incl. the authenticated POST write routes.
  `GET /` → 404 (harmless). `GET /v1/models?api_key=bogus` → 401 (GOOD: header-only key).
  `GET /v1/models/` (trailing slash) → 307 (harmless RedirectResponse). `OPTIONS /v1/models` → 405
  (no wildcard CORS — good).
- **Both-directions auth**: after pass 1 proved 401-without-key, ALSO prove 200-WITH-key on a read
  AND a POST write, then READ THE BACKING STORE to confirm the write landed (see the WRITE PROOF in
  `zqm-zbit-agent-topology.md`). 200 alone is not proof of a real write.
- **Ledger extend, not reset**: append new probes to the SAME service db (zbit8400_audit.db grew
  10→17→20 across 5 passes); mark open_questions RESOLVED as new logs close them (Q1 resolved by the
  capstone log showing the intended authenticated workflow). For a DIFFERENT backing service in the
  same paste (e.g. LiteLLM proxy), open a SIBLING db (litellm4001_audit.db) — don't merge.
