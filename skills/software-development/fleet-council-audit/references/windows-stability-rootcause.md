# Windows fleet stability — root-cause + hardening (NEW 2026-07-11)

Companion to `fleet-council-audit` SKILL.md. Triggered by the user's
"diagnostics and learn more" / "improve systems stability" verbs. This session
decoded TWO real instabilities end-to-end and applied safe (local, reversible)
hardening. Techniques below are portable to any Windows 11 + MSYS/bash host.

## VERB HOOK (where this fits in the skill's verb map)
- "diagnostics and learn more" / "diagnostics and forensic science"
  → read-only ROOT-CAUSE pass (below). No fix until a numbered GO.
- "improve systems stability" → apply the safe hardening (service recovery +
  autostart) AFTER root-causing. Gated on elevation where noted.

## 1. Decode a "unexpected shutdown" via the EventID chain (NOT a crash)
A `EventLog 6008 "previous system shutdown ... was unexpected"` is NOT
necessarily a fault/BSOD. Decode the chain:
- **Event 1074** (User32/winlogon): `winlogon.exe` initiated **power off**
  on behalf of `NT AUTHORITY\SYSTEM`, **Reason Code 0x500ff**,
  "Shutdown Type: power off". → SYSTEM-initiated hard power-off
  (scheduled power action / `Stop-Computer` / update-and-shut-down).
- **Event 41** (Kernel-Power) + **6008** right after = the dirty-power-off
  ARTIFACT (box hard-killed → on reboot it logs "didn't shut down cleanly").
- Absence of **6006** (clean) or a bugcheck = definitively NOT app/hardware crash.
- **Event-log multi-log syntax FAILS**: `-LogName System,Application` →
  "Cannot convert 'System.Object[]'". Loop per-log AND wrap the EventID
  filter in `@(...)` so bash doesn't mangle braces:
    Get-EventLog -LogName System -After (Get-Date).AddHours(-7) |
      Where-Object { $_.EventID -in @(6008,6005,41,1074) }
  Write it to a `.ps1` (inline `$_` gets eaten by MSYS — see skill CRITICAL quirk).
ROOT-CAUSE OUTPUT: "SYSTEM-initiated hard power-off (Reason 0x500ff), not
HW fault/BSOD" + the consequence gap (manually-launched services stayed
down until manual relaunch).

## 2. litellm proxy: default 120s timeout + no fallback = hard fail
- `zbit-heavy` → `hermes3:latest` on a peer Ollama. If NO per-deployment
  `timeout:` is set, **LiteLLM's DEFAULT 120s applies** (litellm.log:
  `request_timeout: None / timeout: None / time taken=120.0`).
- The target model may be PRESENT but VRAM-evicted when N competing models
  share the card → first call cold-reloads >120s → LiteLLM kills it.
  `keep_alive: 10m` does NOT prevent cross-model eviction.
- **No fallback** (`Model Group Fallbacks=None`) → hard fail instead of rerouting
  to a warm node. CLASSIFY as config-gap + resource contention, NOT compromise.
- FIX (needs consent + litellm restart): add `timeout: 45` to the deployment
  + a `fallbacks:` to zbit-fast, OR pin the model with higher keep_alive /
  dedicated VRAM. Verify the target model EXISTS on the node first:
    curl -s http://<ip>:11434/api/tags | <python.exe> -c "import sys,json;
      d=json.load(sys.stdin); n=[m['name'] for m in d.get('models',[])];
      print(any('hermes3' in x for x in n))"
  Use EXPLICIT python.exe (see trap #4) — `python3` is the broken Store stub.

## 3. Service recovery + autostart (close the post-power-off gap)
- **ssh crash loop** (EventLog SCM "terminated unexpectedly" ×N): set
  auto-restart WITHOUT needing the service running —
    sc.exe failure <svc> reset=86400 actions=restart/1000/restart/1000/restart/1000
  Non-elevated CAN set FailureActions. Verify:
    (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\<svc>' -Name FailureActions).FailureActions -ne $null
- **Manually-launched services have NO autostart** → they die on power-off
  and stay down. ZBit (:8400) + LiteLLM (:4001) were launched via a
  `.bat` (manual); only Ollama had a Startup `.lnk`. After a power-off
  they require manual relaunch. FIX = scheduled task `AtStartup` running a
  launcher that starts both (loopback bind preserved).
- **Self-elevate UAC from a background shell is UNRELIABLE**: `Start-Process
  powershell -Verb RunAs` surfaces the prompt on the USER'S desktop — in
  background/non-stealing mode the prompt can't surface, so the elevated task
  silently does NOT get created (verify shows `TASK_NOT_FOUND`). PREFER:
  hand the user the explicit elevated run command (`powershell -File <script>`
  as Administrator) over self-elevation. If you do self-elevate, ALWAYS
  re-verify with `Get-ScheduledTask -TaskName '<name>'` afterward.

## 4. Verification-integrity traps (your checker can be the bug)
When the coding-system guard demands verification evidence, you write a temp
verifier. The trap this session: a MALFORMED boolean in your OWN check
yields false `FAIL` rows even when the file/endpoint is correct.
- **Substring `in` LIES**: `if "FOUND" in "TASK_NOT_FOUND"` is True (substring!).
  Use `.startswith("TASK_FOUND")` or exact `==`. This session's summary line
  once printed "applied: YES" from this bug.
- **socket `recv(200)` truncated before the HTTP body** → a matcher looking
  for `"model"` (LiteLLM returns `"id":`) false-flagged DRIFT. Use
  `recv(1024)` + match `"id":`.
- **`mktemp -p` double-prefixes under MSYS**: resolves to `C:\c\Users\...`
  (doubled drive letter) → python can't open. Use an EXPLICIT absolute path
  for temp verify scripts instead of `mktemp -p`.
- **`python3` / `python` on this host are the BROKEN Windows Store stub**
  ("Python was not found; run without arguments to install"). ALWAYS invoke
  `C:/Users/zqmco/AppData/Local/Programs/Python/Python312/python.exe`
  explicitly in verify scripts.
  Rule: distrust your OWN assertion logic. After the script runs, PROVE the
  state with a DIRECT read (registry `FailureActions`, `Get-ScheduledTask`,
  `recv(1024)`) — that is the real evidence; the script's green/red is
  secondary. State explicitly "ad-hoc verification, not a suite green."

## 5. Persist root-causes (durable artifact, per user expectation)
After decoding, write findings to the SAME fleet SQLite ledger
(`fleet_endpoint_audit.db`) as a `root_cause` table:
  CREATE TABLE IF NOT EXISTS root_cause (
    id INTEGER PRIMARY KEY, finding TEXT, root_cause TEXT,
    evidence TEXT, classification TEXT, ts TEXT );
Classify each: deliberate-poweroff / config-gap / mitigated-crash / etc.
This session persisted 3 rows: (1) 1:24pm = SYSTEM power-off, (2)
litellm zbit-heavy = config-gap+VRAM, (3) sshd crash = mitigated (FailureActions set).

## Hardening applied this session (verified)
- ✅ sshd auto-restart on crash — `sc.exe failure` set (FailureActions 44 bytes).
- ✅ 15-min diagnostics+drift monitoring cron (local, read-only).
- ❌ ZBit/LiteLLM boot autostart task — BLOCKED on UAC (needs user admin run).
- The one true security exposure remains **N2 Redis :6379 unauth** (separate
  finding, needs N2 break-glass cred) — NOT a stability item.
