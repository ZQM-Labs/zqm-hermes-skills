# MSA / "account works but remote auth rejected" diagnostic

Runnable playbook for the stall where the owner insists a credential "works properly" but your
headless SSH/WinRM probe returns `AuthenticationException` / "Access is denied". Treat the owner
claim as a hypothesis and recreate it with a live probe.

## 1. Account type + local alias (run on the machine the owner logs into)
```powershell
Get-LocalUser | Select-Object Name,Enabled,PrincipalSource,SID
```
- `PrincipalSource=MicrosoftAccount` + SID `S-1-5-21-…` → MSA mapped to a LOCAL SAM alias
  (e.g. `zqmcomputing@gmail.com` → local name `zqmco`). Console/RDP accepts the MSA; headless
  SSH/WinRM may reject it, or the password given belongs to a different system.
- `PrincipalSource=Local` → true local account.

## 2. Does sshd accept the account?
```powershell
Get-Content 'C:\ProgramData\ssh\sshd_config' | sls 'Match|AllowUsers|AuthenticationMethods|PasswordAuthentication'
```
Default `Match Group administrators` strips admin rights unless overridden.

## 3. Does WinRM actually listen? (Running service + empty listener still rejects)
```powershell
Get-ChildItem WSMan:\localhost\Listener   # expect an http/https entry; empty = no listener
```

## 4. Live credential test against the REAL target (Python/paramiko or ssh.exe)
Test BOTH forms with the EXACT password:
```python
import paramiko
host, pw = '192.168.1.215', '<the-password>'
for u in ['zqmcomputing@gmail.com', 'zqmco', '.\\zqmco']:
    try:
        c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(host, 22, u, pw, timeout=10, look_for_keys=False, allow_agent=False)
        print(u, 'OPEN', c.exec_command('whoami')[1].read().decode().strip()); c.close()
    except paramiko.AuthenticationException:
        print(u, 'REJECTED')
```
If all forms REJECTED → the password does NOT match the Windows login.

## 5. Cross-system password trap (critical)
A password that works for a Garden (SMB/SSH to Synology/TerraMaster, user `azelenski`) proves
NOTHING about Windows-node auth. Garden accounts are not Windows-local. If the owner supplies a
password that succeeds against a Garden but fails against a node, it is the GARDEN password, not
the Windows login password — stop retrying it against nodes.

## ZQM case study (Node-4 reconcile, 2026-07-12)
- Node-4 (.215): ping UP, ports 22/445/5985/5986 OPEN, but vaulted `zqmlocal/EllaRose89!`
  REJECTED on SSH + WinRM ("Access is denied").
- Owner supplied `zqmcomputing@gmail.com / 344SW00DL4nd!` claiming it "works properly". Live test:
  REJECTED on Node-1, Node-3, Node-4, and all unidentified Windows-candidate hosts.
- Diagnostic on Node-1: `zqmco`/`AlexZ` are `PrincipalSource=MicrosoftAccount` (the
  `zqmcomputing@gmail.com` identity); `Administrator` disabled; no local `zqmlocal`.
- Conclusion: `344SW00DL4nd!` is the GARDEN admin password (`azelenski`), reused by assumption;
  it is NOT the Windows login password. The MSA cannot be used for workgroup headless auth.
- Resolution requires a valid Node-4 LOCAL admin password (not the gmail/MSA, not the garden pw)
  or local console `Set-LocalUser -Name zqmlocal -Password (ConvertTo-SecureString '<win-pw>' -AsPlainText -Force)`.

## Subnet sweep to locate an undefined node (e.g. "Node 5" with no topology entry)
Before assuming a host doesn't exist, discover live hosts:
```python
import subprocess, concurrent.futures
def ping(ip):
    try:
        r = subprocess.run(['ping','-n','1','-w','500',ip], capture_output=True, text=True, timeout=4)
        return ip if 'Reply from' in r.stdout else None
    except: return None
ips=[f'192.168.1.{i}' for i in range(1,255)]
live=[x for x in concurrent.futures.ThreadPoolExecutor(max_workers=80).map(ping,ips) if x]
# then TCP-scan 22/5985 on the unknown ones to find Windows nodes
```
Absence from a stale topology file is NOT proof of absence from the LAN.
