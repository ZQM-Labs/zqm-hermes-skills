# zqm-dpapi-ssh.ps1
# Decrypt a LocalMachine-scope DPAPI JSON credential and run a command over SSH
# via the ComfyUI venv python (paramiko). The password is decrypted in PowerShell
# and passed to python as an argv -- it is NEVER printed and NEVER written to disk.
#
# WHY THIS PATTERN: hand-rolling DPAPI in python ctypes fails (WinError 87), and the
# execute_code sandbox python lacks paramiko. The reliable path is: decrypt in PS
# ([System.Security.Cryptography.ProtectedData]::Unprotect LocalMachine), then call
# the venv python with the secret as an argument.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File zqm-dpapi-ssh.ps1 `
#     -CredPath C:\zqm\cred\zqm-cred-garden-admin.json `
#     -Hosts 192.168.1.144,192.168.1.147 -Cmd "hostname; uptime"
param(
  [string]$CredPath = "C:\zqm\cred\zqm-cred-garden-admin.json",
  [string[]]$Hosts  = @("192.168.1.144"),
  [string]$Cmd      = "hostname",
  [int]$Port        = 22,
  [string]$VenvPy   = "C:\Users\zqmco\Documents\comfy\ComfyUI\.venv\Scripts\python.exe"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Security | Out-Null
if (-not (Test-Path $CredPath)) { Write-Host ("NO CRED FILE: " + $CredPath); exit 1 }
$o = Get-Content $CredPath -Raw | ConvertFrom-Json
$enc = [Convert]::FromBase64String($o.data)
$pw = [System.Text.Encoding]::UTF8.GetString(
  [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, "LocalMachine"))
$user = $o.user
Write-Host ("Decrypted credential for user: " + $user + " (password not printed)")

$py = @"
import paramiko, sys
hosts=sys.argv[1].split(',')
user=sys.argv[2]; pw=sys.argv[3]; cmd=sys.argv[4]; port=int(sys.argv[5])
for ip in hosts:
    try:
        c=paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(ip,port,user,pw,timeout=10,look_for_keys=False,allow_agent=False)
        stdin,stdout,stderr=c.exec_command(cmd)
        print('  '+ip+' -> '+stdout.read().decode().replace(chr(10),' | ').strip())
        c.close()
    except paramiko.AuthenticationException:
        print('  '+ip+' -> AUTH FAIL (wrong user/password for SSH on this host)')
    except Exception as e:
        print('  '+ip+' -> ERR '+type(e).__name__+': '+str(e)[:60])
"@
$py | Set-Content C:\temp\zqm_dpapi_ssh_runner.py
& $VenvPy C:\temp\zqm_dpapi_ssh_runner.py ($Hosts -join ',') $user $pw $Cmd $Port
