---
name: local-service-verification
description: Diagnose, patch, and verify local Windows services — especially Flask/Waitress-backed indexers, uvicorn/FastAPI, LiteLLM, and Redis — using ad-hoc temp verification scripts, process hygiene, and runtime contract checks instead of claiming suite green from static checks alone.
---

# Local Service Verification

## Trigger
You are investigating or improving a local Windows service/process — any of:
- a Flask / Waitress / **uvicorn / FastAPI / LiteLLM** app (localhost listener),
- a Whoosh-backed indexer with async rebuild,
- any localhost service where HTTP endpoints expose `ready`/`search`/`stats`/`update` or similar contracts,
- **a "is this a C2 node?" question about a localhost process** — disprove via connection-egress evidence (see C2 Disproof below).
- **a Redis instance answering `PING` with `+PONG` and no `AUTH`** — run the forensic root-cause (see references/redis-forensics.md) to classify ACCIDENTAL vs BY-DESIGN before recommending a fix.
This skill covers BOTH runtime-contract verification (is the service behaving as patched?) AND security posture / C2 investigation (what is this process, who launched it, where does it talk).

## Three-Layer Investigation (the "investigate fully" verb)
When the user asks to investigate a flagged localhost process, run all three layers and persist to SQLite. Do NOT stop at one layer.

### Layer 1 — PROCESS
- Enumerate the exact PID from `netstat -ano | grep <port>`, then pull its full context:
  - `Get-CimInstance Win32_Process -Filter "ProcessId=<pid>"` → CommandLine, ExecutablePath, ParentProcessId, CreationDate, SessionId, HandleCount, ThreadCount.
  - Owner via `$p.GetOwner()` (Domain\User). NOTE: on renamed accounts (e.g. `zqmco` SID = `ZQM-Node-1\AlexZ`) the folder name ≠ SID name.
  - **Elevation check**: read process token via a tiny C# TypeAccelerator (TokenElevation class 18, TOKEN_QUERY 0x0008). `1` = admin/elevated, `0` = standard, `-1` = no access. (See references/win-process-probe.ps1 — the working template.)
  - **Parent chain**: walk ParentProcessId up to a session root (explorer/cmd/servicehost). `explorer → cmd → python` = manual desktop launch; `services.exe → ...` = service; `taskeng` = scheduled task.
  - **Scheduled-task check**: `Get-ScheduledTask | Where-Object {$_.TaskName -match "<name>"}`. NONE registered = manual launch (the ZBit stack case — both PIDs launched from `cmd 4736` → `explorer 11308`, NO scheduled task).
- Pitfall: do NOT reuse PowerShell's automatic `$PID` variable as a probe var name — it is read-only and returns the *shell's* PID. Rename to `$TargetPid`.

### Layer 2 — SERVICE
- Confirm bind address from a fresh `netstat -ano | grep <port> | grep LISTENING`. `127.0.0.1` = loopback-only (not reachable off-box). `0.0.0.0` = exposed to LAN/Internet.
- Probe HTTP contracts with curl/python urllib (always call the explicit interpreter, e.g. `C:\Users\zqmco\AppData\Local\Programs\Python\Python312\python.exe`):
  - Open routes (no key) vs gated routes (401/403). Record each code.
  - Auth posture: try with NO key, with a BOGUS key (header AND query param), and with a VALID key. Confirms whether key is enforced and where it's read from.
  - Note doc surfaces: `/openapi.json`, `/docs`, `/redoc` often serve 200 unkeyed and disclose the full schema — flag as info-disclosure (low risk on loopback, real risk if bind widens).
  - For proxies (LiteLLM): test `/v1/chat/completions` with NO key to prove open-vs-closed; check `/key/generate` (405/422 = route mounted-but-inert; 500 = feature needs DATABASE_URL).

### Layer 3 — SECURITY / C2 DISPROOF
- **The decisive C2 test = external egress.** A C2 node phones OUT to an attacker controller. Enumerate ESTABLISHED connections for the PID:
  `netstat -ano | grep <pid> | grep ESTABLISHED` then filter out loopback (`127.`, `::1`) and the local LAN subnet (`192.168.1.`).
  - ZERO non-local peers = NOT C2 (by topology). External peers on OTHER PIDs = unrelated processes, not this service.
- First-party code review: does the source do `eval`/`exec` on caller input? Are writes confined to local paths (ledger, keypair)? No exfil channel = confirms benign.
- Verdict label: **C2 = FALSE** when loopback-only + no external egress + first-party code.

## Persistence (per "investigate fully")
Persist findings to a SQLite ledger (see references/audit-schema.sql + scripts/persist.py pattern). Tables: `run_meta`, `process_layer`, `net`, `service_probe`, `verdict`. Label every finding PROVEN / NOT PROVEN / FALSE. Do not store secrets (API keys, tokens) — store only that auth is present/absent.

## Hash-Claim Ledger (drift-detectable findings)
For an "investigate fully" + "hash claims" directive, persist each headline claim as a row with a SHA-256 of `claim + status`, recomputed LIVE every re-run:
- Genesis table: `root_cause` (by-design vs accidental vs OS-default) + `by_design` flag.
- `hash_drift_log`: each run stores STABLE= / DRIFT= count. A drift = a live re-probe no longer matches the stored hash ⇒ state changed (or your checker has a bug — see pitfall below).
- Pitfall: early drift-check runs showed FALSE drift because (a) `socket.recv(200)` truncated a JSON line so the matcher missed, and (b) `"model" in text` matched the wrong substring. Fix: recv a larger buffer (1024+) and match the exact token (e.g. `"id":`). Re-run until STABLE across consecutive runs before trusting.

## "Exposed on purpose?" Genesis split (key skill)
When the user asks why something is exposed, do NOT lump all exposures together. Split:
- **BY DESIGN** — e.g. an Ollama fleet bound to LAN IPs with a comment in litellm_config.yaml ("Hot LB = N2 open"). The agent's distributed inference mesh. Acceptable for a trusted private LAN.
- **UNINTENDED-DEFAULT (NOT proven a deliberate mistake)** — e.g. Redis `bind` empty + `requirepass` empty + `protected-mode *0` (vanilla install, protective switches disabled, never hardened). Do NOT call this a "mistake"/"accidental" unless you have evidence the user TOUCHED it — absent evidence, label it "unintended-default / unhardened-default", distinct from BY-DESIGN. The user WILL correct "mistake" overstatement (seen 2026-07-11: retracted to precise language). The risk (RCE) is identical either way; only blame differs.
- **OS DEFAULT** — e.g. WinRM-HTTP (5985) open, SSH, SMB. Expected, not a misconfig.
Report the split explicitly; the BY-DESIGN ones are accepted architecture, the ACCIDENTAL one is the only item earning CRITICAL.

## C2 Disproof — Quick Checklist
1. PID listens on 127.0.0.1 only? (yes → not off-box reachable)
2. ESTABLISHED conns to non-loopback, non-LAN IP? (none → not beaconing)
3. Launched by scheduled task / service / manual? (manual desktop = user-initiated)
4. Source does eval/exec on input? (no → not RCE-capable C2 agent)
5. Writes confined locally? (yes → no exfil)
→ All yes/no as above ⇒ C2 = FALSE, PROVEN by connection state.

## Post-Restart / Reboot Resilience (RECURRING GAP — cross-session)
The single most repeated open item across the ZQM sessions (Jul 5, 11, 12): local services are
launched by hand and DIE on reboot because nothing re-starts them. This is a CLASS of work, not a
one-off fix. Encode the resilience recipe here so every session starts knowing it.

### What currently survives a reboot vs not (verified state 2026-07-12)
| Service | Port | Survives reboot? | Mechanism |
|---|---|---|---|
| zqm-node-01-indexer | :5000 | LOGON only | `ZQM-Node-01-Indexer.lnk` in Startup folder |
| Skill Automation Center dashboard | :9000 | LOGON only | `ZQM-Skill-Automation-Center.lnk` in Startup folder |
| ZBit agent | :8400 | NO | manual launch, no task |
| LiteLLM | :4001 | NO | manual launch, no task |
| Ollama | :11434 | depends on node | service on some nodes, manual elsewhere |
| Node-2/3/4 sshd + WinRM | 22/5985/5986 | YES (if bootstrap ran) | bootstrap sets Automatic; but zqmlocal pw drift can block *remote* reach after reboot |

Two distinct holes:
1. **Pre-boot (AtStartup) vs logon-only.** Startup-folder `.lnk` shortcuts fire only after a user
   logs in. For services that must be up before/without logon (e.g. the agent stack), use a
   Scheduled Task with an **AtStartup trigger** + SYSTEM principal, NOT a Startup shortcut.
2. **The agent stack has NO supervisor at all.** ZBit :8400 / LiteLLM :4001 are born from a manual
   `cmd` → `explorer` parent chain (Layer-1 check finds NO scheduled task). After any restart they
   are simply gone until a human relaunches them.

### The canonical fix recipe (verified-exists, NOT yet registered)
`C:\Users\zqmco\ZBit_api\start_zqm_stack.bat` launches the stack. `C:\Users\zqmco\swarm\fleet_endpoint_review\apply_stability.ps1`
registers a supervisor Scheduled Task:
- Task name `ZQM-Stack-Autostart`, trigger **AtStartup**, principal **SYSTEM**.
- Action runs `start_zqm_stack.bat`.
- Crash recovery: `RestartCount=3`, retry interval `1 minute` (so a transient early crash self-heals).
- Also configures `sshd` to **Automatic** start + restart-on-failure (covers the SSH-after-reboot case).
Register it ELEVATED (Run as Administrator — see windows-elevated-actions):
```powershell
# ELEVATED PowerShell
powershell -ExecutionPolicy Bypass -File "C:\Users\zqmco\swarm\fleet_endpoint_review\apply_stability.ps1"
```
VERIFY after registering (do not trust the start cmd's own stdout):
```powershell
Get-ScheduledTask -TaskName "ZQM-Stack-Autostart" | Select TaskName,State
# then reboot or `Stop-Process` the stack PIDs and confirm the task restarts them within ~60s
```

### Pitfalls specific to post-restart resilience
- **Background `terminal(background=true)` procs are session-scoped.** When the session ends the
  proc is SIGTERM'd (exit 15) and NOTHING restarts it. A scheduled-task supervisor is the durable
  fix — never treat a background launch as "running after restart."
- **UAC gate.** Registering an AtStartup/SYSTEM task from the NON-elevated agent shell is denied
  ("Access is denied" / "CIM resource not available"). Hand the one-liner above to the user to run
  in an ELEVATED PowerShell; re-verify with `Get-ScheduledTask` afterward (windows-elevated-actions).
- **LogonUser 1326 vs remote REJECT confusion** carries over: if a node's `zqmlocal` password was
  typed differently at bootstrap than what's vaulted, sshd may be Automatic but the vaulted cred
  still REJECTS post-reboot — re-run the bootstrap password-reset one-liner on that node's console
  before assuming the node is "managed."
- **`Start-Process -Verb RunAs -Wait` lies.** On a cancelled UAC prompt it reports success; always
  re-verify the task/state after the elevation attempt (windows-elevated-actions).

### Win11 OpenSSH install — dism.exe fallback (pitfall)
When bootstrapping a Windows 11 node, `Get-WindowsCapability -Online` / `Add-WindowsCapability`
can throw **`Class not registered`** (REGDB_E_CLASSNOTREG). That is a BROKEN PowerShell Dism module
COM registration on that host — NOT a Windows-version gap, and NOT "OpenSSH isn't available." Fix:
call the **native `dism.exe` binary**, which does not use the broken PS COM class:
```powershell
# elevated, on the target node
dism.exe /online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0
Set-Service sshd -StartupType Automatic
Start-Service sshd
New-NetFirewallRule -DisplayName "ZQM-OpenSSH-22" -Direction Inbound -LocalPort 22 -Protocol TCP `
  -Action Allow -Profile Any -RemoteAddress 192.168.1.0/24
```
Order matters in any bootstrap script: check `Get-Service sshd` FIRST (no Dism dependency); only
call the capability install if sshd is absent; wrap the Dism PS provider in try/catch and fall back
to `dism.exe`; wrap the whole OpenSSH block in try/catch so a Dism failure does NOT abort the rest
of the bootstrap (Cert: mount, WinRM, etc.).

### Windows SMB write gap (pitfall — Synology Garden shares)
To drop a file onto a ZQM-Garden NAS SMB share (`\\192.168.1.173\web\`) FROM this agent host:
- **`write_file` tool with a `//` UNC path SILENTLY FAILS** (MSYS path translation), and
  **`cmd /c copy` to the UNC path SILENTLY FAILS** too. No error surfaces — the file just isn't there.
- **ONLY native PowerShell `Copy-Item` works:** `Copy-Item local.ps1 -Destination '\\192.168.1.173\web\local.ps1'`.
  Run it via the `terminal` tool with a PowerShell wrapped command, not via write_file.
- Verify with a PowerShell read-back (`Get-Content '\\192.168.1.173\web\file.ps1'`) — do NOT trust the
  write tool's "success" return when the dest is a `//` UNC path.
- Separate stores: the HTTP web root (`http://ZQM-Garden-01/...`) is often DECOUPLED from the SMB
  `web` share — a file you SMB-put may not be what nodes fetch over HTTP. Confirm which store the
  node actually pulls from before assuming your upload landed.

## Reusable Assets (under this skill)
- `references/win-process-probe.ps1` — Layer-1 probe: CIM process context, **elevation via C# token snippet**, parent-chain walk, scheduled-task check. Includes the `$TargetPid` (NOT `$PID`) fix.
- `references/audit-schema.sql` — Layer-1/2/3 SQLite schema + C2-egress helper query. Persist every finding; label PROVEN / NOT PROVEN / FALSE; no secrets.
- `references/three-layer-probe.py` — combined runner: process (via ps1) + netstat egress filter + HTTP auth probes + writes to the audit DB. Copy, set PIDs/ports, run.
- `references/redis-forensics.md` — Redis UNAUTH forensic root-cause (raw-socket CONFIG GET, no redis-cli). Classifies UNINTENDED-DEFAULT (bind empty + requirepass empty + protected-mode *0) vs BY-DESIGN, and flags the reliability hazard.
- `references/redis-live-auth.md` — LIVE-AUTH recipe: close RCE from a remote unauth session via `CONFIG SET requirepass` (immediate), the v3.0.504 startup-only caveat for bind/protected-mode, consumer-trace-first, pass-hygiene.
- `references/windows-launch-verify-pitfalls.md` — LiteLLM.exe PE-launcher gotcha, git-bash `start` mangling, premature "verified" after restart, bash quote-mangling, change-verification hook.
- `scripts/redis_trace.py` — re-runnable read-only Redis trace. `python redis_trace.py <host> <port>`. Pulls CONFIG/INFO/CLIENT LIST to prove live exposure + genesis.
- `references/post-restart-resilience.md` — post-reboot survival recipes: the unregistered `ZQM-Stack-Autostart` supervisor task (AtStartup/SYSTEM + 3-retry crash recovery), logon-vs-pre-boot gap, Win11 `dism.exe` OpenSSH fallback, Synology SMB-write wrapper, and the post-reboot fleet re-probe checklist.

## Core Principles
1. **Ad-hoc verification first.** There is no canonical test/lint/build. Create a temporary verification script under `%LOCALAPPDATA%\Temp` with a `hermes-verify-` filename prefix. Use `tempfile.gettempdir()` so paths resolve safely from both PowerShell and git-bash. Copy it into the project for execution, run it, then remove the repo-local copy when done.
2. **Verify the live runtime contract, not in-memory imports.** Refresh caches before checking HTTP endpoints. If `/api/stats` or `/api/health` returns old cached data after a patch, force a cache invalidation or restart the process that serves stale code.
3. **One live process only.** If `process.list` or `netstat` shows multiple listeners on the same port, kill duplicates before restarting. Document PID, port, and status after restart.
4. **Windows/MSYS shell hygiene.** In git-bash/MSYS:
   - Use POSIX commands (`cat`, `grep`, `sed`, `cp`) for text and process control.
   - Do NOT use PowerShell builtins (`Get-ChildItem`, `$env:FOO`, etc.) from the terminal.
   - Python invocations from git-bash may default to the global interpreter; always call the project venv explicitly, e.g. `.venv/Scripts/python.exe`.
   - For Windows file paths in commands, prefer quoted POSIX paths (`/c/Users/...`) over backslashes that get mangled by bash.
5. **Never claim green from static evidence alone.** `py_compile` success, syntax-only checks, and imports in-process are necessary but not sufficient. Always append a concrete runtime verification summary to the user.
6. **Re-probe LIVE after every restart.** A service that "started" in a `start`/foreground command may be dead 5s later. Re-check `netstat` LISTENING + an HTTP contract after a 5–10s settle, before reporting applied/verified. (See references/windows-launch-verify-pitfalls.md.)

## Verification Workflow
```text
1. Write `C:\Users\<user>\AppData\Local\Temp\hermes-verify-<topic>.py`.
2. Verify the on-disk source actually reflects your latest patch: check `git diff HEAD <file>` after any `git checkout -- <file>` to detect partial-revert state.
3. Copy it into the repo tree for execution if needed; use quoted POSIX paths (`cp "source" "dest"`) from git-bash.
4. Run it under the project venv.
5. Remove the repo-local copy when the user explicitly asks; keep the Temp copy unless the user wants it removed.
6. After runtime HTTP checks, always verify the PID from `netstat` corresponds to a fresh process, not an old one serving stale code.
7. Summarize as ad-hoc verification with explicit pass/fail counts and the exact contracts checked.
```

## Service Restart Protocol
```text
1. `process.list` to identify every running instance.
2. `process.kill` for every duplicate or stale instance.
3. `netstat` to confirm the port is free.
4. Start a single background instance via `terminal(background=true, notify_on_complete=true)`.
   (Do NOT use git-bash `start /min` — it mangles quoting and the detached
   process dies with the bash subshell. See windows-launch-verify-pitfalls.md.)
5. Wait/poll for readiness; confirm with `curl -s http://127.0.0.1:<port>/api/health`.
6. Re-probe the live HTTP contract 5–10s after start — do not trust the start command's own stdout.
7. Summarize as ad-hoc verification with the live PID, bind, and contract result.
```

## Cached State Pitfalls
- Flask `@lru_cache` helpers must be invalidated when underlying files change (`_invalidate_caches()` before re-running checks).
- A stale process PID can still serve old code long after you edit files; kill + restart is the reliable reset.
- Background jobs may queue but never update manifest on disk if the job is dropped on restart; verify `/api/update/<job_id>` and `/api/stats` after each state change.
- When a Whoosh index has real docs but `/api/stats` shows empty manifest values, prefer a stats fallback to `searcher.doc_count()` in the API layer rather than relaunching a long-running scan just to refresh display numbers.

## Manifest/Stats Fallback Pattern
If the index service has a populated index but empty manifest stats (`total_files=0`, `indexed_files=0`), prefer a lightweight fallback in `get_index_stats()` over relaunching a heavy rebuild. In Whoosh-backed services:
- Load `config.json` once with a temporary best-effort recovery path instead of depending on stale or mangled cache state.
- Fall back missing manifest counts to `searcher.doc_count()` only when the stored value is missing or None; do not overwrite real counts with the index count on normal operation.
- Preserve real manifest data when present; rehydrate missing keys from the live index.
- Verify via `/api/stats` that `config.indexed_files` and `config.total_files` reflect reality, not stale zeros.
- If the process is serving old code after a patch, kill and restart it before checking HTTP contracts.
- **Edited source != live runtime on Windows** — saving `app.py`/`service.py` does not reload an already-running Flask/uvicorn/Waitress process. Even if `py_compile` and import-only checks pass, HTTP can still return old cached logic. After patching runtime code, restart the managed process and verify with fresh `netstat` and `/health`/status-endpoint checks before declaring the edit effective.
- **Manifest/index desync** — a Whoosh/Lucene-style index can grow while `config.json`, manifest rows, or `metadata.db` stay stale. If `indexed_files` is `0` while `document_count` is nonzero, patch `get_index_stats()` to fall back to live index counts rather than relaunching a heavy rebuild just to restore display numbers. If the app still serves old code, restart it first.

## Async `/api/index` Pattern
When asked to "fix async loads" on the indexer, do not paper over a blocking endpoint with `time.sleep` or in-process threading. Convert a sync route like `/api/index` into a true `202 Accepted` path: the request stores a job with `rebuild` in `_UPDATE_JOBS`, launches `_start_background_update(job_id, rebuild=...)`, and returns immediately. Worker threads consume `rebuild` from that job state. Enforce creation order: queued state first, `rebuild` stored, thread spawned, then start. Verify with:
- `curl -X POST http://127.0.0.1:5000/api/index` returns HTTP 202
- `/api/update/<job_id>` shows `queued` then `running` then a terminal state
- `/api/search` still works while a rebuild is in progress

## Flask Background Thread Pitfall
A common breakage pattern in patched Flask indexers: `_start_background_update()` writes queued state, then references `_bg_pool` and worker `t` before creating the `threading.Thread()`. If you see `NameError`, missing args on worker start, stale rebuild=false, or duplicated inline redefinitions of the same function, reset the helper to:
1. create job dict with `rebuild`
2. create thread with target worker and `args=(job_id,)`
3. append to `_bg_pool`
4. call `t.start()`
Out-of-order edits here cause silent no-op rebuilds or immediate failed jobs.

## Enablement Sequencing for Council/Sidecar Services
If the user says `all of the above`, do not blur dependencies. Sequence them and report state explicitly:
1. PowerShell `run_council.ps1` — verify parseability before offering execution. If the script is broken in `HEAD`, report the exact parse failure and offer a clean replacement; do not silently rewrite committed scripts.
2. Service/daemon mode — start if importable; confirm `/health` and rapid endpoint smoke checks.
3. API integration — implement after 1 and 2 because integration depends on a stable service surface.
When both the PowerShell path is broken and the FastAPI service is running, state that clearly: one path is live, another is blocked.

## PowerShell Script Hygiene
- Before running `run_council.ps1`, inspect for inserts of non-PowerShell content after the active script body. Duplicate `.DESCRIPTION` blocks or stray markdown/bullets after line 250 indicate a broken merge and will fail with `Missing statement body after keyword`.
- Do not invoke broken committed scripts blindly; report the failure mode and offer a replacement.

## Windows Service Bindings and Runtime Behavior
When a service is listed in `netstat` and returns `200` on `/`, do not declare transport healthy until you test its **application-level contract**:
- ComfyUI on 8188 can serve `/` but reject prompts as `prompt_no_outputs`; that is healthy transport, not broken, but an empty/minimal `/prompt` probe is required to confirm the prompt handler is reachable.
- If a service starts but is immediately refused afterward, inspect startup logs as well as `user/comfyui_8188.log`/rotated logs; runtime handler crashes often do not surface a stack trace to stdout unless the service is run in foreground with redirected output.
- On Windows, git-bash shells often lack `wmic`. Use `psutil` from Python to enumerate processes by cwd/cmdline and map ports to PIDs.

## Broadcast vs Local Binding Pitfall
A Flask/Waitress service bound to `127.0.0.1` will respond to `http://127.0.0.1:<port>` but will fail on LAN-IP probes (`192.168.x.x`). If remote access is required:
- preference order: reinstall service with `0.0.0.0` bind in its launch code/PowerShell scheduled task/install script;
- verify with both loopback and LAN-IP HTTP probes;
- note OneDrive/Desktop install scripts separately because recent indexer setups use Desktop paths that conflict with `.local` paths under Hermes config.

## ComfyUI Prompts as Smoke Tests
- `prompt_no_outputs` from `/prompt` means the endpoint executed validation and found no outputs in the provided workflow; it is not an exception. Use it only as transport smoke.
- For real execution validation, use a known-good workflow JSON with at least one output node and a valid checkpoint reference.

## Redis UNAUTH Forensic Root-Cause
When a Redis answers `PING` → `+PONG` with no `AUTH`, it is live-exposed. Run `scripts/redis_trace.py <host> <port>` (read-only, no redis-cli) and read references/redis-forensics.md. Classify:
- `bind` empty + `requirepass` empty + `protected-mode *0` → **UNINTENDED-DEFAULT** (vanilla install, protective switches off; NOT a proven "mistake" unless user touched it).
- Compare against an INTENTIONAL exposure (Ollama fleet on LAN IPs with a config comment) = BY DESIGN.
Flag both CRITICAL (RCE: CONFIG SET dir, MODULE LOAD, FLUSHALL) and the reliability hazard (any LAN host can wipe it).

### Redis LIVE-AUTH — close RCE without node cred (NEW 2026-07-11)
You CAN harden from a remote unauth session BEFORE creds exist:
- `CONFIG SET requirepass <48-hex>` → takes effect IMMEDIATELY (no restart). Now every unauth cmd → `NOAUTH`. **RCE closed from LAN right then.**
- Then `AUTH <pass>` on the SAME socket, continue: `CONFIG SET protected-mode yes` + `CONFIG SET bind 127.0.0.1` — BUT on Redis **v3.0.504 (Windows/Memurai build)** these two are REJECTED live (`-ERR Unsupported CONFIG parameter: bind`). They are startup-only → must go via redis.windows.conf + service restart (needs node cred).
- Firewall `Block-<svc>-LAN` (deny 6379 from 192.168.1.0/24) is defense-in-depth, also needs node-side run.
- NEVER print the pass into a persisted file; display once, operator stores on the node. See references/redis-live-auth.md.
- Trace the consumer FIRST (read-only): if NO fleet process references node:port (only venv libs e.g. apscheduler/elasticache examples), it is an orphan → safe to lock with zero breakage. (N2 Redis had only my own orphaned probe socket; nothing legit used it.)

## LiteLLM / uvicorn Launch Pitfalls (NEW 2026-07-11)
- **litellm.exe is a self-bootstrapping PE.** NEVER run `python.exe litellm.exe` — Python tries to import the .exe as a module → `No module named litellm`. Run the exe DIRECTLY: `C:\path\venv\Scripts\litellm.exe --config ... --host 127.0.0.1 --port 4001`. (git-bash `start /min "exe" args` mangles quoting and the detached proc dies with the bash subshell — use `terminal(background=true, notify_on_complete=true)` instead.)
- **litellm 1.91.2 SELF-REWRITES litellm_config.yaml on boot.** When the proc is SIGTERM'd mid-rewrite (e.g. background session reaped, exit 15), the next launch reads a transient partial file → `KeyError: 'model'` in load_config. NOT your config's fault (YAML parses clean, all entries valid). Fix: wait for settle, relaunch; litellm normalizes the file on successful boot. Verify with a live `/v1/models` 200 after 8s, not the start cmd's own stdout.
- **Background terminal procs are session-scoped.** When the session ends / proc exits (exit 15 = SIGTERM), nothing restarts it → service dies silently. This is the autostart gap: a scheduled-task supervisor (run elevated via windows-elevated-actions) is the durable fix, not a background launch. After ANY restart, re-probe `netstat LISTENING` + an HTTP contract 5–10s later before reporting applied/verified.

## Who is calling my localhost service with bad params (400 trace)
When a loopback service logs `400: Invalid model name` / `ProxyModelNotFoundError` with a model name you did NOT configure (e.g. raw `qwen3:8b` / `deepseek-r1:1.5b` hitting a LiteLLM proxy that only knows `zbit-*` virtual names), find the CALLER before assuming a config break:
1. `netstat -ano | grep :<port> | grep ESTABLISHED` → capture the LOCAL (client-side) PID.
2. `Get-CimInstance Win32_Process -Filter "ProcessId=<pid>"` → `CommandLine` reveals which script/app sends the bad request.
3. If no ESTABLISHED conn at probe time, the caller was TRANSIENT (connected, got 400, disconnected). Grep the service log timestamp and correlate with recently-run scripts (e.g. a stray `verify_full.py` / `integrate_fleet.py` in an old worktree — these often carry raw model names the proxy rejects).
Verdict rule: loopback-only + the bad name is YOUR fleet's OWN base model (not an attacker's) ⇒ a stray/misconfigured client on the same host, NOT C2/intruder. The proxy correctly 400s; harmless. (This is C2-disproof from a different angle: wrong-param 400s from loopback = own client, not egress.)

## Wrong-config-file pitfall (verify which file the RUNNING process loads)
When you edit/probe a service config, NEVER assume the similarly-named file in a nearby dir is the one in effect. Multiple worktrees often carry near-duplicate configs:
- The live config is the one the RUNNING proc loads — read it FROM THE PROCESS: `Get-CimInstance Win32_Process → CommandLine` shows `--config C:\...\litellm_config.yaml`. Edit/verify THAT path.
- A sibling dir may hold `litellm_config.integrated.yaml` (350-line variant with deepseek-r1:70b/gemma entries) that the live 60-line `litellm_config.yaml` does NOT use. Reading the integrated variant and believing it's the live config produces wrong conclusions.
- ALSO: litellm 1.91.2 SELF-REWRITES its config on boot (see launch pitfalls). After a successful boot, the on-disk file is litellm's normalized version — diff it against what you wrote before concluding your edit "didn't take".
Always derive the config path from the process cmdline, then read THAT file. Re-verify via the running service, not file inspection alone.

## Output Requirements
- Always include: live process PID, port, bind address, health HTTP status, transport contract checked / application contract checked, manifest hit counts.
- Do not say "service running" without sourcing it from a fresh `netstat` / HTTP probe in the current turn.
- State whether the verification is ad-hoc (it always is here).
