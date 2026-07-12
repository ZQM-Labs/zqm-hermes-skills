# Synology Garden SSH Failover (DSM → SSH, same `azelenski` cred)

## Verified result (2026-07-10)
The Synology Gardens (Garden-01/02/03 fleet) accept the SAME DPAPI-stored `azelenski` credential over BOTH:
- Primary: DSM HTTPS API on :5001 (`auth.cgi`, form-encoded body → sid)
- Backup: **SSH on :22** via paramiko

Probe output (real):
```
GARDEN-02(40)  192.168.1.40  SSH FAILVOER OK -> hostname=ZQM-GARDEN-02
GARDEN-03(64)  192.168.1.64  SSH FAILVOER OK -> hostname=ZQM-GARDEN-03
Garden-01(173) 192.168.1.173 SSH FAILVOER OK -> hostname=ZQM-Garden-01
```
All 10 Synology Gardens have port 22 OPEN (confirmed via TCP probe), so DSM→SSH failover is available fleet-wide.

## Why this matters
If DSM API (5001) ever fails (cert, service crash, firewall), SSH on 22 still reaches the box with the identical credential. No second secret to manage.

## How to run the failover test (password never printed)
PowerShell decrypts the DPAPI cred and passes it as argv to the venv python (do NOT hand-roll DPAPI in Python — see failure-mode table):
```powershell
Add-Type -AssemblyName System.Security
$p = "C:\zqm\cred\zqm-cred-garden-admin.json"
$o = Get-Content $p -Raw | ConvertFrom-Json
$enc = [Convert]::FromBase64String($o.data)
$pw = [System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($enc,$null,"LocalMachine"))
$py = @"
import paramiko, sys
user, pw = sys.argv[1], sys.argv[2]
for name, ip in {"GARDEN-02":"192.168.1.40","GARDEN-03":"192.168.1.64","Garden-01":"192.168.1.173"}.items():
    try:
        c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(ip,22,user,pw,timeout=10,look_for_keys=False,allow_agent=False)
        print(name, ip, "SSH OK ->", c.exec_command("hostname")[1].read().decode().strip()); c.close()
    except paramiko.AuthenticationException:
        print(name, ip, "SSH AUTH FAIL")
"@
$py | Set-Content C:\temp\synossh.py
& "C:\Users\zqmco\Documents\comfy\ComfyUI\.venv\Scripts\python.exe" C:\temp\synossh.py $o.user $pw
```
Invoke via `cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\run.ps1"` (see `-File` backslash gotcha in SKILL.md failure table).

## Note
TerraMaster GARDEN-04 uses SSH as its PRIMARY (no DSM). Its failover is moot unless a TOS API is found. See `terramaster-garden-management.md`.
