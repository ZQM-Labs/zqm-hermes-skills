# TerraMaster GARDEN-04 Management (TOS 5.x)

## Identity (verified 2026-07-10)
- IPs: `192.168.1.144` and `192.168.1.147` — BOTH resolve to hostname `ZQM-GARDEN-04` (one unit / cluster pair).
- MAC OUI `6C:BF:B5` = Noon Technology Co., Ltd, BUT the device is a **TerraMaster** NAS running **TOS 5.1.145-00320**.
- Kernel: `Linux 5.15.59 #246 SMP` (Buildroot 2022.02, x86_64). `/etc/os-release` is empty on TOS.
- Open ports: 22 (SSH), 80 (HTTP, 301→HTTPS), 443, 5443 (HTTPS, valid TLS 1.2 ECDHE-RSA-AES128-GCM-SHA256, self-signed).
- CLOSED: 5000/5001 (no Synology DSM), 8443.

## Management plane that WORKS: SSH (not the web API)
The TOS 5 web API login route is NOT at any of the standard/synology/TOS4 paths:
  - 404 on: `/api/login`, `/module/api.php?api=login`, `/webapi/auth.cgi`, `/databack/*`, `/api/v1/*`, etc.
  - The SPA serves "TOS Loading" at `https://<ip>:5443/` and bootstraps from `/data/jquery.js` + `/databack/complete`, but the backend auth route was not found by enumeration. Do NOT burn time brute-forcing it.
- **SSH works**: the same DPAPI-stored `azelenski` credential logs in via password auth on port 22 on BOTH IPs. Verified: `uname -a` returned the kernel above.

## How to SSH non-interactively from the agent (Node-1, Windows)
`ssh.exe` is present but cannot do non-interactive password auth (needs a TTY/sshpass). `plink`/`sshpass` are ABSENT.
Working method: **paramiko via Python** (installed this session with `python -m pip install paramiko` into the ComfyUI venv — no admin needed).

Run pattern (PowerShell decrypts DPAPI, passes args to python; password never printed):
```
$p = "C:\zqm\cred\zqm-cred-garden-admin.json"
$o = Get-Content $p -Raw | ConvertFrom-Json
$enc = [Convert]::FromBase64String($o.data)
$pw = [System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($enc,$null,"LocalMachine"))
foreach ($ip in @("192.168.1.144","192.168.1.147")) {
  & python C:\Users\zqmco\scripts\zqm-ssh-tm.py $ip $o.user $pw
}
```

## PowerShell `-File` path gotcha (Windows/MSYS)
`powershell -File C:\Users\zqmco\...\x.ps1` passed through bash/cmd strips backslashes → "file does not exist". Two reliable fixes:
  1. Copy the script to a simple path first, then: `cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\probe.ps1"`
  2. Or pipe script text via stdin: `cat script.ps1 | powershell -Command -` (less reliable; use #1).
Inline `-Command "...big script..."` often hits ParserErrors with `[...]`/`$matches`; prefer writing to a `.ps1` and the `cmd.exe /c` trick.

## Security note
- CVE-2022-24990 (TOS ≤4.2.29 unauthenticated admin-password leak via `User-Agent: TNAS`) was TESTED and came back CLEAN on both boxes (no leak on probed paths; likely TOS5 patched). Still worth a firmware check, but not an active emergency per this probe.
- Treat GARDEN-04 as a separate device class from the Synology Gardens — different OS, different cred model (though `azelenski` happened to work for both here).

## Read-only commands to run first (once SSH works)
`uname -a`, `df -h`, `cat /proc/mounts`, `ls /Volume*`, `uptime`, `free -m`, `smartctl --scan` (if present), `cat /etc/TNAS*.conf`.
Avoid writes until the user confirms.
