---
name: windows-host-audit
description: Audit / inventory a Windows host (desktop or homelab node) from Hermes's
  git-bash/MSYS terminal — hardware/OS, network, services/security, and software/toolchain
  — emitting REAL numbers, never inferred. Covers the PowerShell-from-MSYS quoting
  gotcha, a read-only CIM/registry command bank, and the parallel multi-agent "council"
  pattern for deep audits.
metadata:
  hermes:
    related_skills:
    - audit-sqlite-sink
    - data-eda
    - hermes-cron-ops
    - homelab-backup
---

# Windows host audit (git-bash / MSYS under Hermes)

Use this whenever the task is "learn about / inventory / audit this Windows
machine" — one-off or fleet-wide. The deliverable is verified live output,
not a description of one.

## 0b. Audit-depth ladder (USER VOCABULARY — drive the right scan)
This user escalates audit depth with specific verbs. Map each to a scan tier so you
don't under- or over-scope:
- **"diagnostics" / "endpoint review"** → SURFACE tier. Live state of the
  headline items only (services, ports, firewall, posture). One pass, no deep dive.
- **"full silent recon" / "silent recon" / "read them all"** → FULL DUMP tier.
  Comprehensive read-only enumeration (system, procs, svcs, net, fw, users,
  shares, software, tasks) dumped to a file. ZERO mutations, NO UAC. This is
  the `silent_recon_skeleton.ps1` tier.
- **"explore deeply"** → DEEP tier. Go PAST the surface: every listening port
  mapped to its real process PATH + command line + parent; all scheduled-task
  internals (actions + triggers), RESOLVE `.vbs`/`.lnk` to real targets
  (e.g. OpenClaw `gateway.vbs`→`gateway.cmd`); WSL/Docker state; attempt
  Defender-exclusion read (note DENIED-if-non-elevated); scan interesting dirs
  (`.ssh`, `.ollama`, `.openclaw`, `Documents\bounty-tools`, and any
  `quarantine\*` folder). **A `quarantine\*` / "CONTAMINATED"-named folder is USUALLY A
  DEFENDER FALSE-POSITIVE on the user's own agent knowledge base** — verified 2026-07-11:
  `C:\Users\zqmco\quarantine\CVG-CONTAMINATED-Zbit-Knowledge-Base\` held the ZBit/agent KB
  (USER/SOUL/LESSONS_LEARNED/BEACON_MAP/SSH_OPERATIONS), 100% benign first-party memory wrongly
  quarantined (which is WHY the Defender exclusion on `Documents\bounty-tools` exists). READ the
  folder's contents to CONFIRM benign before flagging it as contamination — do not assume
  "CONTAMINATED" means malicious. This is the `deep_recon.ps1` tier below.
- **"forensic science recreation" / "investigate fully"** → RECREATION tier.
  INDEPENDENTLY RE-DERIVE every prior claim from scratch into a fresh capture,
  then DIFF against the earlier report to catch your OWN errors (this session a
  forensic re-capture caught a duplicate WinRM 5985 firewall rule that the
  first pass had "resolved" — see windows-elevated-actions P6). Recreation is
  the user's explicit corrective mechanism; never skip it when they say
  "forensic" or "investigate fully".
- **"investigate fully" on an ALREADY-audited system** → DEPTH / CLOSURE pass,
  NOT a fresh council fan-out. Re-verify each still-OPEN open_question against
  live output LEAD-ONLY (e.g. `sshd -G` to close a password-auth question;
  Windows FW block>allow precedence to close an external-block question — see
  §2d). Do NOT re-dispatch leaves: the breadth is already mapped and fan-out
  risks leaf 429 + re-covering ground already done. Recreation (above) still
  applies to every claim you re-derive. This session closed Q10 + Q8 this way.

KEY SEMANTIC: "silent recon" / "explore deeply" / "diagnostics" / "read them all"
= READ-ONLY OBSERVATION. Do NOT write to the ledger, remediate, or change
config. "investigate fully" = read-only + APPLY the previously-approved mutations
(council→SQLite pattern). "read them all" on keys/shares/ledger = dump the
FULL verbatim list incl. retracted entries, never summarize away.

Reusable: `scripts/deep_recon.ps1` (DEEP tier — process cmdline + parent +
full socket→process map + service binaries + scheduled-task internals + OpenClaw
.vbs resolution + WSL/Docker + Defender-exclusion attempt + interesting-dir scan +
exposure notes; pure read-only, uses `-f` formatting so literal `[` brackets
never abort the script, P7 in windows-elevated-actions). Also `scripts/host-storage-net-audit.ps1`
(§2c one-shot) and `scripts/repair-broken-startup.ps1` (§2a).

## 0. The MSYS → PowerShell quoting gotcha (read this first)
From git-bash, `powershell.exe -Command "..."` with **double quotes** lets
bash expand `$_`, `$()`, `${...}` BEFORE PowerShell sees it. Result: commands
silently corrupt (we once saw `count` and `===` thrown as unknown cmdlets
because bash ate `$_` and merged echo lines).

TWO safe patterns:
1. **Single-quote the whole PS command** (bash won't touch `$`):
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '(Get-Service | Where-Object {$_.Status -eq "Running"}).Count'`
2. **Write a `.ps1` and run `-File`** (cleanest for multi-line / loops):
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File inv.ps1`
   then delete the temp script. NOTE: `-File` runs WITHOUT your profile and
   lacks the `Cert:` PSDrive — fine for read-only inventory, not for cert work.
   **PATH TRANSLATION (critical):** MSYS mangles Windows paths passed to PS.
   - `powershell ... -File C:\\Users\\zqmco\\inv.ps1` → PS sees `C:Userszqmcoinv.ps1`
     (backslashes stripped) → "file does not exist" error 127.
   - `powershell ... -File /c/Users/zqmco/inv.ps1` → also fails ("does not exist").
   [2026-07-10 ZQM-NODE-1: forward-slash MSYS paths like
   `-File C:/Users/zqmco/proc_probe.ps1` WORKED — try that first; only fall
   back to `cygpath -w` if you hit a 'file does not exist' / backslash-strip error.]
   Translate with `cygpath -w` so PS gets a proper `C:\\...` path:
     ```
     runps() { local w=$(cygpath -w "$1"); powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$w" 2>&1; }
     runps /c/Users/zqmco/inv.ps1
     ```
   This is the reliable pattern for multi-section audits (write one .ps1 per
   domain, run each through `runps`).

   **PowerShell-from-this-shell scripting pitfalls (hit live this session):**
   - `$HOME` is a READ-ONLY automatic variable in PowerShell — assigning to it
     (`$home = $env:USERPROFILE`) throws "variable is read-only". Use
     `$env:USERPROFILE` instead.
   - An inline `if/else` INSIDE a string expression — `"$(if($x){'a'}else{'b'})"`
     — throws a PS 5.1 parser error ("Missing statement block after if"). Assign
     first: `$v = if ($x -is [PSObject]) { '[obj]' } else { "$x" }`, then put
     `$v` in the string.
   - `Get-Process -match 'python'` does NOT match `pythonw.exe`; enumerate
     `$_.Name -eq 'pythonw.exe'` separately when auditing bots/automations.
   - **Literal `%` next to a `{N}` `-f` placeholder breaks the parser**
     (`You must provide a value expression following the '%' operator` — PS reads
     `%` as the ForEach-Object operator). Compute pct into a var, keep `%` out
     of the `-f` string. Also: keep `.ps1` ASCII-only — em-dash/curly quotes
     throw `Missing closing '}' in statement block`. See
     `windows-powershell-from-bash` for the full authoring-gotchas list.

   **Removed tooling:** `wmic` is GONE in Windows 11 24H2 (build 26200) — it
   returns exit 127 ("command not found"), not an error message. Never reach for
   it on these hosts; use `Get-CimInstance`/CIM cmdlets (Win32_Processor,
   Win32_PhysicalMemory, Win32_VideoCommand, Win32_VideoController,
   Win32_DiskDrive, Win32_StartupCommand) instead.

   **0c. MSYS `/tmp` ≠ native-tool temp — a real failure this session.** git-bash's
   `/tmp` is NOT where native `python.exe` / `curl.exe` / `powershell.exe` resolve
   paths. Writing a `.py` to `/tmp/redis_ping.py` then `python /tmp/redis_ping.py`
   → `can't open file 'C:\tmp\redis_ping.py'` (No such file). Likewise
   `head -c 200 /tmp/foo.body` can fail because the file was written via a Windows
   root like `/c/Users/...`. Two safe habits:
   - Write any script the agent will RUN to a **native absolute Windows path**
     (`C:\Users\zqmco\AppData\Local\Temp\`) and invoke it as
     `python "C:/Users/zqmco/AppData/Local/Temp/x.py"`.
   - Capture command output to `%LOCALAPPDATA%\Temp\` (i.e.
     `C:\Users\zqmco\AppData\Local\Temp\`), never `/tmp`. MSYS-only tools
     (bash, `read_file`, `search_files`) CAN see `/tmp`; cross-boundary native
     tools CANNOT — so a file written one way may be invisible the other way.
   - Equivalent trap inside one bash invocation: `curl -o /tmp/x.body` succeeds
     for curl, but a later `head /tmp/x.body` can still fail if a python step
     wrote to a Windows root instead. Use ONE shared Windows path for both write
     and read.
   Reusable read-only recon scripts under `scripts/`:
   `win_listener_proc_map.py` (bulk netstat listener → process path + parent),
   `redis_auth_probe.py` (raw RESP PING → `+PONG` = unsecured). Checklist:
   `references/exposure-recon-checklist.md` (5-area read-only exposure recon).

ALWAYS pass `-NoProfile -ExecutionPolicy Bypass` from the agent console:
the user's interactive profile (scoop + starship) is NOT loaded for `alexz`
and references `scoop\\shims` that aren't installed → bare `-Command` can
error on profile aliases. `-NoProfile` sidesteps that.

For clean text out of PS, append `| Format-List | Out-String).Trim()` or
`| Format-Table -AutoSize | Out-String).Trim()`.

## 1. Council pattern (preferred for deep audits)
The user explicitly prefers a PARALLEL multi-agent council for deep infra
audits ("investigate fully with the councils"). Do it:
- `delegate_task` with a `tasks` array of 2–3 **leaf** agents (max 3
  concurrent on this account). Give each a tight domain + the MSYS/PS
  quoting rules above + "read-only, emit real numbers with commands".
- Domains that work well: (a) Hardware & OS, (b) Network & Connectivity,
  (c) Software & Toolchain. The LEAD runs the 4th domain itself (Security &
  Services) so it has live control of that data while the leaves run.
- **Lead MUST re-verify headline numbers** against live output before
  reporting: in this session a leaf reported "Windows 10" from
  `Get-ComputerInfo`; the lead corrected it to **Windows 11** via
  `Win32_OperatingSystem.Caption`. Leaf summaries are self-reports, not
  facts.
- **A council can refute YOUR OWN prior claims — re-verify live and CORRECT the
  ledger, don't just absorb or reject.** In the 2026-07-11 swarm, Council 2
  claimed "N1 does NOT require a key" — directly contradicting the lead's own
  F54/F57 ("N1 requires a key / 401 on N1"). The lead re-tested live (N1
  no-key/sk-na/wrong-key all → 200) and found the COUNCIL WAS RIGHT: the lead's
  earlier `000` was a cold-load timeout misread as "rejected". Lesson: a
  subagent refutation is not automatically true NOR automatically false — run
  the authoritative live probe yourself, then UPDATE any finding that was wrong
  (mark CORRECTED, record the refutation + your re-proof). This is the single
  most valuable council discipline: the swarm catches the lead's own errors.
- **"Swarm of councils" is a standing user trigger.** When the user says "add
  swarms of councils" / "use the councils", dispatch a 3-leaf parallel batch
  (max 3 concurrent on this account) on distinct domains, pre-seed each with
  the netstat/regex/redaction/read-only gotchas, then LEAD-reverify every
  headline claim before recording. The leaves design/validate; the lead
  applies/records.
- **Auto-start items are MISLABELED — resolve to the real target AND verify
  against the live PID / command line.** The Startup `Hermes_Gateway.vbs` is
  named like a gateway but its real target
  (`OneDrive\Desktop\repos\hermes-config\gateway-service\Hermes_Gateway.vbs`)
  runs `pythonw.exe -m hermes_cli.main gateway run` — i.e. the **native Hermes**
  gateway, NOT OpenClaw. The OpenClaw node listening on `:18789`
  (`node …/openclaw/dist/index.js gateway --port 18789`) was launched by a
  SEPARATE **Scheduled Task `\OpenClaw Gateway`**, not by any Startup file.
  CORRECTION (2026-07-11): a prior audit note claimed `Hermes_Gateway.vbs`
  launches OpenClaw — that is REFUTED; it launches Hermes. Lesson: never infer
  a bot's identity from the link NAME — `read_file` the `.vbs`/`.cmd`/`.lnk`
  target, then confirm the running PID's command line matches. If the running
  process matches NONE of the Startup targets, the real launcher is almost
  always a Scheduled Task (see §2a). See command-bank "BOTS & AUTOMATIONS".
- **Bot configs can carry plaintext tokens.** OpenClaw `openclaw.json` and
  `devices/paired.json` held live gateway + device operator tokens. FLAG
  credential exposure and recommend rotation; never reproduce token values in
  the report (treat like the confirmed-sensitive files in memory).

## 1b. Process / automation / AI-agent inventory (class: "what bots are running?")
A common ask: "list the live bot/automation/agent processes — PID, path,
command line, parent PID, memory, listening ports; confirm/deny specific
components; build the spawn tree." Verified method + Python parser +
the `Get-NetTCPConnection` JSON null-PID gotcha: **references/process-inventory.md**.
Three first-class pitfalls from the ZQM-NODE-1 run:
- **Port→PID mapping:** `Get-NetTCPConnection -State Listen | … | ConvertTo-Json`
  serializes `OwningProcessId` as **null on every row** (PowerShell drops the
  CIM uint). Trust `netstat -ano` (via `cmd.exe /c`) for the authoritative,
  parseable port→PID map instead.
- **Confirm a named component = scan PROCESSES AND registered services.** A
  component can be a stopped service with no live process. When the user asks
  "is cua-driver / the indexer / the automation-center running?", check
  `Win32_Process` AND `Win32_Service -match …` — the ZQM run found
  **cua-driver, ZQM-Node-01-Indexer, and ZQM-Skill-Automation-Center had
  NEITHER a process NOR a service**, so they were genuinely not running, not idle.
- **Exclude the agent's own audit subprocesses** (`bash -c hermes-snap…`,
  `powershell -Command Get-CimInstance…`, `head -80`, the agent's own
  `python.exe hermes.exe`) so they don't pollute the bot list — but KEEP the
  legitimate `python.exe hermes.exe` / `ollama.exe serve` / `openclaw … gateway`
  rows (stable command lines); only drop rows matching audit-fingerprint regexes.

## 2a1. Fast LAN endpoint review (when an earlier heavy probe timed out)
For the "enumerate open ports + confirm Ollama LAN exposure + per-port risk +
node grade" class of ask, use the EFFICIENT path, not a full scan:
- Reusable script: `scripts/lan_port_probe.py` — curated port list + 0.4s/port
  `socket` connect (no nmap), plus a one-GET Ollama `/api/tags` check that
  confirms LAN exposure AND model count at once. N4 (16 ports) ran in ~5s.
- Per-port RISK matrix + NODE GRADE rubric (A–E) + worked N4=D example:
  `references/lan-endpoint-review.md`. Run this from the AGENT HOST against the
  LAN target; it is a remote vantage (different from on-host `netstat`).
- KEY EFFICIENCY RULE: scan a SHORT curated list, never 1-65535, when the goal
  is "what's open + is the known service up". 0.4s connect timeout is plenty
  for LAN sub-ms RTT. Read-only: just TCP SYN + one HTTP GET.
- NOTE: a remote CLOSED on 3389/4001/8400/6379/18789 is EXPECTED (those bind
  loopback-by-design) — NOT a finding. See firewall-audit.md §2d.

## 2. Read-only command bank (all proven live)
See `references/command-bank.md` for the full, copy-paste set: OS/CPU/RAM/
disks/GPU/uptime, network adapters+ports, security posture, services,
software versions, and live Ollama probe. ALSO covers: **full volume +
partition + mountpoint enumeration**, **unmounted/letter-less volume
detection** (the "seen but no drive letter" case), **/24 host sweep via
ping.exe** (Test-Connection -AsJob is unreliable — returns 0 alive here),
and **SMB share enumeration + remote read/write test** (native PS
Copy-Item writes where other methods fail). ALSO covers the **scheduled-task
custom-audit recipe** (automation surface: filter non-Microsoft tasks, dump
State/Triggers/Actions/LastRunTime/LastTaskResult, decode the `CimInstance`
trigger gotcha + LastTaskResult codes, flag bespoke vs vendor tasks).

## 2a. Auto-start / persistence-surface inventory (bot "what starts at boot?")
Distinct from service/process inventory. Enumerate Win32_StartupCommand +
Startup folder + Scheduled Tasks, then RESOLVE each `.lnk`/`.vbs` target with
WScript.Shell (COM) and `read_file`, and `Test-Path` every resolved target.
**The dominant real-world failure: `.lnk`/`.vbs` point at STALE paths that no
longer exist** — a pass that stops at the link name reports live bots that are
actually dead. Use **references/auto-start-inventory.md** for the full recipe,
the `.lnk` resolver, the broken-target finding pattern, and the per-bot output
table. When a target is missing, find the real code via `search_files`
(pattern=scriptname) — live repos often live under `OneDrive\\Desktop\\repos\\`.
- **A live listener/process may be launched by a Scheduled Task that NO
  Startup file references.** If you resolve the Startup `.vbs`/`.lnk` targets
  and they still don't match the running PID's command line, enumerate
  Scheduled Tasks: `schtasks.exe /query /fo CSV | grep -i -E "openclaw|gateway|zqm"`.
  Read a task's Action with `schtasks /query /tn "\OpenClaw Gateway" /fo LIST`.
  This is how the OpenClaw `:18789` gateway was actually launched (action =
  `C:\Users\zqmco\.openclaw\gateway.cmd`). Startup folder + Scheduled Tasks are
  TWO independent persistence layers — check BOTH before concluding "nothing
  launches this". (Note: `schtasks` shows the task name/state; the `.cmd` it
  points at shows the real `node … openclaw … gateway` command line.)

**Repair dead links** (when detection finds them): `references/auto-start-repair.md` +
re-runnable `scripts/repair-broken-startup.ps1`. Backs up to `.bak`, repoints
`.vbs` target / `.lnk` Arguments+WorkDir, re-verifies with `Test-Path` on the
trimmed **Arguments** (the launcher exe existing is NOT proof the script runs).

## 2b. Storage: detect an unmounted / letter-less volume
A disk can be partitioned + fully formatted NTFS yet have NO drive letter and
NO folder junction — invisible to `Get-PSDrive`/`Get-Volume` DriveLetter, but
still reporting real Size/Free via `Win32_Volume`. When asked "find where disk
X is mounted":
- `Get-Partition | ForEach-Object { "$($_.DiskNumber):$($_.PartitionNumber) -> $($_.AccessPaths)" }`
  — empty AccessPaths = unmounted.
- `mountvol` — any GUID with "*** NO MOUNT POINTS ***" is unused.
- Report honestly: "3.64TB, 3.40TB free, NTFS, NOT mounted (no letter, no
  junction)". Use `mountvol <dir> \\?\Volume{<GUID>}\` (elevated) to mount it.
Do NOT assume every disk has a letter; `Get-PSDrive` alone will miss it.

## 2c. One-shot storage / shares / network audit (reusable script)
A complete, re-runnable node audit covering disks+volumes (incl. the
unmounted-but-formatted classifier from 2b), local SMB shares, remote NAS
share reachability (resolve + `Test-Path \\server\share`), adapters/IP/APIPA/
DNS/default-route, and a `/24` live-host ping sweep. Drop it on the target and
run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/host-storage-net-audit.ps1`
Config block at top (NAS name, share list, sweep range, known IPs) — edit per
node. Authoring note: keep the `.ps1` ASCII-only and `%`-free (see
`windows-powershell-from-bash` authoring gotchas) or it will not parse.

## 2d. Firewall / WinRM / sshd security audit (WinRM/sshd/port-scope tier)
A dedicated recipe for the "services by group, WinRM 5985/5986 state, sshd
PasswordAuthentication, firewall allow-rules for X ports, Defender RTP, run-key
hygiene, full listening-port census" class of ask. Verified live on ZQM-NODE-1
(2026-07-11). Full command set + worked pitfalls: `references/firewall-audit.md`.
THREE non-obvious gotchas captured there (each has burned a prior audit):
- **Firewall enumeration HANGS** with the per-rule
  `Get-NetFirewallRule | Get-NetFirewallPortFilter` loop + `schtasks /query /fo
  LIST` (120s timeout here). Use ONE `netsh advfirewall firewall show rule
  name=all dir=in` dump, parse once. Completes <30s.
- **Socket census is authoritative for listeners.** The `WSMan:` PS provider
  returned "Cannot find path" even while 5986 was bound. Use
  `Get-NetTCPConnection -State Listen`. Confirmed: 5986 bound, **5985 NOT bound**
  (WinRM HTTPS-only) — a prior audit's "5985 listening" claim was overstated.
- **Loopback probes are vantage-sensitive.** Testing `127.0.0.1:<port>` from a
  remote sandbox tests the SANDBOX's loopback → false "dormant" conclusion. The
  OpenClaw `:18789` gateway IS listening on Node-1's loopback; run the probe ON
  the target host. Also: `LocalIP=Any` on an allow-rule is NOT mis-scoping —
  source scope is enforced by **RemoteIP** (Ollama 11434 = RemoteIP
  192.168.1.0/24 = correctly LAN-restricted; a prior "mis-scoped" LOW was FALSE).
- **Firewall rules do NOT filter loopback / self-to-own-IP traffic.** A
  `curl http://<own-LAN-IP>:<port>` run ON the host returns 200 even when a Block
  rule is active — the self-connect path is loopback-exempt, so that 200 is NOT
  proof the block failed. To PROVE a LAN block, probe from a DIFFERENT host
  (cross-node `curl`, or a peer `Invoke-Command`/PSSession — needs a credential).
  Never report a same-host 200 as "still exposed"; it is an invalid test.
- **Block overrides Allow at the same port** (Windows block>allow precedence). A
  newly-added `action=block` silently wins over a stale `action=allow` rule on the
  same port/RemoteIP — so an old allow rule may be harmless, but verify externally
  rather than assuming the allow wins.
- **Don't probe raw (non-HTTP) ports with httpx.** httpx sends an HTTP GET and
  times out against Redis/TCP services, yielding a false "closed". Use a raw
  `socket` PING for Redis, and `netstat -ano` (via `cmd.exe /c`) for listener
  census — never `Get-NetTCPConnection` JSON (drops OwningProcessId as null).
- **Listener census MUST be `cmd.exe /c netstat -ano -p TCP | Select-String LISTENING`**
  (JSON-serialize `Get-NetTCPConnection` drops the owning PID). Map port→PID from
  that, then `Get-CimInstance Win32_Process -Filter ProcessId=X` for cmdline+parent.
- **TWO netstat PARSING GOTCHAS that each cost ~6 wasted turns this session — pin them:**
  - (a) The subprocess-wrapped form SILENTLY SWALLOWS netstat stdout. Do NOT do
    `subprocess.run(['powershell.exe','-NoProfile','-Command',"cmd /c netstat ... | Select-String LISTENING"])` — it returns 0 rows (MSYS/PS pipe eats cmd.exe stdout). RELIABLE pattern: run it as a BARE terminal command writing to a Windows temp file, then parse the file:
    `powershell.exe -NoProfile -Command "cmd.exe /c 'netstat -ano -p TCP' | Select-String LISTENING" > C:/Users/zqmco/AppData/Local/Temp/net.txt 2>&1`
    then `open(r'...\net.txt')` in a SEPARATE Python step. The inline -Command form
    with the Select-String pipe works; the subprocess / powershell -File forms both
    dropped rows this session. NEVER infer "no listeners" from an empty parse — check the
    raw file byte count first.
  - (b) Regex: use `[\d.]+:\d+`, NOT `\S+`. netstat's 2nd column `0.0.0.0:0` has
    internal spaces around it, so `TCP\s+(\S+):(\d+)\s+\S+\s+(\d+)` FAILS to match ANY
    row (the `\S+` for the 2nd column can't span the spaced `0.0.0.0:0`). Use:
    `TCP\s+([\d.]+):(\d+)\s+[\d.]+:\d+\s+LISTENING\s+(\d+)`. A wrong regex makes the
    parse return 0 matches → false CONTRADICTED claims in the claim-chain re-verify.
- **`netsh advfirewall firewall show rule name="<NAME>"` FAILS when NAME has spaces and
  is wrapped in nested quoting under MSYS.** A bash `for r in "A B" "C D"; do netsh ...
  name="$r"; done` loop returned `No rules match the specified criteria` for every rule
  (variable expansion + nested quotes broke it). Fix: run EACH rule dump as its OWN single
  `powershell.exe -NoProfile -Command "cmd.exe /c 'netsh ... name=\"<EXACT NAME>\" verbose'"`
  call, or — preferred — parse the single `show rule name=all dir=in verbose` dump (one shot,
  no per-rule loop). For a specific rule, pull its block with a python regex over that dump.
- **Don't grab the WRONG firewall rule for a port.** `findstr /i "2179"` also matches
  DESCRIPTION lines, and one port often has several same-stem rules with different LocalPort.
  Port 2179's inbound ALLOW is **"Hyper-V (REMOTE_DESKTOP_TCP_IN)"** (LocalPort: 2179,
  RemoteIP: Any), NOT the similarly named **"Hyper-V - WMI (Async-In)"** rule which is
  LocalPort: **Any**. Always read the `Rule Name:` line in the SAME dashed block as the
  `LocalPort:` you care about and confirm the LocalPort value matches before reporting that
  rule as the port's policy (11434/2179/53 each have multiple same-stem rules — match on
  LocalPort, not on the name stem).
- **sshd on Windows: a commented `#PasswordAuthentication yes` = password auth ON**
  (OpenSSH default). Check the bind with netstat (`0.0.0.0:22` = all interfaces,
  reachable from the LAN if a firewall allow-rule scopes the subnet). `sshd_config`
  values are unreadable non-elevated — flag the exact value as UNVERIFIED and request
  an elevated re-read rather than asserting it.
- **Exclude the agent's OWN audit subprocesses from bot/process listings** (the
  `python.exe` running your probe, `powershell -Command Get-CimInstance…`, `head`,
  `netsh`) so they don't pollute the inventory — but KEEP legitimate
  `ollama.exe serve` / `node … openclaw … gateway` / `python.exe -m uvicorn` rows.
`127.0.0.1:4001/8400/18789`); that is
CORRECT, not a finding. The exposure lives at the HOST layer (sshd/WinRM/SMB bound
`0.0.0.0`) — audit BOTH layers and report the loopback vs LAN distinction explicitly.
- **NEW (2026-07-11): `sshd -G` resolves the EFFECTIVE sshd config NON-elevated** — do NOT leave password-auth as UNVERIFIED. `sshd.exe` is at `C:\\Program Files\\OpenSSH\\sshd.exe`; `sshd -G` dumps effective settings (resolving commented defaults). This session returned `passwordauthentication: yes` + `authenticationmethods: any` → password logins accepted from LAN (closed Q10). Full recipe in references/firewall-audit.md (sshd-`-G` subsection).
- **Windows `sshd_config` Match-block EOF trap (2026-07-11, Council-1 finding).** The Windows OpenSSH `sshd_config` ends with a `Match Group administrators` block. Appending directive lines at EOF scopes them to ADMINS-ONLY (not global). To harden, EDIT THE COMMENTED LINES IN PLACE (e.g. `^#?\\s*PasswordAuthentication\\s+.*` → `PasswordAuthentication no`) BEFORE the Match block — never append at EOF. Also: members of Administrators use `C:\\ProgramData\\ssh\\administrators_authorized_keys`, NOT `~/.ssh/authorized_keys` — verify your pubkey is there AND a pubkey login works BEFORE disabling password-auth, or you lock yourself out.
- **`socket.recv()` on a fresh connect is a FALSE-NEGATIVE trap (recurred 3× this session).** A bare `s.connect(); s.recv(64)` times out even when the connect SUCCEEDED, because the server sends nothing unsolicited — you read 0 bytes / timeout and wrongly conclude "down/blocked". Authoritative pattern: send an actual request. For HTTP use `curl -s -m 6 -o /dev/null -w "%{http_code}" http://<ip>:<port>/<path>` (or `urllib` POST), NOT bare recv. Redis specifically: raw-TCP `PING\r\n` then read — and retry 2–3× because a single short-timeout connect can show a transient `NO` while raw-TCP retry shows `+PONG` (the earlier "Redis false positive" was the inverse: a transient timeout looked like a state change).
- **`sqlite3` binding pitfall (2026-07-11).** `cur.execute(sql, mystring)` iterates the STRING CHARACTER-BY-CHARACTER if you pass a bare `str` where a tuple/list is expected → "uses 1 binding, N supplied" (N = string length). ALWAYS wrap params in a list/tuple: `execute(sql, [val])` or `execute(sql, (val,))`. A bare string is a 249-element sequence, not one value.
- **NEW (2026-07-11): Windows FW block>allow precedence can RESOLVE an external-block question without a peer probe.** If a `Block` rule shares LocalPort+RemoteIP with a stale `Allow`, the block wins deterministically. This session closed Q8 this way (ZQM-Ollama-LAN-Block beats stale Ollama-LAN-only-11434). Report as "resolved by rule-precedence analysis" — a proof, not an assumption (a live peer curl stays gold-standard IF a credential exists). See references/firewall-audit.md.

## 3. Verification policy
- Read-only only. Never change system state during an audit.
- Every headline number must trace to a real command + output line.
- Cross-reference fleet memory (Node IPs, expected Ollama models) and call
  out CONFIRMED vs CONTRADICTED vs NEW.
- **Supplied "known context" / prior findings are a HYPOTHESIS, not ground
  truth.** When the user hands you earlier conclusions (e.g. "Startup
  Hermes_Gateway.vbs launches OpenClaw", "quarantine has ~10108 items"), verify
  each against live evidence and report CONFIRMED vs CONTRADICTED with proof.
  This session the OpenClaw claim was CONTRADICTED (separate Scheduled Task
  launches it; the .vbs launches Hermes) and the quarantine item count was
  off (8543 real files, not ~10108). Leading with a refutation of a wrong
  assumption is a feature, not a failure — surface it explicitly.
- Flag attack-surface items: LAN-exposed SSH(22)/WinRM(5985-86)/SMB(445)/
  Ollama(11434) when present; note RDP/UAC/firewall/Defender state.

## 4. Output format
Plain-text terminal block. Sections: Host identity, CPU/RAM, GPU, Storage,
Network, Security/Services, Software, Fleet cross-reference, Findings/flags.
Lead with the CORRECTED/important items, not a flat dump.

## 5. Non-elevated shell — privilege gates + fallbacks
Hermes's MSYS terminal runs PowerShell as the **logged-in user WITHOUT UAC
elevation** (verify with the admin check below). Several audit probes then
return **"Access is denied (0x80070005)"** even though the service is running.
This is a PRIVILEGE LIMITATION, not a finding — call it out honestly, do NOT
fabricate the config, and supply a compensating probe.

PROBES THAT FAIL NON-ELEVATED (confirmed this session):
- `winrm enumerate winrm/config/listener` and `winrm get winrm/config/service`
  → "Access is denied".
- `Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WSMAN\\...`
  → "Requested registry access is not allowed".
- `Get-MpPreference` / exclusion values → "Must be an administrator to view
  exclusions" (the count returns but the values are hidden).
- `WSMan:` PSDrive `Listener` path → "Cannot find path" (provider access gated).

COMPENSATING PROBES (work without elevation):
- **WinRM HTTPS listener still live?** `netsh http show sslcert` → look for
  `IP:port : 0.0.0.0:5986` with Application ID `{afebb9ad-9b97-4a91-9ab5-
  daf4d59122f6}` (canonical WinRM GUID) = listener exists with an SSL cert.
  Confirm reachability: `Test-NetConnection 127.0.0.1 -Port 5986` or a
  `[System.Net.Sockets.TcpClient]::Connect('127.0.0.1',5986)` probe.
- **Admin check (run first):** `[Security.Principal.WindowsPrincipal]::
  [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.
  Principal.WindowsBuiltInRole]::Administrator)` → $false means re-run
  elevated to close the gaps (exact WinRM listener config, Defender exclusion
  paths, `AllowUnencrypted` confirmation).
- Defender protection state itself (Get-MpComputerStatus) IS readable
  non-elevated — only the exclusion *values* are hidden.

ALWAYS state in the report which numbers are confirmed vs. gated-on-privilege,
and recommend an elevated re-run to disclose the hidden ones.
