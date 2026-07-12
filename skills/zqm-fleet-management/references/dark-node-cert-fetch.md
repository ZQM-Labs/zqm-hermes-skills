# Dark-node bootstrap: HTTP fetch + Cert: mount (pitfall #16 + #17)

## Problem
The canonical `zqm-bootstrap.ps1` builds the 5986 HTTPS listener cert with:
```
$cert = New-SelfSignedCertificate -Subject "CN=$env:COMPUTERNAME" -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
```
Under `powershell -File` with `-NoProfile`, the `Cert:` PSDrive is NOT
auto-mounted, so this throws:
```
New-SelfSignedCertificate : Cannot find drive. A drive with the name 'Cert' does not exist.
```
With `$ErrorActionPreference="Stop"` the whole script aborts here — so the
node gets 5985 + zqmlocal but NO 5986 and NO OpenSSH. Seen on Node-2 this
session: it ran the HTTP-fetched bootstrap and died at exactly this line.

Why Node-4 worked earlier: its run used `-command "..."`, which mounts
Cert:. `-command` vs `-File -NoProfile` is the entire difference.

## Constraint (pitfall #18, CORRECTED 2026-07-10)
WRITE behavior to `\\ZQM-Garden-01\web\` is METHOD-SPECIFIC:
- `write_file` tool (MSYS `//host/path`) and `cmd /c "echo > \\host\share\x"` → SILENTLY FAIL (report success, nothing lands).
- NATIVE PowerShell `Copy-Item`/`Set-Content`/`New-Item` to the UNC → WORKS and PERSISTS on the SMB `web` share. Verified: `Copy-Item -Path 'C:\temp\x.ps1' -Destination '\\ZQM-Garden-01\web\zqm-bootstrap.ps1' -Force` then read-back showed the new bytes. ALWAYS verify a write by reading the UNC back — the write_file tool lies.
- CRITICAL DECOUPLING: the HTTP web server serves from a FROZEN store SEPARATE from the SMB `web` share. So even after you PowerShell-write the patched script to the SMB share, `curl http://ZQM-Garden-01/zqm-bootstrap.ps1` STILL returns the OLD copy. A node's HTTP-fetch does NOT see your SMB write.
So: the agent CAN drop a corrected script on the SMB share for the USER to grab, but the node's own HTTP-fetch gets the frozen server copy. Deliver the node-run fix as the inline `-Command` form below — never rely on "I fixed the served script."

## Working node command (defeats 3 bugs at once)
Paste on Node-2/3 (elevated). HTTP-fetch defeats UNC backslash-doubling
(#16) and the no-SMB-cred wall (#16); the inline `-Command` pre-mounts
Cert: (#17) before running the fetched script in the same session:

```
cmd /c "mkdir C:\zqm 2>nul & curl -s -o C:\zqm\bootstrap.ps1 http://ZQM-Garden-01/zqm-bootstrap.ps1 & powershell -NoProfile -ExecutionPolicy Bypass -Command `"New-PSDrive -Name Cert -PSProvider Certificate -Root \ -ErrorAction SilentlyContinue; & C:\zqm\bootstrap.ps1`""
```

Notes:
- Use hostname `ZQM-Garden-01` (→ 192.168.1.173). Do NOT use IP 192.168.1.40
  (that is Garden-02, a different box). Verified: http://ZQM-Garden-01/zqm-bootstrap.ps1 → 200, 3554 bytes.
- `New-PSDrive -Name Cert ... -Root \` inside `-Command` mounts the
  Certificate provider; `-ErrorAction SilentlyContinue` makes it a no-op if
  already present (e.g. on a `-command`-style run).
- The `& C:\zqm\bootstrap.ps1` runs in the SAME powershell session, so the
  just-mounted Cert: drive is live for the whole script including line 35.
- The inline has NO `$_` / bare `*` / backtick / `@{}`, so it survives the
  paste-corruption transport (pitfall #9).

## If you CAN edit the served script (user on Garden-01)
Add right after the `New-Item -ItemType Directory ...` line in
`zqm-bootstrap.ps1`:
```powershell
# ensure Cert: PSDrive exists (absent under -NoProfile shells)
if (-not (Test-Path Cert:)) { try { New-PSDrive -Name Cert -PSProvider Certificate -Root \ -ErrorAction Stop | Out-Null } catch { Write-Host "Note: could not auto-mount Cert: drive" } }
```
Then the plain HTTP-fetch wrapper (pitfall #16) suffices.

## Verify after run
Node response file should contain:
`Bootstrap complete on ZQM-NODE-X. WinRM 5985 (quickconfig) + 5986 (HTTPS) enabled, zqmlocal stored to DPAPI.`
If it still shows `Cannot find drive 'Cert'`, the Cert: mount line is not
taking effect — confirm the `-Command` wrapper (not bare `-File`) was used.
