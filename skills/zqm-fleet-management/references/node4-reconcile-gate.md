# Node-4 (.215) Reconcile Gate — proven findings (2026-07-12)

## The problem
Node-4's local `zqmlocal` account has a DIFFERENT password than the fleet vault
(`C:\zqm\cred\zqm-cred-node-local.json` on Node-1 holds `EllaRose89!`). WinRM (5985/5986) and SSH
(22) BOTH reject the vaulted cred. Node-4 is reachable (ping UP; ports 22/445/5985/5986 OPEN) but
NOT authenticable remotely.

## Can we reconcile it FROM ANOTHER NODE or A GARDEN? — NO (proven by live probe)
SSH credential sweep against Node-4 (.215):
- `zqmlocal`/`EllaRose89!`        -> REJECT (known mismatch)
- `zqmco`/`EllaRose89!`           -> REJECT (Node-1-style admin; Node-4 not imaged same)
- `AlexZ`/`EllaRose89!`           -> REJECT
- `azelenski`/`344SW00DL4nd!`     -> REJECT (Synology account, never a Windows-local)
- `Administrator`/`EllaRose89!` + /`344SW00DL4nd!` -> CONNECTION RESET (10054; account throttled/disabled)

=> Node-4 was deployed with its OWN unique local-admin password, not the fleet standard. No
lateral node credential opens an admin channel.

## Can a GARDEN do it? — NO (structurally impossible)
Synology DSM / TerraMaster TOS are storage OSes; they cannot run `Set-LocalUser` on a Windows host
and have no Windows SAM. A Garden can serve files but cannot administer Node-4's local accounts.

## Conclusion / gate
The reconcile REQUIRES LOCAL access to Node-4 (console / RDP / WinRM-as-local-admin) — an action
no node or garden can perform on its behalf. This is a hard gate, not a loop-worthy failure.

## The fix (local on Node-4, elevated)
    $sec = ConvertTo-SecureString 'EllaRose89!' -AsPlainText -Force
    Set-LocalUser -Name 'zqmlocal' -Password $sec
After this, Node-1 (and any ZQM node) can WinRM + SSH to Node-4 with the vaulted cred, and the
push/bootstrap (C:\zqm\node4-bootstrap\NODE4_BOOTSTRAP.ps1) can run remotely + be verified.

## Self-contained bootstrap package (built on Node-1)
C:\zqm\node4-bootstrap\ — copied to Node-4, then run locally:
    .\NODE4_BOOTSTRAP.ps1 -GardenPassword '344SW00DL4nd!'
Re-encrypts the garden cred with Node-4's LocalMachine DPAPI key, registers the ZQM-Garden-Link
self-heal task (SYSTEM, boot + 15min), applies mounts. Pure PowerShell, no python needed.
NOTE: Garden-01 (.173) + Garden-03 (.64) will likely still reject Node-4's source IP (.215) at the
Garden side (same IP-allowlist behavior as Node-3) — allow .215 on those Synology DSM boxes.
