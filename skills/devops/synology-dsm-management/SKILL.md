---
name: synology-dsm-management
description: Manage Synology DSM NAS devices programmatically from PowerShell/terminal
  — authenticated API sessions, login sweeps across a fleet, and the non-obvious pitfalls
  (form-encoded body vs JSON, PS 5.1 cert handling, DSM auth error codes, port 5000/5001).
  Use when the task is to connect to, log into, or pull status from one or many Synology
  boxes on a LAN. Pairs with windows-secure-credential-handoff for obtaining the admin
  credential without chat exposure.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - synology
    - dsm
    - nas
    - api
    - powershell
    - fleet
    - lan
    - management
    related_skills:
    - homelab-backup
---
# Synology DSM Management

## Overview
Synology NAS boxes expose a DSM web UI (ports 5000 HTTP / 5001 HTTPS) and a JSON-RPC-ish web API at `/webapi/`. The auth endpoint is `SYNO.API.Auth`. This skill covers logging in and sweeping a fleet, with the specific bugs that produce false "invalid password" results.

## When to use
- Connect to / log into a Synology DSM box from script.
- Sweep many Garden/NAS IPs to find which accept a credential.
- Pull DSM status (shares, storage, health) via the API.
- Integrate with `windows-secure-credential-handoff` to avoid pasting the DSM admin password in chat.

## The login call (CRITICAL body-format rule)
DSM `SYNO.API.Auth` login expects **`application/x-www-form-urlencoded`** — i.e. pass a PowerShell hashtable directly to `-Body`. Passing a JSON string (via `ConvertTo-Json`) makes DSM receive empty `account`/`passwd` and return **error 101 "invalid account or password"** even with a CORRECT credential. This false-negative burned a full session before being caught.

CORRECT (form body):
    $r = Invoke-RestMethod -Uri "https://$ip`:5001/webapi/auth.cgi" -Method Post `
         -Body @{api="SYNO.API.Auth"; version=6; method="login"; account=$user; passwd=$pw; session="FileStation"; format="sid"}

WRONG (JSON body → false 101):
    -Body (@{...} | ConvertTo-Json)   # DO NOT DO THIS

## Self-signed cert (PS 5.1)
`Invoke-RestMethod` in PowerShell 5.1 has NO `-SkipCertificateCheck` param. Ignore the self-signed DSM cert with:
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
(Do this once per runspace, before the call.)

## Ports
- 5001 = HTTPS DSM (preferred). 5000 = HTTP DSM.
- Try 5001 first, fall back to 5000. If both time out / refuse, the device is NOT a Synology DSM box (e.g. different vendor — see "Non-DSM devices" below).
- SSH (22) is also open on Synology by default for shell access.

## DSM Auth error codes (from API spec)
| code | meaning |
|---|---|
| 100 | unknown error |
| 101 | invalid account or password  ← most common; usually the JSON-body bug above, or genuinely wrong creds |
| 102 | account disabled |
| 103 | permission denied / 2FA required |
| 104 | login attempts exceeded (lockout) |
| 105 | 2-step auth (TOTP) required |
| 106 | TOTP mismatch |
| 107 | CSRF token needed |

If you get 105/106, the account has 2FA enabled and the API login path can't complete — use SSH or disable 2FA for that account.

## Fleet login sweep
The ready-to-run script `scripts/dsm-login-sweep.ps1` takes a credential file (from `windows-secure-credential-handoff`) and a list of IPs, logs into each on 5001/5000, and reports `LOGIN OK sid=...` vs `REJECTED error=N` vs `NO DSM PORT`. Use it to verify which Gardens accept the stored cred.

## Non-DSM devices
Not every "Garden" is Synology. Devices from other vendors (e.g. MAC `6C:BF:B5` = Noon Technology) may expose SMB/NFS/SSH but NO DSM port 5000/5001. For those, identify the real management plane by probing 80/443 web UI and grabbing the SSH banner; do not assume DSM.

## Pitfalls summary
- JSON body → false 101. Use form-encoded hashtable. (MOST IMPORTANT.)
- PS 5.1: no `-SkipCertificateCheck`; use the ServicePointManager callback.
- `Add-Type -AssemblyName System.Security` before any DPAPI `ProtectedData` use (when consuming stored creds).
- Don't trust a single "error 101" — re-test with the form-body fix before concluding the password is wrong. The user's manual browser login at :5001 is ground truth that the cred is valid.

## References / support files
- `references/dsm-api.md` — full endpoint/error-code/knowledge bank (login URL, form-body rule, PS 5.1 cert bypass, non-DSM vendor notes).
- `scripts/dsm-login-sweep.ps1` — ready-to-run fleet sweep: takes a stored cred name + IP list, logs into each on 5001/5000, reports LOGIN OK / REJECTED error=N / NO DSM PORT. Consumes a windows-secure-credential-handoff JSON file.
