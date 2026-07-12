---
name: session-history-enumeration
description: >-
  Thorough, COMPLETE enumeration of Hermes session histories when the user
  asks for "all sessions", "full history", "enumerate session histories", or
  "what did we work on". Covers the FTS5 single-term search quirk, the
  cron-job blind spot, and the completeness-verification loop that stops a
  false "done". Use when asked to list/review past sessions, audit scope
  across sessions, or reconcile what was done.
---

# Session History Enumeration

## When
The user asks for the full set of past sessions — e.g. "full enumeration of
session histories", "review all previous conversations", "what sessions exist".
Treat the request as a COMPREHENSIVENESS audit, not a quick list.

## Why this needs a skill
A single `session_search` sweep almost always UNDER-counts, and worse, the
tool's own shapes lie about completeness. On 2026-07-12 an agent reported
"12 sessions, complete" then "16, complete" — both wrong by ~20x. The real
store held **307 records**: 71 interactive CLI chats, 175 cron-job runs
(8 distinct recurring jobs), 60 delegated subagents, 1 tool session. The
miss happened because the agent trusted `session_search` (its BROWSE shape
caps at 10 most-recent rows; its DISCOVERY/FIS5 shape demotes `source:"cron"`
so cron runs either bury or starve the interactive hits; and multi-term
queries return 0). `session_search` is a *sample*, never a *census*. The
only authoritative count comes from the SQLite store on disk. This skill
enforces reading the store directly, not trusting the tool.

## Steps
1. **Frame it as hypothesis, not fact.** "Done" / "complete" is a claim to
   verify, like any other. Do not assert completeness until you have read
   the store directly (step 4) and confirmed the `cli` count.
2. **FTS5 quirk (DRILL-DOWN ONLY, not for counting).** If you must use
   `session_search` to find a *specific* missed topic (e.g. "did we ever
   discuss TerraMaster?"), note it is FTS5-backed: multi-term Boolean
   phrases return 0 and look like "nothing found". Use LOOSE SINGLE TERMS
   only (`autostart`, `UAC`, `ZQM`, `bounty`, `rebrand`, `fleet`,
   `Quantum-Automation`, `hash claims`). But remember: this only finds
   *interactive* sessions that match, never a true count, and never
   recovers cron runs you didn't already know about. Prefer the store read.
3. **Sweep broadly (only if using the tool for drill-down).** Run 8-15
   single-term queries covering entity/project names, known dates, and
   distinctive tokens; union the `session_id`s.
4. **DO NOT TRUST THE TOOL FOR A CENSUS — read the store directly.**
   `session_search` BROWSE caps at the **10 most-recent** rows, and FTS5
   DISCOVERY **demotes `source:"cron"`** (so cron runs either bury or
   starve the interactive hits). A `session_search(query="", sort="oldest")`
   call does NOT return every session — it returns 10 rows. Treat any
   `session_search` result as a *sample*, never a count. The authoritative
   store is SQLite. Read it directly (Python, read-only):
   ```python
   import sqlite3
   DB = r"C:\Users\zqmco\AppData\Local\hermes\state.db"   # default profile
   c = sqlite3.connect(DB)
   rows = c.execute("""SELECT id,title,source,model,started_at,message_count
                        FROM sessions ORDER BY started_at ASC""").fetchall()
   # source ∈ {cli, cron, subagent, tool}; group cron by title prefix for jobs
   ```
   This is the ONLY way to get a true total. Default profile lives at
   `~/.hermes/state.db` (i.e. `C:\Users\<user>\AppData\Local\hermes\state.db`);
   other profiles live under `~/.hermes/profiles/<name>/state.db`. A ready
   enumerator that prints the full index + per-source counts + distinct cron
   jobs is shipped as `scripts/enumerate_sessions.py` — run it instead of
   hand-rolling. Use `session_search` only to DRILL INTO a specific session's
   transcripts (bookends/scroll), not to count.
5. **Classify by source, then deliver the interactive chats.** The store
   mixes four sources in one table:
   - `cli`      = the real "chat histories" (this is what the user means by
                 "sessions" unless they said "cron jobs").
   - `cron`     = automated watchdog/monitor runs. GROUP BY the text before
                 the `·` in `title` (or by the `cron_<hex>_` id prefix) to
                 recover DISTINCT recurring jobs — individual runs are noise.
   - `subagent` = delegated children of a parent cli/cron run; not standalone
                 chats. Report their COUNT and span, don't enumerate each.
   - `tool`     = integration plumbing; usually ignorable.
   Deliver the `cli` set chronologically (date → session_id → one-line topic
   → relevance). Separately list the distinct cron jobs (count of runs each).
6. **Catch the cron blind spot via the store, not the tool.** Because you
   now read `state.db`, cron runs are already in the full row set — just
   don't let 175 cron rows visually drown the 71 cli rows. Filter
   `WHERE source='cli'` for the chat index; report cron as aggregate.
7. **Deliver chronologically:** `cli` sessions by date → `session_id` →
   one-line topic → relevance to the current ask (e.g. post-restart loose
   ends). Separately list distinct cron jobs (run-count each) and the
   subagent count+span. REDACT any credentials/tokens seen in history as
   `[REDACTED]` — never preserve them.
8. **Open vs done.** Flag unresolved items separately from completed work.
   Do NOT re-surface stale "remaining work" from compacted summaries
   unless the user re-asks; the latest message wins (context-compaction
   rule).

## Pitfalls
- **Trusting `session_search` for a count.** BROWSE = 10 most-recent rows;
  FTS5 DISCOVERY demotes cron and needs loose single terms. It is a *sample*.
  Read `state.db` (step 4) for the census. The 2026-07-12 "12 then 16 sessions"
  failure came from trusting the tool's shaped output as a complete count.
- Asserting "enumeration complete" before reading the store. The store IS
  the completeness check — if you didn't `SELECT … FROM sessions`, you
  haven't verified completeness, period.
- Multi-term query returning 0 → don't conclude "nothing"; switch to
  single terms (only relevant when DRILLING for a missed topic via the tool).
- Forgetting `source:"cron"` / `source:"subagent"` rows in the store — filter
  `WHERE source='cli'` for the chat index, report cron/subagent as aggregates.
- Trusting a compacted summary over a fresh store read; the latest message
  wins (context-compaction rule) but the session LIST must come from disk.

## Support files
- `scripts/enumerate_sessions.py` — reads `state.db` read-only, prints the
  full chronological session index grouped by source, per-source counts, and
  distinct recurring cron jobs (grouped by title prefix). Run this INSTEAD of
  `session_search` for any "how many / which sessions" question.
- `references/state_db_schema.md` — the `sessions` table columns + the
  cron/subagent grouping recipe, so future agents can write their own queries
  without re-deriving the schema.

## When the user wants TRANSCRIPTS of a specific session
THEN (and only then) use `session_search` scroll/bookend on the `session_id`
from the store. The tool is a drill-down viewer, not a census tool.
