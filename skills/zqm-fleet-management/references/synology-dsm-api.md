# Synology DSM REST API (Gardens)

## Login endpoint
POST https://<ip>:5001/webapi/auth.cgi  (fallback :5000)

## CRITICAL GOTCHA (this is what broke the first sweep)
The auth body MUST be form-encoded. Pass a hashtable to `-Body` so PowerShell URL-encodes it:
```powershell
$r=Invoke-RestMethod -Uri "https://$ip`:5001/webapi/auth.cgi" -Method Post -TimeoutSec 5 `
   -Body @{api="SYNO.API.Auth";version=6;method="login";account=$user;passwd=$pw;session="FileStation";format="sid"}
```
DO NOT do `| ConvertTo-Json -Compress | -Body`. JSON body -> DSM can't parse account/passwd ->
returns error 101 "invalid account or password" EVEN WITH CORRECT CREDENTIALS. This made all
10 Gardens look rejected; the human had actually logged in fine in a browser. Form-encode fixed it.

## Error codes
- 100 unknown | 101 invalid account/password | 102 account disabled
- 103 permission denied / 2FA | 105 2FA required | 106 TOTP mismatch | 107 CSRF needed
- 101 with a valid cred usually means WRONG BODY FORMAT (see above), not a bad password.

## Other notes
- Self-signed cert: set `[System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}`
  (PS 5.1 has no -SkipCertificateCheck).
- On success: `$r.data.sid` is the session token for subsequent calls (FileStation, etc.).
- Garden-04 (192.168.1.144/147, Noon Technology) is NOT Synology: no DSM on 5000/5001,
  /webapi/auth.cgi returns 404. Management method unknown — identify the device first.

## Sweep pattern (all Gardens at once)
Loop the IP list, try 5001 then 5000, form-encode the body, report LOGIN OK / REJECTED error=N /
NO DSM PORT. Full working version used in-session against 12 IPs: 10 OK, 2 (Garden-04) no DSM port.
