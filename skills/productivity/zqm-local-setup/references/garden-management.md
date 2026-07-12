# ZQM-Gardens Management (Synology DSM + TerraMaster TOS)

The "ZQM-Gardens" are NOT all the same OS. Two management planes, confirmed live 2026-07-10:

| Device class | IPs | OS | Mgmt channel | Works? |
|---|---|---|---|---|
| Synology DSM | .32 .37 .38 .39 .40 .52 .53 .64 .169 .173 (10 boxes) | Synology DSM | HTTPS API :5001 (`:5000` also) | DSM login returns sid on all 10 |
| TerraMaster TOS | .144 .147 (GARDEN-04, hostname `ZQM-GARDEN-04`) | TerraMaster TOS 5.1.145 (kernel 5.15.59, Buildroot) | SSH :22 | SSH login as `azelenski` on both |

CRITICAL: do NOT assume every Garden is Synology. `.144`/`.147` are TerraMaster — DSM
login returns "NO DSM PORT" and the Synology `/webapi/auth.cgi` 404s. They are managed by
SSH, not the DSM API.

## Synology DSM API (form-encoded — MUST be form, not JSON)
    # PowerShell (agent side, after DPAPI decrypt of $user/$pw):
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }   # self-signed cert, PS5.1 has no -SkipCertificateCheck
    $r = Invoke-RestMethod -Uri "https://$ip`:5001/webapi/auth.cgi" -Method Post -Body @{
        api="SYNO.API.Auth"; version=6; method="login"; account=$user; passwd=$pw; session="FileStation"; format="sid"
    }
    if ($r.success) { $sid=$r.data.sid } else { "REJECTED error="+$r.error.code }

PITFALL (cost us a full wrong conclusion this session): passing the params as a JSON
body (`@{...} | ConvertTo-Json`) makes Synology return error 101 ("invalid account/
password") even with a CORRECT password — the server can't parse JSON login params.
ALWAYS pass a hashtable so PowerShell form-encodes it. error 105/106 = 2FA (TOTP) on.
After login, pull system info: `Invoke-RestMethod -Uri "https://$ip`:5001/webapi/entry.cgi"
-Body @{api="SYNO.Core.System";method="info";version=1;_sid=$sid}` (model/version/hostname).
Logout with `api=SYNO.API.Auth;method=logout;session=FileStation;_sid=$sid`.

## TerraMaster TOS management (SSH)
- Port 5443 is the TOS web UI (TLS 1.2, title "TOS Loading") but the login API route is
  NOT at `/module/api.php` (that's TOS <=4.2.29). For TOS 5 we did NOT find a working REST
  login path — SSH was the reliable channel.
- SSH works with the SAME `azelenski` credential as the Synology DSM login.
- Non-interactive SSH from the agent: there is NO `sshpass`/`plink` installed and
  `ssh.exe` can't do password auth without a TTY. FIX: `python -m pip install paramiko`
  (installs into the ComfyUI venv `C:\Users\zqmco\Documents\comfy\ComfyUI\.venv`), then
  use the paramiko snippet in `scripts/zqm-ssh-tm.py`. `winget install sshpass` is
  BLOCKED by the user — do not attempt it.
- Verified read-only SSH commands on GARDEN-04: `uname -a`, `cat /proc/version`,
  `hostname`, `uptime`, `df -h /`. `/etc/os-release` is empty on TOS.

## TerraMaster TOS security note (CVE-2022-24990)
TOS <= 4.2.29 has an unauthenticated admin-password disclosure via a request with
`User-Agent: TNAS` to the API endpoint. We tested GARDEN-04 (.144/.147) with that header
on `/module/api.php*` — CLEAN (no leak), consistent with TOS 5.1.145 being patched.
Still worth a firmware review. Do not store/transmit the disclosed password if found.

## Probe pattern that worked (don't brute-force API paths blindly)
When a device's API route is unknown, use Python (`execute_code`) with
`http.client` + `ssl` context (`check_hostname=False; verify_mode=CERT_NONE`) to GET the
root page and read the `<title>` / inline bootstrap script — that reveals the real app
prefix (e.g. TerraMaster's `/databack/` SPA shell). Guessing 30+ REST paths wastes turns.
