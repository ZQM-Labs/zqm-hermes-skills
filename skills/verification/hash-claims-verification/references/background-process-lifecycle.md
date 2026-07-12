# Windows Background-Process Lifecycle (corrected, 2026-07-12)

## The trap
On this Windows host the Hermes `process` tool's session_id/PID tracking DIVERGES
from the real OS. Long-lived servers started via `terminal(background=true)` keep
running even after `process kill <session_id>` reports "killed", and stale session
records re-fire `watch_patterns` later — sending the agent on ghost hunts.

## What ACTUALLY happened (verified, not assumed)
A session built an API attestation server and, suspecting stale state, issued three
`process kill` calls on three different session_ids, then started a fresh one, over
and over. The `process` tool reported "killed" each time. A `watch_patterns` match
("attestation API on") then fired for EACH of the supposedly-dead sessions — four
times total (proc_1887af582829, proc_6e3f73428cdf, proc_43b9bea051, proc_86e548808ce6).

The naive read: "the OS process survived all kills; the original server kept
serving on :8088." THIS WAS WRONG. Proven with authoritative OS probes:

1. `netstat -ano | grep ":8088"` ever showed EXACTLY ONE LISTENING PID at a time
   (7204 at the end). A port cannot double-bind, so at most one server was ever up.
2. `taskkill /PID 7388 /F` returned "SUCCESS: The process with PID 7388 has been
   terminated." and a follow-up `netstat` showed `8088 free`. The kill WORKED.
3. `Get-CimInstance Win32_Process ... | Where-Object { $_.CommandLine -like
   '*api_server*' }` ever returned exactly ONE PID. The others were dead.

Corrected mechanism:
- `process kill` DID terminate the OS process. Each restart spawned a NEW OS PID;
  the SURVIVOR was simply the NEWEST spawn. Kills worked.
- The watch-pattern re-fires were ZOMBIE SESSION RECORDS: each killed session still
  had its buffered stdout startup line ("...attestation API on...") and the matcher
  re-emitted it against old text. A watch match is NOT proof of liveness.

## The rules (embed these)
- A `watch_patterns` match is a HINT, not evidence. Before killing or restarting,
  PROVE liveness with netstat.
- LISTENING = live server. TIME_WAIT = a leftover socket from a curl call, NOT a
  server. Do not count TIME_WAIT lines as processes.
- Source of truth = `netstat -ano | grep ":<port>"` + `Get-CimInstance`. Ignore the
  `process` tool's session_id/PID labels.
- Kill by REAL pid: `taskkill /PID <pid> /F`. Confirm free with netstat.
- After any restart, re-curl a known claim (e.g. /attest/claim/B4) — Python imports
  the core once at startup, so a stale process serves stale claims.

## Net commands (MSYS/git-bash shell — use grep, not findstr)
    netstat -ano | grep ":8088"          # real listener PID in last column
    powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -like '*api_server*' } | Select-Object ProcessId"
    taskkill /PID <pid> /F
