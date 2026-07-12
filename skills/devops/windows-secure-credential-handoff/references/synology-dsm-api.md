# Using a handed-off credential against Synology DSM

This was the first real consumer of the secure-credential-handoff skill
(see SKILL.md). The human stored the DSM admin cred via the STORE one-liner;
the agent consumed it and called the DSM JSON API.

## Login API
POST https://<garden-ip>:5001/webapi/auth.cgi
body (form): api=SYNO.API.Auth&version=6&method=login&account=<user>&passwd=<pw>&session=FileStation&format=sid

PowerShell (PS 5.1) — note the self-signed-cert bypass for PS 5.1:
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    # PASS A HASHTABLE DIRECTLY (form-encoded). Do NOT ConvertTo-Json — DSM expects
    # application/x-www-form-urlencoded; a JSON body makes account/passwd arrive EMPTY
    # and DSM returns a FALSE error 101 "invalid account or password" even with a
    # CORRECT credential. (This false-negative wasted a full session before caught.)
    $r = Invoke-RestMethod -Uri "https://192.168.1.40:5001/webapi/auth.cgi" -Method Post `
         -Body @{api="SYNO.API.Auth";version=6;method="login";account=$o.user;passwd=$pw;session="FileStation";format="sid"}
    if ($r.success) { "LOGIN OK sid=" + $r.data.sid.Substring(0,10) + "..." } else { "REJECTED error=" + $r.error.code }

NOTE: `-SkipCertificateCheck` is a PS 7+ parameter and does NOT exist in PS 5.1
(error: "A parameter cannot be found that matches parameter name 'SkipCertificateCheck'").
Use the `[ServicePointManager]` callback instead.

## DSM Auth error codes (from Synology API spec)
| code | meaning |
|---|---|
| 100 | unknown error |
| 101 | invalid account or password  <-- what we hit; means the STORED cred is wrong, NOT a handoff failure |
| 102 | account disabled |
| 103 | permission denied / 2FA required |
| 104 | login attempts exceeded |
| 105 | 2-step auth (TOTP) required |
| 106 | TOTP mismatch |
| 107 | CSRF token needed |

## Gotchas
- If you get 101, the pipeline WORKED — the human simply entered the wrong
  account/password for that NAS. Re-run the STORE one-liner with correct creds;
  do NOT debug DPAPI/Unprotect.
- 105/106 means the account has 2FA; the DSM login API cannot do TOTP. Disable
  2FA for that account or use SSH instead.
- Garden TCP surfaces (port scan): SSH(22), HTTP(80), HTTPS(443), DSM(5000/5001),
  NFS(111/2049) all open on the ZQM Gardens; SNMP(161) closed on all.
- SMB `web` share on Garden-02 (192.168.1.40) is writable by a cached no-cred
  IPC$ session from Node-1 — handy for script drop. But `azelenski` could not
  SMB-auth to it; the correct DSM admin account name may differ from the SMB
  account. Confirm the exact account name with the user.
- A Synology is NOT a Windows host: do NOT use WinRM/CIM (New-CimSession) against
  it — it returns the TrustedHosts/Kerberos error because there is no WinRM.
  Use the REST API or SSH.
