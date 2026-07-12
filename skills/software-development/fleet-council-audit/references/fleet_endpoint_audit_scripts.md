# Reusable fleet endpoint audit scripts (ZQM, 2026-07-11 session)

All scripts are read-only recon EXCEPT `n2_redis_fix.ps1` (a staged remediation that
requires a credential and supports `-WhatIf`). Paths below are where they lived this
session under `C:\Users\zqmco\swarm\fleet_endpoint_review\`.

## Scripts
- **fleet_port_probe.py** — fast bounded TCP port probe (0.4s/port) across the ZQM
  service map (22/135/139/445/2179/3389/5040/5357/5985/5986/47001/11434/4001/8400/6379/
  18789). Used by parallel leaves for per-node sweep.
- **n2_redis_fix.ps1** — STAGED remediation for the N2 Redis CRITICAL. Sets `bind
  127.0.0.1` + `requirepass <pass>` in redis.windows.conf, adds Windows Firewall rule
  "Block-Redis-LAN" (deny tcp/6379 from 192.168.1.0/24), restarts the Redis service,
  self-verifies loopback PONG. Params: `-RedisPass <str>` (mandatory), `-WhatIf`.
  Run ON N2 via WinRM from N1 (N2 has no SSH; WinRM 5985/5986 open + N2 in N1
  TrustedHosts). DO NOT "fix via the unauth channel" — that is the RCE.
- **diagnostics.py** — the "diagnostics" verb: re-probes each flagged finding + hunts
  active ESTABLISHED sessions on exposed ports, separates active vs config-level.
- **hash_genesis.py** — the "hash claims" + "genesis" verbs: hashes claims to SQLite
  (claim_hash table) and writes the by-design/accidental root-cause split (genesis table).
- **consolidate_fleet.py** — merges LEAD (N1) + leaf (N2/N3/N4) results into one ledger
  with node grades, endpoint risk rollup, and fleet-critical findings.

## SQLite schema (fleet_endpoint_audit.db)
```
nodes(node,ip,os,grade,lan_exposed_critical,notes,reviewed)
endpoints(id,node,port,svc,bind,exposure,risk,verified,notes)
findings(id,severity,node,port,svc,finding,evidence,reverify)
remediations(id,target,issue,vector,status,evidence,blocker,decided)
claim_hash(id,claim,status,evidence,sha256,reverify)
genesis(id,finding,root_cause,by_design,evidence,confidence)
meta(k,v)
```
- Severity vocabulary: CRITICAL (pre-auth RCE, e.g. unauth Redis) > HIGH (LAN-exposed
  unauth service, e.g. Ollama) > MED > LOW.
- Node grades seen: N1 MEDIUM-HIGH, N2 CRITICAL(F), N3 HIGH, N4 HIGH.

## Key evidence (verified this session)
- N2:6379 → `PING` returns `+PONG` with NO AUTH (CRITICAL, RCE primitive).
- N1/N2/N4 :11434 Ollama → LAN-exposed, no auth (HIGH); N3 :11434 → closed on LAN
  (localhost-bound, good).
- ZBit stack (PID 1908 :8400, 19120 :4001) → loopback-only, no egress → NOT C2.
- N2 Redis genesis = ACCIDENTAL (default drift); Ollama LAN = BY-DESIGN (ZBit fleet fabric).
- DNS omnimap: 255 ccTLDs (exact, IANA), 10/12 root operators US-HQ, US-gov-control
  post-2016 = FALSE, DNSSEC end-to-end ~0.6%.
