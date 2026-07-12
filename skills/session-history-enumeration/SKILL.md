---
name: session-history-enumeration
description: Reliably enumerate the COMPLETE Hermes session history (every interactive chat, cron run, and delegated subagent) for the current profile. USE whenever asked to "list sessions", "enumerate session history", "review all previous conversations", "how many sessions", or when session_search's browse/discovery returns only a handful of results and you suspect more exist. The native session_search tool hard-caps output at 3 sessions per call (browse AND discovery) and ranks discovery by BM25 over a cron-heavy message corpus, which hides ~95%+ of interactive chats — querying state.db directly is the only trustworthy method.
---

# Session History Enumeration (class-level skill)

## WHY THIS SKILL EXISTS
On 2026-07-12 a fleet operator asked "full enumeration of session histories completed?"
and received the answer "16 sessions" — TWICE. Both were wrong. The real store held
**309 records** (71 interactive chats + 177 cron runs + 60 subagents). The error came
from trusting the `session_search` tool:

- **Browse mode** (`session_search` with no args) returns only the **3 most-recent**
  sessions (verified live: returned 3, all cron). It does NOT surface the user's
  interactive chats unless one happens to be in the literal last 3 by start time.
- **Discovery mode** (FTS5 query) returns a hard cap of **3 results** per call, and
  ranks them by per-session BM25 over the `messages_fts` index. That index is complete
  (150,668 rows, trigram variant present) — the defect is presentation, not indexing.
  Recurring cron jobs (e.g. `ZQM fleet diagnostics + drift watch`) emit the terms
  "node"/"garden"/"bounty" dozens of times per run, so they out-rank an interactive chat
  that mentions a term once and dominate the top-3. A single-term query therefore returns
  mostly cron hits and is capped at 3, making ~68 of 71 interactive chats unreachable.
- **Multi-term Boolean queries** return ZERO results under FTS5 strictness — so
  "post-restart autostart scheduled task" → 0 hits, even when matches exist.

The tool is fine for *drilling into a known session* or *searching content*, but it is
**not** a complete enumeration primitive. For "how many / list all", go to the source.

## THE RELIABLE METHOD — query state.db directly
The session store is a SQLite DB. Profiles each have their own; the default profile lives at:
- Windows: `C:\Users\<user>\AppData\Local\hermes\state.db`
- Linux/macOS: `~/.hermes/state.db`  (or `~/.local/share/hermes/state.db`)

The `sessions` table has columns: id, source, title, model, started_at (unix epoch),
message_count, parent_session_id, cwd, ended_at, end_reason, and many cost/token fields.

Canonical complete enumeration query:
```sql
SELECT id, title, source, model, started_at, message_count
FROM sessions
ORDER BY started_at ASC;
```

Source-class breakdown:
```sql
SELECT source, COUNT(*) FROM sessions GROUP BY source;
-- cli=interactive chats, cron=recurring jobs, subagent=delegated children, tool=automation
```

Distinct cron jobs (collapse the per-run noise):
```sql
SELECT CASE WHEN title='alpha' THEN 'alpha:'||substr(id,1,14)
            ELSE substr(title,1,instr(title,'·')-1) END AS job,
       COUNT(*) AS runs
FROM sessions WHERE source='cron'
GROUP BY job ORDER BY runs DESC;
```

## STEPS (do this, not session_search browse)
1. Resolve the DB path for the active profile (default above; other profiles under
   `~/.hermes/profiles/<name>/state.db`).
2. Run the canonical `SELECT ... ORDER BY started_at` query via a small Python script
   (sqlite3 stdlib; open read-only so you never lock the live store).
3. Split the result into the three meaningful buckets and report counts:
   - **Interactive CLI** = `source='cli'` (the real "chat histories").
   - **Cron runs** = `source='cron'`, then group by job name.
   - **Subagents** = `source='subagent'` (worker children — not standalone chats).
4. Emit the human-readable chronological list (see templates/index_template.md).
5. If the user wants a durable artifact, generate the markdown index with
   references/generate_index.py and write it to their swarm/ or docs dir.

## PITFALLS
- **Never report "complete" from session_search browse/discovery.** Both modes hard-cap at 3 results per call; FTS5 discovery skews to cron. Only state.db counts as ground truth.
- **Do not hand-transcribe** 70+ sessions — generate the index programmatically from
  the DB (references/generate_index.py) so it can't drift.
- **Live store drifts.** Cron runs accrue while you work; totals will creep up between
  queries. Note the generation timestamp in any artifact.
- **Credentials/tokens in titles/summaries**: redact (e.g. HackerOne tokens, pw strings)
  if any surface in titles. The DB titles are usually clean, but verify.
- **Subagents are not chats.** Counting them as "sessions" inflates the number; report
  them separately so the user isn't misled.
- **Other profiles**: if `HERMES_PROFILE` or a profile name is in play, enumerate that
  profile's state.db too, or state you only covered default.

## VERIFICATION
After enumerating, sanity-check:
- `SUM(bucket counts) == SELECT COUNT(*) FROM sessions`.
- The oldest `started_at` matches the user's "first session" recollection.
- A spot-check of 2–3 session IDs via `session_search(session_id=...)` opens the right
  transcript (confirms your DB rows map to real chats).
- To QUANTIFY the blind spot's size (not just list it), compute ground_truth_count /
  interactive_reported and the corpus-weight skew (cron vs cli message volume) — see
  `verification/hash-claims-verification` references/blind-spot-enumeration.md.

## WHEN NOT TO USE
- Searching for *content inside* a session (use session_search discovery with a
  single loose term).
- Drilling into one known session (use session_id + scroll).
- This skill is specifically for COMPLETE, COUNTABLE enumeration.

## TWO-PASS PATTERN (consolidated from prior duplicate)
1. **Census pass (this skill):** always read `state.db` directly for the count +
   chronological list. Never assert "complete" off a tool-shaped sample.
2. **Drill-down pass (session_search, optional):** once you have a `session_id`
   from the census, use `session_search(session_id=...)` scroll/bookend to read
   THAT session's transcript. The tool is a drill-down viewer, not a census tool.
- **Compacted summaries lie about scope.** If a compaction summary says "review
  what we tried / remaining work", do NOT re-surface its stale item list. The
  latest user message wins; the SESSION LIST must come from `state.db` on disk,
  not from recalled summary text.

## CONSOLIDATION NOTE
This skill subsumes the older `verification/session-history-enumeration` (which
incorrectly claimed a "10-row browse cap" and linked a non-existent
`scripts/enumerate_sessions.py`). That duplicate was removed; this top-level
skill is the single source of truth. If both names still resolve, delete the
`verification/` copy.
