# Hermes `sessions` table schema (state.db)

The authoritative session store is SQLite, not the `session_search` tool.
The tool's BROWSE shape returns only the 10 most-recent rows and its FTS5
DISCOVERY shape demotes `source:"cron"` — so neither can produce a full
census. Read the store directly instead.

## Location
- Default profile: `~/.hermes/state.db`
  (Windows: `C:\Users\<user>\AppData\Local\hermes\state.db`)
- Other profiles: `~/.hermes/profiles/<name>/state.db`
- Open read-only: `sqlite3.connect(path)` (no write lock needed).

## Relevant columns (of `sessions`)
| column          | type    | notes                                       |
|-----------------|---------|---------------------------------------------|
| id              | TEXT PK | `cron_<hex>_<timestamp>` or `YYYYMMDD_HHMMSS_<hex>` |
| source          | TEXT    | `cli` \| `cron` \| `subagent` \| `tool`     |
| title           | TEXT    | free text; cron titles look like `Job Name · Jul 12 11:36` |
| model           | TEXT    | e.g. `tencent/hy3:free`, `stepfun/step-3.7-flash:free` |
| started_at      | REAL    | unix epoch (seconds) — sort on this        |
| last_active     | REAL    | unix epoch (may be absent on some rows)     |
| message_count   | INTEGER | size of the transcript                      |
| parent_session_id | TEXT  | set on subagent/child rows; NULL on roots   |

## Census query (the only reliable count)
```sql
SELECT id, title, source, model, started_at, message_count
FROM sessions
ORDER BY started_at ASC;
```

## Classifying the four sources
- `cli`      → the real interactive "chat histories". This is what the user
               means by "sessions" unless they asked for cron jobs.
- `cron`     → automated runs. They are NOISE as individual rows. Recover
               DISTINCT jobs by grouping on the text before the `·` in
               `title` (or by the `cron_<hex>_` id prefix):
               ```python
               key = (title or "alpha").split("·")[0].strip() or "alpha"
               ```
- `subagent` → delegated children of a parent cli/cron run. Report COUNT
               + date span; do NOT enumerate each one.
- `tool`     → integration plumbing; usually ignore.

## Drill-down (transcripts of ONE session)
Use `session_search` scroll/bookend ONLY here, on a `session_id` you already
got from the store. The tool is a viewer, not a census tool.
