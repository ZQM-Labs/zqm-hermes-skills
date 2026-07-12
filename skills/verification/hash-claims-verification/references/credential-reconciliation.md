# Credential reconciliation & "can't be done" gate enumeration (ZQM fleet)

Concrete procedure used when a remote target (e.g. Node-4) rejects the known vaulted
credential and the owner says "you should be able to do whatever I can." The point: a
"can't reach / can't reconcile from another node or garden" claim is ONLY valid AFTER a
FULL enumeration is LIVE-tested. Half a probe is not proof.

## The enumeration checklist (run every item, record live result)
1. **Decrypt the DPAPI vaults on the source host** to confirm the EXACT password being tested
   (don't trust memory of what the blob holds):
   ```powershell
   Add-Type -AssemblyName System.Security
   $o = Get-Content C:\zqm\cred\zqm-cred-node-local.json -Raw | ConvertFrom-Json
   [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect(
     [Convert]::FromBase64String($o.data), $null, 'LocalMachine'))
   ```
2. **Enumerate Windows Credential Manager** (`cmdkey /list`) — often holds `Domain:target=<IP>`
   garden creds (azelenski). List them so you can state "nothing here opens the target."
3. **Test every stored credential against the target over BOTH protocols**:
   - SSH (paramiko) on :22
   - WinRM Negotiate on :5985 (`New-CimSession -Port 5985 -Authentication Negotiate -Credential`)
   Candidates: vaulted node-local (`zqmlocal`), source-host local admins (`zqmco`/`AlexZ` +
   fleet pw — only if target imaged same), target `Administrator`, garden `azelenski` (NOTE:
   Synology/TerraMaster account, NOT Windows-local — structurally cannot administer a Windows
   node), and any Microsoft-account UPN the owner supplies (usually rejected — nodes use local
   SAM, not MSA).
4. **Avoid SSH 10054 throttle**: rapid retries trip connection resets that LOOK like auth
   failure. Test `Administrator` over WINRM (not SSH) for a clean "Access is denied". Space
   retries with `time.sleep`.
5. **Subnet sweep to locate unidentified hosts** (a "Node 5" may exist at an unguessed IP):
   - threaded `ping -n 1` 192.168.1.1-254; collect live hosts.
   - probe :22 + :5985 on each UNKNOWN live host to find Windows nodes.
   - test the owner cred against each unidentified Windows-candidate host.
6. **Rule out a hypervisor / IPMI / iDRAC plane**: probe target neighbors for 623 (IPMI),
   8006 (Proxmox), 5900 (VNC), 443 (HTTPS mgmt). A host-console plane can inject `Set-LocalUser`
   without the target's local pw.

## Proven conclusion (only after ALL of the above fail)
"No stored credential reaches the target; no garden can administer a Windows SAM; no mgmt
plane found. Reconcile requires a LOCAL action on the target (console/RDP/WinRM-as-local-admin)
or an owner-supplied target-local admin password." Stated WITH evidence, not "can't."

## Node-4 case study (2026-07-12, fully enumerated)
- Vault decrypt: `zqmlocal` / 11-char `EllaRose89!` (vault-confirmed).
- .215: SSH REJECT, WinRM 5985 "Access is denied" (auth reached host, refused).
- `zqmco`/`AlexZ`+fleet pw: REJECT. `azelenski`+garden pw: REJECT (garden/MSA acct).
  `Administrator`+fleet/garden pw: WINRM "Access is denied". `zqmcomputing@gmail.com`+garden pw:
  REJECT on .215 AND on Node-1 itself (proves nodes use local SAM, not the MSA).
- Subnet sweep: 38 live hosts; Windows nodes = Node-1(.218), Node-3(.46), Node-4(.215);
  Node-2(.21) ABSENT (dead). Unidentified SSH-open hosts (.164/.170/.210/.220) all REJECTED the
  owner cred. No hypervisor/IPMI plane found on neighbors.
- CONCLUSION: Node-4 deployed with a unique local-admin pw not stored anywhere reachable.
  Gate = owner supplies Node-4 local-admin pw OR reaches its console.
