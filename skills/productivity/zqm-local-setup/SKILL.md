---
name: zqm-local-setup
description: Use when setting up, repairing, or working inside the ZQM Windows homelab.
  Entry-point skill for Node-1/2/3/4 indexers, localhost services, LAN investigation,
  PowerShell remoting across workgroup nodes, ZQM-Gardens NAS (Synology + TerraMaster),
  GitHub workflow, and repo hygiene. Points to the exact local skills and evidence-based
  workflows instead of generic advice.
version: 1.4.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - windows
    - homelab
    - setup
    - indexer
    - github
    - lan
    - winrm
    - synology
    - terramaster
    related_skills:
    - github-pr-workflow
    - hermes-cron-ops
    - homelab-backup
    - localhost-management
    - networking-tools
    - ollama-fleet-lb
    - ollama-recovery
    - openclaw-mesh
    - python-windows-project-setup
    - windows-lan-investigator
    - zqm-github-management
    - zqm-repo-hygiene
---
# ZQM Local Setup

## Overview

Entry point for the actual ZQM Windows homelab. Loads the right specialist skill for common ZQM work on `192.168.1.0/24`.

**Topology (verified 2026-07-10 via live probe):**
- Node-1: `192.168.1.218` / `ZQM-Node-1.lan` — THIS host (the Hermes agent runs here as `zqmco`)
- Node-2: `192.168.1.21` / `ZQM-Node-2.lan` (remoting verified working)
- Node-3: `192.168.1.46` / `ZQM-Node-3.lan`  (NOT .22 — sequential IP guessing is wrong)
- Node-4: `192.168.1.215` / `ZQM-Node-4.lan` (NOT .23)
- ZQM-Gardens:
  - Synology fleet: Garden-01 `.173` (+`.53/.52/.169`), Garden-02 `.40` (+`.32/.37/.38/.39`), Garden-03 `.64`. DSM on 5000/5001. Garden-02 `.40` has a **cached** SMB credential from Node-1 (agent `cp` works without re-auth). Garden-01 `.173` `web` share is **NOT** cached but IS reachable from the agent with the garden-admin DPAPI cred (`net use \\192.168.1.173\web /user:azelenski <pw> /persistent:no`) — and crucially Node-3/4 already WRITE response files there, so they can READ+RUN a `zqm-bootstrap.ps1` dropped at `\\ZQM-Garden-01\web\`. **Use Garden-01 `web` as the dark-node script drop-and-run point** when the user's session can't reach Garden-02's UNC (the user's `alexz` session holds NEITHER cached SMB cred).
  - **TerraMaster GARDEN-04**: `.144`/`.147` (BOTH report hostname `ZQM-GARDEN-04` → cluster pair; TOS 5.1.145, kernel 5.15.59 Buildroot). **SSH(22) VERIFIED working with the same `azelenski` cred** (real shell, up 14 days, load ~0.75). Web UI on :5443 (valid TLS1.2) but the TOS5 REST login route is NOT at `/module/api.php` (that's TOS<=4.2.29) and brute-forcing 404s everywhere — **use SSH, don't chase the web API**. See `references/garden-management.md`. SECURITY: CVE-2022-24990 (unauth admin-password leak via `User-Agent: TNAS` on `/module/api.php`) was **TESTED CLEAN on 144/147 this session** (no leak on tested paths) — likely TOS5+; still worth a firmware check.
- Default advertised service: NetBIOS/SMB on 139/445

CRITICAL: Node IPs are NON-sequential. Always resolve `<name>.lan` via DNS before probing; never guess .21/.22/.23/.24.

## When to Use
- Starting new work in a ZQM repo
- Repairing a broken `.venv` or service script on Node-1/2/3/4
- Investigating a LAN host on `192.168.1.0/24`
- Managing GitHub repos under `ZQM-Computing`
- Deciding which local skill to load for a given task
- Setting up or debugging WinRM / PowerShell Remoting between nodes
- Staging scripts on a ZQM-Garden for grab-and-run on remote nodes
- **Managing a ZQM-Garden** (Synology DSM API OR TerraMaster SSH) — see the two Garden references.

## Skill Routing Table

| Task | Load This |
|---|---|
| Broken `.venv`, Python 3.12 hardcoded paths, service bootstrap scripts, `SKIP_ROOTS` tuning | `python-windows-project-setup` |
| Port scanning, ping sweep, traceroute, DNS, HTTP/TCP probes | `networking-tools` |
| Localhost port conflicts, `ERR_CONNECTION_REFUSED`, local server launch | `localhost-management` |
| Full LAN host investigation: identity, ports, SMB, firewall, owner mapping | `windows-lan-investigator` |
| WinRM / PowerShell remoting across nodes (setup, TrustedHosts, auth pitfalls) | `references/winrm-workgroup-remoting.md` |
| **Synology Garden management** (DSM API login, shares, health) | `references/synology-garden-management.md` |
| **TerraMaster GARDEN-04 management** (SSH via paramiko, TOS5 quirks) | `references/terramaster-garden-management.md` |
| Secure credential handoff (DPAPI, alexz vs zqmco account split) | `references/secure-cred-handoff.md` |
| GitHub auth, `gh` CLI, private repo file edits, credential safety | `zqm-github-management` |
| Repo naming, README template, cleanup, commit discipline | `zqm-repo-hygiene` |
| PR workflow, branch strategy, conventional commits | `github-pr-workflow` |

## Standard Order of Operations

### New repo setup or repair
1. Load `python-windows-project-setup`
2. Recreate `.venv` with `python -m venv .venv`
3. Install deps from `requirements.txt`
4. Harden service/bootstrap scripts for dynamic Python resolution
5. Narrow `DEFAULT_SCAN_ROOTS` and put system roots in `SKIP_ROOTS`
6. Harden `/api/health` or equivalent endpoints
7. Commit and push

### LAN investigation
1. Load `networking-tools` for basic reachability
2. Load `windows-lan-investigator` for the full evidence chain
3. Load `localhost-management` if the investigation is from the target host itself

### GitHub hygiene
1. Load `zqm-github-management` for auth/credentials
2. Load `zqm-repo-hygiene` for cleanup/README/branch standards
3. Load `github-pr-workflow` for the actual PR mechanics

### Garden management (Synology vs TerraMaster)
- **Synology** (Garden-01/02/03): DSM HTTPS API on :5001. Validate cred with `auth.cgi` (form-encoded body). See `references/synology-garden-management.md`.
- **TerraMaster GARDEN-04** (.144/.147): NO DSM. Use **SSH (paramiko)** — see `references/terramaster-garden-management.md`. Do not brute-force the TOS5 web API.

## Windows Remoting (WinRM / PowerShell Remoting)
All ZQM Windows nodes are WORKGROUP (not domain-joined). To let Node-1 manage Node-2/3/4 over `New-PSSession`, the full verified playbook (including every failure we hit and fixed) lives in `references/winrm-workgroup-remoting.md`. TL;DR:
1. **TARGET** (e.g. Node-2), Admin PS: `winrm quickconfig -q` (NOT `Enable-PSRemoting` — see note below), set adapter `Private`, create a LOCAL admin (Microsoft/email accounts are rejected by NTLM), add to `Remote Management Users` + `Administrators`.
2. **CLIENT (Node-1)**, Admin PS: `winrm quickconfig -q` FIRST (its own WinRM must run or TrustedHosts writes fail), then `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force`.
3. **TEST**: `New-PSSession -ComputerName <ip> -Port 5985 -Credential (Get-Credential)` using `.\zqmlocal` (local account; explicit cred forces NTLM).
4. Store reusable bootstrap/fleet scripts on Garden-02's `web` SMB share (`\\192.168.1.40\web`) — it's the only Garden with a cached SMB credential from Node-1.

## Environment Facts (verified 2026-07-10, live probe on Node-1)
- **OS**: Windows 10 (hostname zqm-node-1; agent runs as `zqmco`, user desktop is `zqm-node-1\alexz`)
- **Python**: `3.11.15` active (ComfyUI venv `Documents\comfy\ComfyUI\.venv`), AND `3.12.10` standalone at `AppData\Local\Programs\Python\Python312` (pip 25.0.1). `python3` = MS-Store alias (use `python`); `python -m pip install` works user-level.
- **uv**: `0.11.26 (x86_64-pc-windows-msvc)`.
- **Node/npm**: `v24.18.0` / `11.16.0` at `C:\Program Files\nodejs`.
- **git**: `2.55.0.windows.2`; **gh**: at `C:\Program Files\GitHub CLI\gh.exe`.
- **go**: `go1.26.4 windows/amd64` at `C:\Program Files\Go`. **docker**: `29.6.1`. **rust/cargo**: NOT installed.
- **winget**: `v1.29.280`. **scoop**: NOT installed (PATH stub only — see gotcha below). **choco**: not installed.
- **Ollama**: `0.31.2` (LAN-exposed, no auth — `zqm-fleet-management` covers this).
- **PowerShell**: Windows PowerShell **5.1.26100.8655** (NOT pwsh 7). Custom profile EXISTS at `OneDrive\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` (~4 KB) — loads **starship** + a Scoop-style 40+ tool alias set (git, gh, nvim, rg, fd, …). ALWAYS invoke with `-NoProfile -ExecutionPolicy Bypass -File` when handing scripts to the user (see pitfall table / dark-node notes in `zqm-fleet-management`).
- **Notable apps** (registry): Docker Desktop, FFmpeg, Git, GitHub CLI, Go, Google Chrome, VS Code (User), Node.js, Ollama 0.31.2, Python 3.12.10, RipGrep MSVC. No NVIDIA/CUDA, Rust, JetBrains, or Obsidian entries.
- `ssh.exe` present but cannot do non-interactive password auth (needs TTY/sshpass; plink/sshpass ABSENT). Use paramiko for scripted SSH.
- `Get-NetFirewallRule` is unreliable; prefer `netsh advfirewall`
- `tasklist /FO TSV` is invalid; use `/FO CSV` or `/FO LIST`
- OneDrive can lock `.git/index.lock`; expect occasional resolution

## Workstation toolchain inventory (re-runnable)
- **`scripts/workstation_toolchain_inventory.sh`** — one-shot parallel probe that emits REAL version strings for every package manager / Python+pip+uv / Node+npm / git / go / rust / docker / PowerShell+profile / registry apps / PATH. Run `bash scripts/workstation_toolchain_inventory.sh`. It bakes in the **scoop-PATH-stub gotcha** (below) so a future run won't falsely report scoop as present.

## Common ZQM Failure Modes

| Symptom | Root Cause | Fix |
|---|---|---|
| Service bootstrap fails on launch | Hardcoded `Python312` path | Dynamic `python.exe` lookup; see `python-windows-project-setup` |
| Index scan skips nearly everything | `DEFAULT_SCAN_ROOTS` includes `C:\Windows` / `C:\PerfLogs` | Narrow roots; move system paths to `SKIP_ROOTS` |
| `/api/health` returns 500 without index | `NoneType` from missing Whoosh index | Harden endpoint to return 200 for absent optional state |
| `git push` exits 128 | Credential helper broken/absent | `gh auth git-credential` + `credential.helper manager-core` |
| Port 5000 refused / no process | Indexer not started or `.venv` broken | Verify `.venv\Scripts\python.exe` exists; rebuild if needed |
| `.git/index.lock` after OneDrive sync | OneDrive file locking | Remove lock, retry git command |
| WinRM "must be added to TrustedHosts" | Workgroup target not trusted by client | `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<ip>" -Force` on Node-1 |
| WinRM "Access is denied" with email cred | Microsoft account rejected by NTLM | Use a LOCAL account (`.\zqmlocal`); create one on target |
| `Set-Item WSMan:...` "client cannot connect" | Node-1's own WinRM not running | `winrm quickconfig -q` on Node-1 FIRST |
| **"Can I reach Node-X from here?" answered by guessing** | Agent concludes remote is impossible without checking | Run `scripts/zqm-node-reachability.ps1 -Node <ip>` FIRST — checks PSSessions, SMB mappings, C$ reachability, ports 5985/5986/22; prints a VERDICT (session exists / port-open-no-secret / node dark). This session: Node-2 had 5985 OPEN but no session + no stored zqmlocal + C$ unreachable → truly untouchable, but proven, not assumed. |
| **TrustedHosts READ works as non-admin, WRITE needs elevation** | `Get-Item WSMan:\localhost\Client\TrustedHosts` (read) succeeds as `zqmco`; only `Set-Item` (write) returns "Access is denied" | Agent CAN verify the user's "I widened the hosts" claim via `Get-Item` (read) — no admin needed. Only the user's ELEVATED shell can `Set-Item`. Don't re-attempt Set-Item; just read-verify and report the actual value. |
| DPAPI "Key not valid for use in specified state" | User-scope DPAPI (Export-Clixml) stored by `alexz` but agent is `zqmco` | Use **LocalMachine-scope** DPAPI (JSON + `ProtectedData.Protect(...,LocalMachine)`); user-scope always fails here — see `references/secure-cred-handoff.md` |
| Synology DSM REJECTED error=101 on login sweep | EITHER stored account/password is wrong, OR (common bug) params sent as JSON body instead of form-encoded | ALWAYS pass a hashtable to Invoke-RestMethod -Body so PS form-encodes it; JSON body makes Synology return 101 even with a correct password. Verify with DSM API (references/garden-management.md). error 105/106 = 2FA on. |
| **DSM login 101 on EVERY box despite right cred** | Request sent as JSON body; Synology `auth.cgi` needs `application/x-www-form-urlencoded`. JSON → empty account/pass → 101. | Pass the hashtable directly to `-Body` (PS form-encodes it). If user says "I just logged in with that cred", SUSPECT THE REQUEST SHAPE before the credential — re-test form-encoded. |
| `New-SmbMapping`/"net use IPC$" "network name cannot be found" vs open 445 | Synology SMB client quirk, not auth — even valid creds fail this path | Use the DSM HTTPS auth API to validate creds instead; do NOT conclude auth failed from SMB errors alone |
| PowerShell 5.1 `Invoke-RestMethod` "-SkipCertificateCheck" not found | PS 5.1 lacks that param | Set `[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }` for self-signed Synology certs |
| `.ps1 cannot be loaded / scripts disabled` | PowerShell ExecutionPolicy blocks file scripts | Agent uses `powershell -ExecutionPolicy Bypass -File ...`; user uses inline one-liners or `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| `Set-Content` "WROTE" but file missing | Parent dir absent + unconditional `Write-Host` | Create dir first: `New-Item -ItemType Directory -Force -Path (Split-Path $Path)`; gate success msg behind `Test-Path` |
| **TerraMaster TOS5 web login 404s on every API path** | TOS5 backend auth route is not at `/module/api.php` (that's TOS4) or any synology/standard path; brute-forcing wastes time | Use **SSH (port 22)** instead — `azelenski` cred logs in via paramiko (`python -m pip install paramiko`). Full method: `references/terramaster-garden-management.md` |
| **`powershell -File C:\\Users\\...\\x.ps1` → "file does not exist"** | Bash/cmd strips backslashes from the `-File` path | Copy script to `C:\\temp\\`, then `cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\temp\\probe.ps1"`. Avoid inline `-Command` for scripts with `[...]`/`$matches` (ParserError). |
| **INLINE one-liner PS pasted into the user's console gets MUTILATED in transit** (hit 2026-07-10 on Node-3/4 bootstrap) | Chat/terminal transport silently dropped `$_` → `$`, dropped bare `*`, and mangled backtick-escaped quotes → `$.IPAddress` parser error, `Address=+Transport=HTTPS` (no `*`), broken winrm string. Both nodes failed identically. | Author inline PS to be TRANSPORT-HARDENED: (1) NEVER use `$_` — use piped cmdlets instead (`Get-NetConnectionProfile \| Set-NetConnectionProfile -NetworkCategory Private` instead of `Where-Object { $_.IPAddress -like ... }`); (2) NEVER use bare `*`, and AVOID `winrm create` (shell-escaping nightmare) — use `New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{Address="*";Transport="HTTPS"} -ValueSet @{Hostname=...;CertificateThumbprint=...}` (native PS, no `*`, no backticks); (3) AVOID backtick line-continuations/escapes entirely; write it as one compact line. See `references/inline-ps-transport-hardening.md`. Prefer pasting a FILE via the local path (`C:\\Users\\zqmco\\zqm-bootstrap-inline.ps1`) over a giant inline blob whenever possible. |
| **User's inline pasted PS throws `$.IPAddress is not recognized`** | Transport dropped `$_` (see above) — same root cause as the inline-PS-mutilation pitfall | Same fix: rewrite with no `$_`, no bare `*`, no backticks. The `references/inline-ps-transport-hardening.md` template is the drop-in replacement. |
| **User's own PowerShell can't open `\\192.168.1.40\web\zqm-*.ps1` ("file does not exist" / path not found)** | The cached SMB credential to Garden-02 exists ONLY in the `zqmco` agent session, NOT the user's interactive `alexz` session — so the UNC share is unresolvable for them even though the agent's bash `cp` can write to it | The scripts ALSO exist locally on Node-1 at `C:\Users\zqmco\zqm-*.ps1`. Have the user run them from that LOCAL path (native backslashes work fine in their PS). Only the agent's `cp`/`bash` can use the `\\192.168.1.40\web` UNC. If the user must use the share, copy it local first: `copy \\192.168.1.40\web\zqm-store-cred.ps1 C:\temp\` then run `C:\temp\zqm-store-cred.ps1`. |
| **`winget install` blocked / denied** | (placeholder) | Check winget version (`winget --version`) and admin scope; see above for the verified `v1.29.280`. |
| **"scoop is installed" but it isn't — PATH has `scoop\shims`** | A PowerShell profile can APPEND `C:\Users\<user>\scoop\shims` to PATH even when scoop was never installed. `Test-Path C:\Users\<user>\scoop\shims` and `...\scoop\apps` both return False, and `scoop --version` is "command not found" in BOTH bash and PowerShell. So a PATH entry ≠ an installed tool. | Do NOT report scoop (or any tool) as present from PATH alone. Verify: (1) command resolves in both shells, (2) the install dirs exist, (3) `scoop --version` returns a real version. The `scripts/workstation_toolchain_inventory.sh` probe does exactly this and prints "scoop NOT installed (PATH entry is a stub)". Hit live 2026-07-10: profile referenced scoop + 40 tools, but only the shim dir was on PATH with no backing install. |
| **Python `ctypes` DPAPI decrypt → WinError 87** | `CryptUnprotectData` ctypes signature/struct layout wrong (DATA_BLOB first arg) | Do NOT hand-roll DPAPI in Python. Decrypt in PowerShell via `[System.Security.Cryptography.ProtectedData]::Unprotect($enc,$null,"LocalMachine")`, then pass the password as an argv to the python script. Reliable every time. |
| **`paramiko` ModuleNotFoundError from `execute_code`** | The execute_code sandbox python is a different interpreter than the ComfyUI venv that has paramiko | Run python scripts that need paramiko with the explicit venv interpreter: `C:\\Users\\zqmco\\Documents\\comfy\\ComfyUI\\.venv\\Scripts\\python.exe C:\\temp\\x.py` (write the .py with write_file first; heredoc paths get MSYS-mangled). |
| **`Enable-PSRemoting -Force` only enables PowerShell 7+ remoting, NOT Windows PowerShell 5.1** | PS7's `Enable-PSRemoting` creates a PS7-only endpoint; the fleet loop runs on WinPS 5.1 from Node-1 and cannot connect (5985 shows "WinRM cannot complete the operation" or silent failure) | Use `winrm quickconfig -q` inside the bootstrap script — it enables the 5.1 listener (and HTTP 5985 for all PS versions). The `zqm-bootstrap.ps1` v2 uses this. |
| **HTTPS 5986 listener: `New-WSManInstance ... -SelectorSet @{Address=\"\";Transport=\"HTTPS\"}` → "resource URI missing/incorrect format"** | Empty `Address` string is invalid; must be `Address=\"*\"`. The inline-PS transport-corruption (bare `*` dropped) turned `Address=*` into `Address=\"\"` on Node-3/4 | Use `winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=...;CertificateThumbprint=...}"` (proven working on Node-2 this session) OR `New-WSManInstance -SelectorSet @{Address=\"*\";Transport=\"HTTPS\"}` with a literal `*`. Never an empty string. |
| **`winrm delete ...Listener?Address=*+Transport=HTTPS` throws WSManFault and ABORTS the script** when no HTTPS listener exists yet (first run) under `$ErrorActionPreference=\"Stop\"` | `winrm delete` errors on a missing listener; the unhandled error stops the whole bootstrap before `winrm create` runs → 5986 never created (hit on Node-4) | Wrap the delete in `try { winrm delete ... 2>$null } catch { }` so a missing listener is non-fatal; then `winrm create` always proceeds. `zqm-bootstrap.ps1` v2 has this fix. |
| **Node reports "Bootstrap complete" but WinRM ports stay CLOSED** (Node-3 case this session) | User re-ran the STALE broken inline command from a `response.txt` file instead of the corrected staged `zqm-bootstrap.ps1`; the old command aborted at `Set-NetConnectionProfile` (non-elevated) before `Enable-PSRemoting` ran → nothing enabled | AGENT: before trusting "done", (1) re-read the response file content AND (2) probe the node's ports (5985/5986/22) from Node-1 — a closed 5985 means not bootstrapped regardless of self-report. Tell the user to run the STAGED FILE (`\\\\ZQM-Garden-01\\web\\zqm-bootstrap.ps1`), not re-paste old inline. |
| **WinRM session to a node returns "Access is denied"** (Node-4 case) | WinRM IS up (port open, auth reached) but the stored `zqmlocal` password does NOT match what was typed at that node's bootstrap → credential mismatch, NOT a network/unreachable problem | Distinguish: "WinRM cannot complete the operation" = service down/unreachable; "Access is denied" = service up + wrong password. Fix: re-run the bootstrap on that node and type the SHARED `zqmlocal` password so the fleet loop's single cred matches all nodes. |
| **Multi-node fleet loop needs ALL nodes to share ONE `zqmlocal` password** | If each node got a different password at bootstrap, the single DPAPI cred file only works on the one node that matches | Enforce: the user must type the SAME password on Node-2/3/4. If "Access is denied" appears on only some nodes, re-run bootstrap on those with the shared password. |
| **`Add-Type -AssemblyName System.Security` "Unable to find type" in a `cmd.exe /c powershell -File` runspace** | Flaky assembly load in the spawned runspace | Use `[void][System.Reflection.Assembly]::LoadWithPartialName("System.Security")` OR, simpler, do the DPAPI decrypt in its own small PS step and pass the result to python. The mesh-verify run proved `Add-Type` works on direct invocation but not always via `cmd /c`. |
| **execute_code python can't reach `C:\temp\failover_syno.py`** | MSYS path translation mangles `/c/temp/...` for a Windows-native python | Write the .py with the write_file tool (absolute `C:\...` path) and invoke the venv python by its absolute Windows path. |
| **Reusable pattern: PS decrypts DPAPI cred, then drives paramiko SSH** | ctypes DPAPI fails (WinError 87); execute_code lacks paramiko | Use `scripts/zqm-dpapi-ssh.ps1` — decrypts the LocalMachine-DPAPI JSON in PowerShell, passes the secret as argv to the ComfyUI venv python (`C:\Users\zqmco\Documents\comfy\ComfyUI\.venv\Scripts\python.exe`) which imports paramiko. Password never printed, never on disk. |
| **"is the mesh redundant / do we have login failover?"** | Ad-hoc port scans each time | Run `scripts/zqm-failover-probe.ps1` — pure TCP reachability: node login ports (5985/5986/22/3389/135/445) + Synology DSM(5001) vs SSH(22) + GARDEN-04 SSH/5443. No creds, no writes. |
| **User swears `email/pw` "works" but SSH/WinRM REJECT it** | Microsoft-account (MSA) login: console/Hello/PIN works; remote SSH/WinRM with the MSA UPN often rejected. ALSO the password may be a GARDEN password (e.g. `344SW00DL4nd!` = Garden admin `azelenski`), NOT the Windows login pw. | Do NOT accept or reject by assertion. Run `references/msa-remote-auth.md` diagnostic chain: (1) distinguish TrustedHosts client block vs real `0x8009030e`; (2) `Get-LocalUser` → `PrincipalSource=MicrosoftAccount`, local SAM name = `Name` column; (3) test WinRM as the SAM name with candidate pw. The user's "it works" = console/Hello/PIN, which does NOT prove remote-auth password. |
| **Garden mounts fail on Node-3/4 with error 1312 but work on Node-1** | Synology DSM per-client IP allowlist rejects the node's SOURCE IP for SMB logon (cred is valid — works from Node-1). | GARDEN-side gate, not a node bug. Proven: TCP 445 OPEN + same cred OK from Node-1 + `admin` user → "wrong password". Fix on DSM: allow the node IP. See `references/garden-smb-allowlist.md`. Garden-02 (.40)/Garden-04 (.147) accepted; Garden-01 (.173)/Garden-03 (.64) rejected Node-3 this session. |
| **"No credential / node unreachable" stated without checking** | Agent concludes auth/connectivity impossible without enumerating stored vaults, Credential Manager, other node creds, and candidate IPs | User enforces FULL ENUMERATION before any "can't". Check `C:\zqm\cred\*.json` (decrypt), `cmdkey /list`, all local accounts, and a fabric ping sweep (`scripts/zqm-fabric-sweep.py`) + SSH/WinRM auth sweep (`scripts/zqm-cred-sweep.py`). Only declare "unreachable" after every candidate is exhausted. Do not loop on one failing auth call. |


## Secure Credential Handoff (DPAPI SecureString)
When the agent needs a real credential (Synology admin, Node local account, TerraMaster SSH) to do LAN management, NEVER accept it pasted in chat. Use the DPAPI SecureString handoff so the secret never enters the transcript. Full method, one-liners, and pitfalls: `references/secure-cred-handoff.md`. Reusable scripts (all in `scripts/`):
- `zqm-store-cred.ps1`  — USER runs; **parameterized** (`-Name <tag>`, default `node-local`) → `C:\zqm\cred\zqm-cred-<tag>.json` as **LocalMachine-scope** DPAPI JSON. Self-verifies by re-decrypting and only prints OK if the roundtrip succeeds (fixes the old silent-`Set-Content` false-success trap). Run: `powershell -ExecutionPolicy Bypass -File \\192.168.1.40\web\zqm-store-cred.ps1 -Name node-local`. (NOT user-scope `Export-Clixml` — that fails across the alexz/zqmco split.)
- `zqm-use-cred.ps1`    — AGENT runs; loads JSON via `ProtectedData.Unprotect(...,LocalMachine)`, uses `PSCredential`/`SecureString` only (password never printed).
- `zqm-cred-cleanup.ps1`— removes stored JSON(s).
- `zqm-bootstrap.ps1`   — run on a remote Node to enable remoting + create local admin.
- `zqm-fleet.ps1`       — run on Node-1 to loop-manage Node-2/3/4 via one `.\\zqmlocal` cred.
- `zqm-dpapi-ssh.ps1`    — AGENT runs; decrypts a LocalMachine-DPAPI JSON and drives paramiko SSH (via ComfyUI venv python) WITHOUT the password ever printing or touching disk. Reusable for any scripted SSH using a stored cred.
- `zqm-failover-probe.ps1` — assess login-failover coverage across the fleet (node login ports + Synology DSM-vs-SSH + GARDEN-04). Pure TCP, no creds. Re-run after any remoting change.
- `zqm-node-reachability.ps1` — agent-side pre-check: can Node-1 actually reach a target node right now (PSSession/SMB/C$/ports)? Returns a VERDICT; run BEFORE claiming a node is unreachable.

STANDING ACCOUNT SPLIT (hit 2026-07-10): the USER's interactive shell runs as `zqm-node-1\alexz`, but the AGENT's terminal session runs as `zqmco`. User-scope DPAPI (`Get-Credential | Export-Clixml`) ALWAYS fails across the handoff ("Key not valid for use in specified state") because the ciphertext is bound to alexz. FIX: use **LocalMachine-scope** DPAPI (the `zqm-store-cred.ps1` default) so any local account on the PC can decrypt. Do NOT tell the user to "re-store under zqmco" — their shell is alexz and that won't work. Full method + verified one-liner in `references/secure-cred-handoff.md`.

## Staging scripts on a Garden for grab-and-run
SMB write to `\\192.168.1.40\web` (Garden-02) works from Node-1 WITHOUT creds (cached session). Stage `zqm-bootstrap.ps1` / `zqm-fleet.ps1` there; remote nodes pull and run them. Other Gardens (173/64/144/147) DENY anonymous SMB write — they need Synology creds.

## NODE LOGIN FAILOVER — NOW IMPLEMENTED (verified 2026-07-10)
The Windows nodes previously had **NO login redundancy**. `zqm-bootstrap.ps1` v2 (staged at `\\192.168.1.40\web\zqm-bootstrap.ps1`) now closes that gap:
- Enables **WinRM HTTP 5985** (baseline) AND **WinRM-HTTPS 5986** (self-signed cert + listener + LAN-scoped firewall rule) as failover A.
- Installs/enables **OpenSSH Server (22)** as failover B, reusing the same `zqmlocal` account. (Skips gracefully on editions lacking the OpenSSH.Server capability.)
- **Auto-stores the `zqmlocal` password to LocalMachine-DPAPI JSON** (`C:\zqm\cred\zqm-cred-node-local.json`) so the agent can re-establish sessions WITHOUT the password in chat. If the DPAPI file already exists, bootstrap consumes it non-interactively.
- `zqm-fleet.ps1` (staged at `\\192.168.1.40\web\zqm-fleet.ps1`) loops Node-2/3/4, trying 5985 then **falling back to 5986**, and reports Host/Ver/Uptime/SSHD/WinRM-HTTPS per node. Both scripts syntax-verified and hash-matched to the Garden share.
**User actions still required to finish the mesh — EXACT commands (agent CANNOT run these: needs admin on Node-1 + the zqmlocal secret only the user holds):**
- **[A] Node-1, ELEVATED Admin PS** — widen TrustedHosts:
  `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.21,192.168.1.46,192.168.1.215" -Force`
- **[B] Node-1 (where the AGENT lives), ELEVATED Admin PS** — store the `zqmlocal` password to DPAPI LOCALLY. The fleet loop runs from Node-1 and reads `C:\zqm\cred\` ON Node-1, so the cred ONLY needs to live here — no cross-machine copy, no need to touch Node-2. (Earlier guidance said "run it on Node-2 and copy to Node-1" — that was overcomplicated; Node-2 needs nothing from you right now since its WinRM is already up and `zqmlocal` already exists with the matching password. We just need the password in Node-1's DPAPI store so the fleet loop can authenticate to Node-2.) Run the LOCAL copy (the user's `alexz` session cannot open the `\\192.168.1.40\web` UNC — see pitfall table):
  `powershell -ExecutionPolicy Bypass -File C:\Users\zqmco\zqm-store-cred.ps1 -Name node-local` → at prompt `User name: zqmlocal`, `Password: ***` → expect `OK stored + roundtrip-verified ... user=zqmlocal`. (If you must use the share, copy it local first: `copy \\192.168.1.40\web\zqm-store-cred.ps1 C:\temp\` then run `C:\temp\zqm-store-cred.ps1`.)
- **[C] Node-3 (.46) and Node-4 (.215), LOCAL Admin PS** — enable failover (5985→5986→22) + auto-store cred. **Run the FILE, never an inline paste** (inline PS dropped the bare `*` from the HTTPS listener selector → `Address=""` → "resource URI missing/incorrect format", breaking 5986 on Node-4 this session). Delivery, in order of reliability:
  1. **PREFERRED:** agent pushes the corrected `zqm-bootstrap.ps1` to `\\ZQM-Garden-01\web\zqm-bootstrap.ps1` (Garden-01 `web` reachable from the agent via the garden-admin DPAPI cred; Node-3/4 already write response files there, so they can read+run it). On each node:
     `powershell -ExecutionPolicy Bypass -File \\ZQM-Garden-01\web\zqm-bootstrap.ps1`
  2. If that UNC is blocked on the node: `copy \\ZQM-Garden-01\web\zqm-bootstrap.ps1 C:\temp\` then run `C:\temp\zqm-bootstrap.ps1`.
  3. Garden-02 `\\192.168.1.40\web\` only works if the node holds a cached SMB cred (the agent does; the user's `alexz` session does NOT).
  Expect: created `zqmlocal`, stored cred, WinRM-HTTPS 5986, OpenSSH 22. Use `winrm quickconfig -q` (not `Enable-PSRemoting`) inside the script so the WinPS 5.1 listener comes up — see `references/node-failover-setup.md`.
- Then tell the agent **"done"** and it runs `zqm-fleet.ps1` from Node-1 — connects each node via 5985, falls back to 5986, reports Host/Ver/Uptime/SSHD/WinRM-HTTPS.
**Discipline:** the agent runs `zqm-fleet.ps1` as a BASELINE first — it exits `NO NODE CRED FILE` until [B]+[C] are done and TrustedHosts is still single-entry until [A]. That baseline IS the proof of real state; the agent does NOT claim the mesh is complete. The two gates it cannot cross are admin-on-Node-1 (TrustedHosts write → "Access is denied" as `zqmco`) and the `zqmlocal` secret (only the user knows it).
**Gardens already HAVE failover:** Synology = DSM API (:5001) + **SSH (:22)** with the same `azelenski` cred (verified: `hostname` returned `ZQM-GARDEN-02/03/Garden-01`); TerraMaster GARDEN-04 = SSH (:22). So a DSM/API outage on a Synology does NOT lose management — SSH backs it.

## AGENT BOUNDARY DISCIPLINE — what "proceed / perform / do it" does NOT grant
This homelab has a hard trust boundary the agent must respect even when the user says "go ahead":
- The agent's terminal runs as `zqmco` on Node-1. Commands that require **admin on Node-1** (e.g. editing `WSMan:\localhost\Client\TrustedHosts`) return **"Access is denied"** from this session. The user must run them in an **elevated** PowerShell. Do NOT claim they succeeded.
- The agent does **NOT** possess interactive-only secrets. `Get-Credential` is a prompt only the human can answer, and the `zqmlocal` password is known only to the user. You can hand the user a one-liner, but you cannot supply or retrieve that secret. Do NOT fabricate a "mesh complete / fleet connected" result.
- **Prove the real state, then hand off.** When a step needs elevated/admin or a secret you lack, (1) verify what you CAN reach (port scans, the missing-cred-file baseline, current TrustedHosts value), (2) state plainly which parts are blocked and why, (3) give the exact commands for the user's local/elevated console. Example from this session: the fleet loop was run as a baseline first — it exited "NO NODE CRED FILE" and TrustedHosts still showed only `192.168.1.21`, which is the true status; only after the user performs Steps 1–3 does the agent run the loop for real.
- This is the opposite of "ask permission every time" — it's about not pretending. The user wants autonomous progress; deliver it wherever the account actually allows, and clearly fence the rest.

## Notes
- **References & scripts:** `scripts/workstation_toolchain_inventory.sh` (re-runnable Node-1 toolchain inventory — emits real version strings + proves scoop-PATH-stub vs real install), `references/zqm-topology.md` (verified IP/DNS map), `references/winrm-workgroup-remoting.md` (full remoting playbook + pitfalls), `references/secure-cred-handoff.md` (LocalMachine-scope DPAPI handoff — REQUIRED because user is `alexz` but agent is `zqmco`), `references/garden-management.md` (Synology DSM form-encoded API + TerraMaster TOS SSH), `references/synology-ssh-failover.md` (DSM→SSH failover with same `azelenski` cred — VERIFIED), `references/node-failover-setup.md` (how `zqm-bootstrap.ps1` v2 + `zqm-fleet.ps1` deliver 5985→5986→22 login failover), **`references/inline-ps-transport-hardening.md` (how to author inline PS that survives paste into the user's console — no `$_`, no bare `*`, no backticks; fixes the Node-3/4 `$.IPAddress` corruption)**, **`references/garden-node-resilient-links.md` (self-healing Garden SMB link layer + the WORKGROUP WinRM-from-scheduled-task Negotiate failure — CRITICAL gate for headless node monitoring; read before building any Garden/Node resilience automation)**, `scripts/probe_lan.py` (timeout-based LAN port probe — do NOT use bash `/dev/tcp`, it HANGS on dead hosts), `scripts/zqm-ssh-tm.py` (paramiko non-interactive SSH to TerraMaster — requires the ComfyUI venv python), `scripts/zqm-dpapi-ssh.ps1` (decrypt DPAPI JSON → drive paramiko SSH via ComfyUI venv python; secret never printed), `scripts/zqm-failover-probe.ps1` (login-failover coverage probe — pure TCP), `scripts/zqm-cred-sweep.py` (TCP + paramiko SSH auth sweep across candidate user:pass pairs — use before concluding "no credential works"), `scripts/zqm-fabric-sweep.py` (ping sweep of 192.168.1.0/24 → live hosts, to discover unidentified nodes like a not-yet-built Node-5), `scripts/zqm-*.ps1` (cred handoff + bootstrap + fleet — staged at `\\192.168.1.40\web\`). New this session: `references/msa-remote-auth.md` (Microsoft-account remote-auth failure diagnostic — the trap where a working console login looks "wrong" over SSH/WinRM) and `references/garden-smb-allowlist.md` (Synology per-IP SMB logon rejection / error 1312).
- **Credential handling:** On this solo LAN the user authorizes inline credential use for verification, but insists on rotation afterward. Prefer the DPAPI handoff (`references/secure-cred-handoff.md`) so the secret never lands in chat; otherwise use inline only, then advise rotation. Never store creds in memory or chat echoes.
- This skill exists to load the right specialist skill faster. It does not replace them.
- If a local skill is missing, check `C:\Users\zqmco\AppData\Local\hermes\skills\`.

## Housekeeping / Archival Policy
These installed skills are not relevant to this Windows/ZQM environment. Prefer not loading them:
- `apple/*` — macOS only
- `social-media/xurl` — X/Twitter CLI workflow; not used here
- `research/research-paper-writing` — academic MLOps workflow; heavy and detached
- `media/*` — GIF, YouTube, audio tools; not part of ZQM work
- `smart-home/*` — no smart-home stack in this environment
- `yuanbao` — unrelated group chat integration
- `creative/*` — design/animation tools; not part of the current workflow
- `mlops/*` — GPU-first model serving/eval; not present on this host
Delete or archive only after confirming they are not referenced by other skills. If unsure, leave them installed but do not load them.
