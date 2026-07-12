# ZQM fleet — topology corrections (verified 2026-07-11)

Durable, council-verified facts about the ZQM homelab so future audits don't re-derive them.

## Host role correction (BREAKING for prior assumptions)
- "Gateway G1" `192.168.1.173` and "Gateway G2" `192.168.1.40` are NOT routers and NOT
  Home Assistant. They are **Synology DSM 7.x appliances** (hostnames `ZQM-Garden-01` /
  `ZQM-GARDEN-02`). `:5000` = DSM HTTP->HTTPS redirect stub; `:5001` = DSM login (webman UI).
  `:80/:443` = Synology Web Station default page. So G1/G2 are storage appliances, mislabeled
  "gateway" in older memory/notes.
- There is **NO Home Assistant** anywhere on the fleet — `:8123` is closed on all 7 hosts. The
  `homeassistant` toolset / `HASS_TOKEN` plan has no HA host to target. Drop it or point it
  elsewhere.
- "Synology NAS" `192.168.1.53` is the primary DSM (same `ZQM-Garden-01` hostname string as G1;
  carries `:873` rsync that G1 does not).

## OpenClaw mesh
- `:18789` (OpenClaw agent mesh) is CLOSED on every host in the fleet — the mesh is down
  fleet-wide, not just Node-1. Don't report it as a Node-1-only issue.

## Redis (Node-2) — confirmed critical
- `192.168.1.21:6379` = Redis 3.0.504 on Windows, **unauthenticated**, empty `bind`,
  `dir=C:\Program Files\Redis`. Live RCE primitive. Fix gated on Node-2 WinRM break-glass pw.

## Port inventory (full connect-scan + protocol-verified, all 7 UP — 2026-07-11 re-verified)
- Node-1 .218  : 22,135,139,445,5985,5986,11434
- Node-2 .21   : 135,139,445,5985,5986,6379,11434   (no SSH)
- Node-3 .46   : 445  (minimal)
- Node-4 .215  : 22,135,139,445,5985,5986,11434  (11435 was CLOSED on a later re-probe — 2nd Ollama instance intermittent/restarted; re-check before relying on it)
- G1 .173      : 21,22,23,53,80,111,139,161,443,445,662,873,892,2049,5000,5001,7000
- G2 .40       : 21,22,23,53,80,111,139,443,445,548,662,873,892,2049,5000,5001
- NAS .53      : 21,22,23,53,80,111,139,161,443,445,662,873,892,2049,5000,5001,7000

## Gotcha this corrected (RE-VERSED 2026-07-11)
- Earlier note claimed a lead `connect()` sweep reporting `:23 Telnet OPEN` on G1/G2/NAS was a FALSE POSITIVE (scanner-host reset) and that a council handshake "proved NO :23". That was WRONG. A later lead re-probe with a real telnet IAC negotiation (`\xff\xfb\x01` → `\xff\xfb%...` reply) + an FTP `220 ZQM-Garden-01 FTP server ready.` banner PROVED `:23` AND `:21` ARE real on the Synology units, plus `:111` rpcbind, `:2049` NFS, `:892` nfs-rquotad, `:548` AFP (G2), `:7000`. The council handshake was the false-negative. LESSON for future audits: confirm a surprising port with a STRONGER method (banner/IAC/handshake), and do NOT trust a council "absent" claim over a lead connect() hit without your own stronger verification.
- Node-4 `:11435` is intermittent — do not treat it as always-up.
