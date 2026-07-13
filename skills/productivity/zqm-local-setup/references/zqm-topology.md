# ZQM LAN Topology (verified 2026-07-12 via router device table + ICMP/TCP/SSH probes)

NOTE: IPs are NON-sequential. Do not guess .21/.22/.23/.24 — resolve `<name>.lan` and probe.
Router = SAX1V1K (ASKEY, Spectrum/Charter) at 192.168.1.1.

## Compute / fleet nodes
| Name              | IP             | HW / OUI            | State (2026-07-12)                                                                 |
|-------------------|----------------|---------------------|------------------------------------------------------------------------------------|
| Node-1 (self)     | 192.168.1.218  | 08:9D:F4 (host)     | Hermes agent host; fed-indexer :5000 LIVE; Ollama/SearXNG/AnythingLLM running.     |
| Node-2            | 192.168.1.21   | E8:65:38 (generic)  | ON but NO open ports (no 22/80/445/5985). Untouchable — cannot host a peer.        |
| Node-3            | 192.168.1.46   | Intel 8C:17:59      | **LIVE FEDERATION PEER** (fleet_nodes=1). SSH✓ as zqmlocal; embedded Py at C:\py312. |
| Node-4            | 192.168.1.215  | Intel F0:D4:15      | Ollama LIVE; SSH✗ + WinRM✗ as zqmlocal (auth gate). Needs local Set-LocalUser.     |
| xyo-bridge (RPi)  | 192.168.1.164  | RPi B8:27:EB        | :22 OPEN. **NEXT VIABLE PEER** — SSH login unknown (not node-local/garden-admin).  |

## ZQM-Gardens (NAS — staging drop only, NOT peer hosts)
| Name      | IP(s)                              | HW              | DSM (5000/5001) | SMB write from Node-1        |
|-----------|------------------------------------|-----------------|-----------------|-------------------------------|
| Garden-01 | 192.168.1.52 /.53 /.169 /.173      | Synology        | OPEN            | denied (per-IP allowlist)     |
| Garden-02 | 192.168.1.32 /.37 /.38 /.39 /.40   | Synology        | OPEN            | WRITE-OK via .40 `web` (cached)|
| Garden-03 | 192.168.1.64                       | Synology        | OPEN            | denied                        |
| Garden-04 | 192.168.1.144 /.147 /.185 /.186    | TerraMaster/Noon| CLOSED          | denied                        |

All Gardens: SSH(22)/HTTP(80)/HTTPS(443) OPEN as `azelenski`.
Garden-02 .40 `web` share is the reliable fleet staging drop point (files staged there this session).

## Network infra
- Router: 192.168.1.1 (SAX1V1K / ASKEY) — :80/:443.
- Mesh: decoMeshW3000 .187 (Deco, TP-Link E0:D3:62); B0210 satellites .83/.224/.228; Linksys APs .124/.143.

## Clients / IoT (not peer hosts)
- Roku: .69 .88 .200 | Pixel-9-Pro-XL: .77 | Nest Mini: .82 (dead twin .172)
- Generic: .9 .6 .79 .54 .252 .220 .210 .170 .142 .123 .110

## DEAD (router-confirmed offline)
- 192.168.1.20 (S124FNTF23026628), .90 (BILIAN), .91 (HPI4DF291), .172 (Google-Nest-Mini)

## Fleet federation status (2026-07-12)
- Aggregator: Node-1 (.218) — /api/federate LIVE.
- Peers: Node-3 (.46) live (fleet_nodes=1). Node-4 gated. xyo-bridge (.164) pending SSH cred.
- Staging channel: Garden-02 .40 `web` (SSH as azelenski; SMB blocked from Node-1 by allowlist).
