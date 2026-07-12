# Verify the staged fix is actually on the share (before telling the user to run it)

## Why
The user keeps pointing at `\\ZQM-Garden-01\web\Node-X response.txt` / `oneline.txt` — these are THEIR console transcripts and go STALE. A re-run of an old broken command produces a fresh error file that looks like "nothing improved", while the corrected script sits staged and un-run. Never conclude "still broken" from a stale transcript. First PROVE the deliverable on the share is correct, THEN hand the user the run command.

## Read-back probe pattern
Write a .ps1 (NOT inline from bash — MSYS corrupts UNC paths, see pitfall #12) that maps the share with the DPAPI garden cred, reads the staged file, asserts fix markers, prints the first lines, then unmaps.

```powershell
# verify-staged-fix.ps1
Add-Type -AssemblyName System.Security | Out-Null
$p = "C:\zqm\cred\zqm-cred-garden-admin.json"
$o = Get-Content $p -Raw | ConvertFrom-Json
$e = [System.Convert]::FromBase64String($o.data)
$pw = [System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($e, $null, "LocalMachine"))
net use \\192.168.1.173\web /user:$($o.user) $pw /persistent:no 2>$null
$fp = "\\192.168.1.173\web\zqm-bootstrap.ps1"
if (Test-Path $fp) {
  $c = Get-Content $fp -Raw
  Write-Host ("STAGED FILE EXISTS: " + $c.Length + " bytes")
  Write-Host ("contains winrm quickconfig:    " + ($c.Contains('winrm quickconfig')))
  Write-Host ("contains guarded winrm delete: " + ($c.Contains('try { winrm delete')))
  Write-Host ("contains BROKEN New-WSManInstance: " + ($c.Contains('New-WSManInstance')))
  Write-Host ("--- first 3 lines ---")
  ($c -split "`n" | Select-Object -First 3) -join "`n"
} else { Write-Host "STAGED FILE MISSING" }
net use \\192.168.1.173\web /delete /y 2>$null
```

## Run it from bash via cmd.exe (pitfall #6: backslashes survive this way)
```
cp /c/Users/zqmco/verify-staged-fix.ps1 /c/temp/verify.ps1
cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\verify.ps1"
```

## Pass criteria (the fixed bootstrap)
- `winrm quickconfig` present  → enables 5985 for ALL PS versions (not just PS7)
- `try { winrm delete ...HTTPS }` guarded → won't abort on a node with no existing HTTPS listener
- NO `New-WSManInstance` with `Address=""` → the 5986 listener will actually be created
- `Address=*` (asterisk) in the create call

If any criterion fails, RE-PUSH the canonical `zqm-bootstrap.ps1` from `C:\Users\zqmco\` before telling the user to run it.

## Then hand the user the canonical run (pitfall #10 + #14)
```
powershell -NoProfile -ExecutionPolicy Bypass -File \\192.168.1.173\web\zqm-bootstrap.ps1
```
- NO quotes around the path
- `-File` not `-command`
- `-NoProfile` (scoop/starship profile interferes)
- IP form if the `\\ZQM-Garden-01` name doesn't resolve
- Enter the ONE shared `zqmlocal` password (Node-1 DPAPI store value)
