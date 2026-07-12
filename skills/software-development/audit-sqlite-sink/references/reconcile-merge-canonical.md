# Reconcile Option A — Merge / Promote stray into canonical (cron-safe)

When the reconcile decision is A (NOT archive-the-stray): keep the EXISTING fragment DB in
place as the single ledger and IMPORT the stray's complete data into it. Use this when the
fragment carries UNIQUE tables a running monitor depends on (e.g. a live cron reads its
`claim_hash` table) AND the stray carries the complete / intact claim chain the fragment lacks.

## Pre-flight (MANDATORY before any move)
1. Enumerate EVERY `*.db` under the project root (search_files target=files). There may be
   more than two. This session found SIX: 5 empty scaffolds + 1 complete stray + 1 fragment.
2. For each, read `PRAGMA table_info(<t>)` + row COUNT to classify: EMPTY scaffold
   (0 claims / 0 findings), COMPLETE (intact chain), or FRAGMENT (unique tables).
3. CRON-SAFETY CHECK: grep the monitoring scripts for hard-coded DB paths (`DB =`,
   `sqlite3.connect(`). If a running cron reads the fragment file (e.g. hash_drift_check.py
   hard-codes `DB = .../fleet_endpoint_audit.db` and reads its `claim_hash` table), you MUST
   NOT delete/rename/move that file or the monitor breaks. Keep it in place.
4. Diff `findings` columns between fragment and stray. If they DIFFER (fragment:
   severity/node/port/svc/finding/evidence/reverify; stray: fid/title/severity/status/evidence),
   a blind `INSERT INTO findings` corrupts rows — import the stray's findings into a SEPARATE
   table `swarm_findings`, keep fragment's `findings` as-is.

## Merge recipe (verified 2026-07-12)
- Fragment = `fleet_endpoint_review/fleet_endpoint_audit.db` (authoritative target, kept in place)
- Stray    = `zbit-litellm-20260711/fleet_swarm.db` (68 findings, 68 claim_hashes, chain INTACT)
Steps:
1. `CREATE TABLE IF NOT EXISTS claim_hashes(fid,claim_hash,prev_hash,chain_root,generated)`
   in fragment; INSERT the stray's 68 rows (idempotent: skip fids already present).
2. `CREATE TABLE IF NOT EXISTS swarm_findings(fid,title,severity,status,evidence)`;
   INSERT stray's 68 findings.
3. `CREATE TABLE IF NOT EXISTS open_questions(qid,question,status,resolution)`;
   INSERT stray's 27.
4. `CREATE TABLE IF NOT EXISTS meta(k,v)`; write keys: canonical_db, authoritative_source,
   reconcile_decision=Option A, merged_tables, fragment_unique_retained, cron_safety,
   empty_siblings_archived, merged_at.
5. VERIFY: chain still INTACT (walk claim_hashes, each prev_hash == previous claim_hash; a
   single chain_root), count tables, confirm the cron's `claim_hash` table is untouched.
6. Archive EMPTY sibling scaffolds via mv to `<root>/archive/`. If `shutil.move` fails with
   WinError 32 (file locked by the running cron or AV), that is SAFE TO LEAVE — confirm 0 rows
   via sqlite COUNT first; they are inert duplicates. Do NOT retry in a tight loop; note the lock.

## Verified end-state (this session)
tables: 18 | claim_hashes: 68 (INTACT, 1 root) | swarm_findings: 68 |
open_questions: 27 | findings: 10 (fragment's own) | claim_hash: 16 (cron target, untouched) |
hash_drift_log: 78 | meta: 18.
Net: a six-way split collapsed to ONE canonical ledger, chain integrity proven, monitor unharmed.

## Running the merge script on this Windows host
- Terminal calls are independent shells: do NOT export `$PY` across calls.
- Write the merge .py to %TEMP% with a `hermes-*.py` prefix, then run with the absolute
  interpreter: `"C:/Users/zqmco/AppData/Local/Programs/Python/Python312/python.exe" hermes-merge-audit.py`.
- Avoid `cmd.exe /c` wrapping of heredocs — it mangles quoting. Delete the temp script after.
