# Fleet endpoint review — consolidation schema, tuple-normalize bug, remediation-staging blocker

Companion to the "full endpoint review" verb in SKILL.md. Live 2026-07-11 fleet pass.

## 1. Consolidated SQLite ledger schema (worked)

LEAD merges all leaves + own N1 deep review into ONE db:
`swarm/fleet_endpoint_review/fleet_endpoint_audit.db`

nodes(node TEXT, ip TEXT, os TEXT, grade TEXT,
      lan_exposed_critical TEXT, notes TEXT, reviewed TEXT)
endpoints(id INTEGER, node TEXT, port INTEGER, svc TEXT, bind TEXT,
          exposure TEXT, risk TEXT, verified TEXT, notes TEXT)
findings(id INTEGER, severity TEXT, node TEXT, port INTEGER, svc TEXT,
         finding TEXT, evidence TEXT, reverify TEXT)
meta(k TEXT, v TEXT)

- nodes = one row per fleet node + overall grade + the single biggest critical flag.
- endpoints = every OPEN port across all nodes, with bind + LAN/WAN exposure + risk (CRIT/HIGH/MED/LOW/MED-HIGH).
- findings = severity-ranked (CRITICAL first), each with verbatim evidence.
- meta = node count, endpoint count, CRITICAL/HIGH counts, review date, method, zbit_stack_C2=FALSE note.

Confirm output: `FLEET LEDGER: ... nodes=4 endpoints=51 CRITICAL=1 HIGH=7` before declaring saved.

## 2. Tuple-shape-normalize bug (cost one failed persist run)

Per-node endpoint tuples were INCONSISTENT:
- N1 rows carried a bind field -> 7-tuple: (port,svc,bind,exp,risk,ver,notes)
- N2/N3/N4 rows OMITTED bind -> 6-tuple: (port,svc,exp,risk,ver,notes)

Naive unpack `for port,svc,bind,exp,risk,ver,notes in eps:` THREW
`ValueError: not enough values to unpack (expected 7, got 6)` on the first N2 row.

FIX - normalize inside the loop:
  if len(row) == 7: port,svc,bind,exp,risk,ver,notes = row
  else: port,svc,exp,risk,ver,notes = row; bind = exp
Same root-cause class as the SQLite RETRACTION / schema-mismatch pitfall: after ANY merge or
field rename, COUNT the CREATE TABLE columns AND the tuple together - a mismatch aborts the whole
executemany batch and silently drops rows after the bad one. Re-verify row counts post-commit.

## 3. Remediation-staging blocker ("do A+C" pattern)

When the user scopes remediation as e.g. "A+C" (apply fix A, leave rest C = report-only):
A (apply fix) that needs a per-node break-glass cred you do NOT have -> STAGE, don't guess.

1. Write the fix as a parameterized, idempotent, -WhatIf-safe script ON DISK, e.g.
   n2_redis_fix.ps1 -RedisPass <pass> [-WhatIf]. It should: set bind 127.0.0.1 + requirepass in
   redis.windows.conf (idempotent -replace); add FW rule Block-Redis-LAN (deny tcp/6379 from
   192.168.1.0/24); Restart-Service Redis -Force; self-verify loopback PING->PONG with the pass.
2. DO NOT fabricate or re-loop a guessed password. Per-node creds DIFFER - N2's pw is NOT the
   rejected 'EllaRose89!'; one retry proving a reject is enough, never re-loop.
3. Confirm the ONLY remote execution path. N2 has SSH :22 CLOSED (filtered) -> only WinRM
   :5985/:5986 OPEN. Script runs ON N2 via Enter-PSSession -ComputerName 192.168.1.21
   -Credential (break-glass) from Node-1. (redis-cli is NOT on Node-1 - post-fix LAN verify uses
   a python socket PING, not redis-cli.)
4. Report status as STAGED + BLOCKED: exact artifact path + what you'll do on receipt of the cred
   - (a) run -WhatIf, (b) run live with real pass, (c) from Node-1 verify LAN PING now fails/NOAUTH
   + loopback still authenticates, (d) update findings N2:6379 -> RESOLVED with evidence.
5. "C" = rest stays report-only; those HIGH findings remain live in the ledger until a separate GO.

Never auto-apply a privileged cross-node change without the credential. Staging + blocking is the
honest, non-fabricating outcome when the cred is missing.

## 4. Reusable probe engine

scripts/fleet_endpoint_probe.py <ip> [ms] - Python socket + settimeout(0.4), returns
OPEN/CLOSED/FILTERED per port from a curated service map. Used by LEAD and handed to leaves.
Do NOT use bash /dev/tcp for the sweep (no connect timeout -> hangs on filtered ports; first
fleet sweep timed out at 180s on Node-4).
