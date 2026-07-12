# Resilient Garden Link — unbreakable Node → ZQM Garden connections

VERIFIED 2026-07-12 from Node-1 (192.168.1.218). Companion code: `templates/zqm-garden-link.ps1`
+ `templates/zqm-garden-topology.json`. This is the method behind the user's standing goal of
making ZQM Node↔Garden connections "unbreakable".

## The fragility we found (why links break)
1. **SMB mounts were session-only.** `net use` without `/persistent:yes` dies on reboot. The fleet
   only ever used the Garden `\\...\web` share transiently (to pull `zqm-bootstrap.ps1`), never persisted it.
2. **No IP fallback.** Code/handlers that hard-code one Garden IP (e.g. `\\192.168.1.173\web`) go dark
   the instant that one IP is unreachable — even though every cluster has 3–5 member IPs to fail across.
3. **Garden-04 has NO DSM.** TerraMaster units (.144/.147) expose SMB(445)+SSH(22) but port 5000 is CLOSED.
   Any tool that assumes a DSM REST API silently breaks for that cluster → make code protocol-aware.
4. **WinRM is single-cred + TrustedHosts.** Node-4's `zqmlocal` password was set differently at bootstrap
   than the fleet cred → mismatch. Reconcile via `Set-LocalUser -Name zqmlocal -Password $sec` or re-bootstrap
   with the fleet password. Don't guess creds.
5. **Node-2 (.21) is a dead single point.** Was OFFLINE (router listed it "Dead"). No recovery path yet.

## The unbreakable pattern (encode this for any Node→Garden link)
Order matters. Resolution before mount; fallback before failure.

1. **Resolve by DNS name first.** All Garden clusters resolve via `.lan` from Node-1:
   `ZQM-Garden-01.lan`→.173, `ZQM-GARDEN-02.lan`→.40, `ZQM-GARDEN-03.lan`→.64, `ZQM-GARDEN-04`→.144.
   DNS/mDNS dying is the realistic failure → fall back to a static member-IP list (the topology file).
2. **Build a fallback chain.** Candidate hosts = [dns_name] + [all cluster member IPs]. Probe SMB(445)
   on each; take the first that answers. DryRun output proved the chain works:
   `ZQM-Garden-01 > 192.168.1.173 > 192.168.1.52 > 192.168.1.53 > 192.168.1.169`.
   Note Garden-04 correctly picked `.147` even though `.144` was listed "primary".
3. **Persist the mount.** `net use Z: \\<live-ip>\web /user:<user> <pw> /persistent:yes`.
   Drop any stale session mount first (`net use Z: /delete /y`).
4. **Self-heal.** Register a Scheduled Task (RunLevel Highest) that re-runs the link module:
   trigger = AtStartup + RepetitionInterval 15min. This repairs mounts after reboot or Garden IP drift.
5. **Always DryRun before Apply.** `-DryRun` reports resolution + plan with NO mounts and NO credential use.
   `net use` has no `-WhatIf`; DryRun is the only safe pre-flight.

## VERIFIED Garden fabric topology (2026-07-12)
- **ZQM-Garden-01** `.173` (primary) + `.52/.53/.169`. SMB+DSM+SSH OPEN. `.52/.53` share MAC
  `90:09:D0:4B:D1:6B` = Synology HA active/passive pair.
- **ZQM-GARDEN-02** `.40` (primary) + `.39/.38/.32/.37`. All SMB+DSM+SSH OPEN.
- **ZQM-GARDEN-03** `.64`. SMB+DSM+SSH OPEN.
- **ZQM-GARDEN-04** `.144` (primary) + `.147`. SMB+SSH OPEN, **DSM/5000 CLOSED** (TerraMaster, no DSM API).
- **Nodes:** Node-1 `.218` (mgmt, this host); Node-2 `.21` DEAD; Node-3 `.46` WinRM OPEN; Node-4 `.215` WinRM OPEN.
- **Garden admin DPAPI cred** present at `C:\zqm\cred\zqm-cred-garden-admin.json` (machine-scope ProtectedData).
- Full machine-readable copy in `templates/zqm-garden-topology.json`. Re-verify with a live probe before trusting.

## PowerShell 5.1 pitfalls (hit live this session — durable for this fleet)
- **NO ternary operator.** `($x) ? 'a' : 'b'` is a PARSE ERROR on PS 5.1. Use `if (...) {..} else {..}`.
- **Nested quotes in `cmd.exe /c "powershell -File ..."` break silently.** Quote-parsing at the cmd layer eats
  the PowerShell args → "Unexpected token" / echoed instead of executed. Fix: copy the .ps1 to `C:\temp\` first,
  then `cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\script.ps1"`. (Also avoids the
  `-File \\network\path` "does not exist" trap when a remote node can't resolve the share name.)
- **WinRM `0x8009030e` "logon session does not exist"** = missing explicit credential, NOT a connectivity failure.
  Supply `-Credential` (workgroup = explicit user, not Kerberos). The TCP port being OPEN does not mean auth works.
- **`Resolve-DnsName`** works for `.lan` names from Node-1; wrap in try/catch and fall back to static IPs.

## Two-door scope framing (user's "unbreakable" request)
- **Door A — Resilient Garden Link (build now, low risk):** the module + topology above. Persistent, self-healing,
  name-resolved, multi-IP-fallback mounts on every Node. Deployable from Node-1 immediately (have the garden cred);
  replicate topology+cred to Node-3/4.
- **Door B — Full fleet fabric + failover (gated):** add vaulted WinRM fleet remoting Node-1→all nodes with SSH
  fallback, DSM→SSH Garden failover (proven earlier), and a Node-2 power-on/recovery procedure. REQUIRES the user to
  reconcile Node-4's `zqmlocal` to the fleet password (or re-run its bootstrap). Do not guess the credential.

## Repro recipe
```
cp /c/zqm/link/zqm-garden-link.ps1 /c/temp/glink.ps1
cp /c/zqm/link/zqm-garden-topology.json /c/temp/gtopo.json
# safe pre-flight (no mounts, no cred use):
cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\glink.ps1 -DryRun -TopologyFile C:\temp\gtopo.json"
# real deploy on a Node:
cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\glink.ps1 -Apply -InstallTask"
```
