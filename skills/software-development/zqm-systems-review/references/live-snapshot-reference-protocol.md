# Live Snapshot Reference Protocol

Use this when asked for a “full dynamic reference”, exhaustive enumeration, or canonical audit across multiple live stores.

## Source of truth

- Enumerate directly from canonical stores: SQLite databases, message tables, session tables, filesystem scans.
- Do not rely on FTS-backed search tools or limited-window browse APIs for completeness claims; they are subset views.

## Build protocol

1. Read counts first:
   - sessions
   - messages
   - role breakdown
   - source breakdown
2. Pull raw rows from all relevant stores.
3. Deduplicate across stores by stable identifier. Prefer the row with the highest evidence count.
4. Enrich with exact counts from message tables. Use role-filtered queries for user/assistant/tool splits.
5. Store build-time anchors inside the produced artifact.

## Verification protocol

- The artifact is a timestamped snapshot, not a live mirror.
- After build, exact count equality with source-of-truth stores is expected only if the stores are quiescent.
- Post-build writes by cron/messaging will make live DB counts diverge from the snapshot; that drift does not invalidate the snapshot.
- Validator logic:
  - Accept artifact when required JSON schema fields exist.
  - Accept artifact when `snapshot_note` is present and documents live-DB drift.
  - Accept artifact when build-time anchors are present in `stores` and are internally consistent with the session array.
  - Do not reject solely because live DB counts differ from snapshot counts after build time.
- On mismatch:
  - If the artifact anchors exactly match the DB at build time, treat the artifact as valid for that instant.
  - If the anchors themselves do not match expected pre-build values, rebuild the artifact.

## Persisted artifact naming

- C:\Users\zqmco\AppData\Local\hermes\outputs\session_systems_full_reference.json

## Runtime failure pattern

A common drift pattern is placeholder/duplicate logic appearing mid-build because the same field is read inconsistently across stores. Always count from message tables for session message counts. Never backfill verifier expectations from midpoint aggregate fields.
