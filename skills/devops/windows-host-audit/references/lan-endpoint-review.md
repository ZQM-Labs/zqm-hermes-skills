# LAN endpoint review — fast probe + per-port risk + node grade

## The efficient-probe technique (why it exists)
A "full read-only endpoint review" of a fleet node where an earlier heavier
probe **timed out**. The fix: a **curated port list** + short per-port connect
timeout **instead of** a full-range scan or slow banner-grab. Pure-python
`socket` connect (no nmap). N4 (16 ports) scanned in ~5s at 0.4s/port.

Reusable script: `scripts/lan_port_probe.py` (run from agent host against LAN
target; does the Ollama :11434 check AND a Redis :6379 unauth check, then emits
a NODE GRADE). Default port set is tuned for the ZQM homelab node class —
extend per node.

Key efficiency rules:
- Scan a SHORT curated list, never 1-65535, when the goal is "enumerate open
  ports + confirm a known service."
- 0.4s connect timeout is enough for LAN (sub-ms RTT); raise only for flaky WAN.
- One HTTP GET to Ollama `/api/tags` both confirms LAN exposure AND enumerates
  models in a single request (no auth observed = finding in itself).
- One RESP `PING` to Redis :6379 with NO AUTH → `+PONG` = CRITICAL RCE
  primitive (CONFIG SET / module load / cron write). `-NOAUTH` → auth on (MED).
- Read-only: just TCP SYN + one Redis PING + one HTTP GET. No payloads, no mutations.

## Per-port risk table (ZQM node class, LAN vantage)
Assign per open port. This is the matrix used for N4 — copy/adapt.

| Port | Service | Exposure | Risk |
|------|---------|----------|------|
| 22 | SSH | LAN | MED — remote shell; verify key-only auth, no pw/root |
| 135 | MS-RPC | LAN | MED-HIGH — RPC/WMI recon surface |
| 139 | NetBIOS | LAN | MED — legacy SMB over NetBIOS |
| 445 | SMB | LAN | HIGH — file sharing; EternalBlue-class surface |
| 5040 | WinNAT | LAN | LOW — usually internal |
| 5357 | WSDAPI | LAN | MED — device-discovery, info disclosure |
| 5985 | WinRM-HTTP | LAN | MED-HIGH — UNENCRYPTED remote mgmt |
| 5986 | WinRM-HTTPS | LAN | MED — encrypted remote mgmt (preferred) |
| 11434 | Ollama | LAN-exposed | HIGH — unauthenticated model API |

Closed-but-worth-noting for this class: 3389 (RDP), 4001 (LiteLLM),
8400 (ZBit-Agent), 18789 (OpenClaw-MESH) — these bind
loopback-by-design (see firewall-audit.md §2d); a remote CLOSED is the
**expected** state, NOT a finding.

**CORRECTION (2026-07-11, live evidence — do NOT over-generalize "loopback-only"):**
Redis :6379 is NOT reliably loopback-bound across the fleet. Node-2
(192.168.1.21) had **:6379 LAN-OPEN and FULLY unauthenticated** — a raw
`PING` returned `+PONG` with NO `AUTH`. This is a CRITICAL RCE primitive and
caps the node grade at E/F on its own. ALWAYS probe :6379 explicitly with a
RESP `PING` (see `lan_port_probe.py` `redis_unauth()`); never assume it is
closed. If a node shows :6379 OPEN, escalate to CRIT immediately and recommend
`requirepass`/ACL + loopback bind or firewall.

## Node grade rubric (endpoint-review deliverable)
Aggregate the per-port risks into a single letter-grade. Three exposure
dimensions drive the grade:

- **Unauthenticated RCE-capable service:** Redis :6379 answering `PING`→`+PONG`
  unauthenticated (seen OPEN on Node-2 .21) — this alone is E/F.
- **Unauthenticated LAN service:** Ollama :11434 (public `/api/tags`, model
  theft / compute-abuse) and SMB :445 are the two biggest.
- **Open admin/management planes:** SSH, WinRM (5985 plaintext + 5986 TLS),
  RPC, NetBIOS — all reachable from LAN with no segmentation noted.

Grade bands (LAN-only vantage unless a WAN test was run):
- **A (LOW):** only loopback-bound AI services open; host mgmt ports closed or
  firewall-scoped to a mgmt VLAN; no unauthenticated service.
- **B (MODERATE):** SSH + WinRM open but key-only / TLS, no unauth service.
- **C (ELEVATED):** SMB or one unauth service open; mgmt ports open but
  plausibly segmented.
- **D (HIGH):** Ollama fully unauthenticated on LAN AND/OR SMB open AND
  multiple remote-mgmt ports open with no apparent isolation. (N4 = D.)
- **E (CRITICAL) / F:** any unauthenticated RCE-capable service (e.g. Redis
  :6379 unauthenticated — Node-2 = F), or WAN-exposed unauthenticated service.

N4 (2026-07-11) result: **D (HIGH RISK)** — Ollama unauthenticated on LAN +
SMB + SSH/WinRM/RPC/NetBIOS all open with no segmentation observed; 9 open
ports, 45 Ollama models reachable unauthenticated.

Node-2 (2026-07-11) result: **F (CRITICAL)** — Redis :6379 LAN-OPEN and
unauthenticated (`PING`→`+PONG` no AUTH) + SMB (445) + WinRM (5985) + Ollama
(11434, unauthenticated) open. Unauth Redis alone caps the grade at F.

## Remediation to recommend (out of scope to apply)
- **Bind Redis to loopback + set `requirepass`/ACL; firewall 6379 (Node-2 was
  unauthenticated — treat as P0).**
- Bind Ollama to loopback + reverse proxy with auth; firewall 11434 to mgmt.
- Firewall SMB/WinRM to a mgmt VLAN; prefer 5986 over 5985.
- Enforce key-only SSH; verify no root/pw auth.
- (LAN-only findings: do NOT claim WAN exposure without a separate test.)
