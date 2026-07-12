# Working files — claim-attestation service (C:\Users\zqmco\swarm\)

## Endpoint map (api_server.py, port 8088, loopback)
  GET /                     banner + endpoint list
  GET /attest               full live attestation JSON (31 claims + chain + probes)
  GET /attest/summary       {claim_count, tally, chain_root, audit_db_chain}
  GET /attest/claim/<ID>    single claim, e.g. /attest/claim/B4
  GET /attest/chain         hash chain array
  GET /attest/probes        raw live probe values
  GET /audit/chain          read-only re-walk of fleet_endpoint_audit.db claim_hashes
  GET /sitrep               full SA: nodes + audit ledger + session store + gaps
  GET /nodes                live fleet node/port reachability matrix

## Probe inventory (gather_probes in claims_core.py)
  curl http_code :8400/:4001/:11434 on N1(.218), N2(.21), N3(.46), N4(.215)
  redis-cli -h N2 PING
  powershell Get-ScheduledTask (ZQM|Stack|Autostart) + Get-Service sshd
  sqlite3 ro: state.db sessions (cli/cron/sub/tool/parent counts)
  sqlite3 ro: fleet_endpoint_audit.db (open_questions, reliability_applied, remediations)

## Live fleet state captured 2026-07-12 (reference; will drift)
  N1 reachable, Ollama 11434=200; N2 reachable (Redis AUTH_REQ); N3 NOT reachable;
  N4 reachable, Ollama 11434=200, 45 models, LAN-OPEN.
  audit: open_questions 27 total / 20 OPEN; claim_hashes chain valid (68 rows,
  root dbd8bc730fa9348367005a1e5306d80cbe9691e0cd56598f637e16915bca34eb).
  session_store: ~315 total (cli 72, cron 182, sub 60, tool 1, nested 60).

## Restart recipe (netstat-anchored)
  taskkill /PID <netstat-PID> /F
  rm -rf C:\Users\zqmco\swarm\__pycache__
  cd C:\Users\zqmco\swarm && python api_server.py --host 127.0.0.1 --port 8088
  netstat -ano | grep :8088   # confirm real listener PID
