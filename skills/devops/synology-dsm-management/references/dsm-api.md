# Synology DSM API — knowledge bank

## Login endpoint
POST https://<ip>:5001/webapi/auth.cgi   (5001 = HTTPS, 5000 = HTTP fallback)
Form body (application/x-www-form-urlencoded — NOT JSON):
  api=SYNO.API.Auth&version=6&method=login&account=<user>&passwd=<pw>&session=FileStation&format=sid

CRITICAL: pass a PowerShell HASHTABLE to -Body so it is form-encoded. Using
`ConvertTo-Json` makes DSM receive empty account/passwd and return a FALSE
error 101 even with a correct password. (This false-negative burned a full
session before being caught — see pitfall in SKILL.md.)

## PS 5.1 self-signed cert
No `-SkipCertificateCheck` in PS 5.1. Use:
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

## Auth error codes
| code | meaning |
|---|---|
| 100 | unknown error |
| 101 | invalid account or password (usually the JSON-body bug, or genuinely wrong creds) |
| 102 | account disabled |
| 103 | permission denied / 2FA required |
| 104 | login attempts exceeded (lockout) |
| 105 | 2-step auth (TOTP) required |
| 106 | TOTP mismatch |
| 107 | CSRF token needed |

## Session reuse
The returned `sid` is the session token. Pass it back as `?_sid=<sid>` or in a
web session for subsequent calls (SYNO.* APIs: FileStation, DSM, etc.).

## Non-DSM devices
Not every "Garden" is Synology. Vendor MAC 6C:BF:B5 (Noon Technology) devices
expose SMB/NFS/SSH but NO DSM port 5000/5001. Identify their management plane by
probing 80/443 web UI and grabbing the SSH banner; do not assume DSM.

## Gotchas
- 105/106 = account has 2FA; API login can't do TOTP -> use SSH or disable 2FA.
- Synology is not Windows: do NOT use WinRM/New-CimSession (no WinRM service) —
  it returns the TrustedHosts/Kerberos error. Use REST API or SSH (port 22 open).
- A single "error 101" is NOT proof the password is wrong — fix the body format
  first; the user's manual browser login at :5001 is ground truth the cred is valid.
