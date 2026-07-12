# Empirical proof: session_search blind spot (measured 2026-07-12)

This skill exists because `session_search` repeatedly under-counted the session
store. Below are the LIVE measurements that justify going to `state.db` directly.

## Method
Ran `session_search` with no query (browse) and with single-term queries
(`Garden`, `bounty`, `node`), and compared against a direct read of `state.db`.
Also inspected the SQLite schema to confirm whether the FTS5 index itself was
broken or merely mis-ranked.

## Measurements (state.db read-only)
- Total store = **310 records** (live, drifts up as cron fires):
  cli=71, cron=178, subagent=60, tool=1. Bucket sum == total.
- Index artifact on disk reported cli=71, matching live.
- Prior "complete" answers: agent said **12**, then **16**. Real = 71.
  Undercount = **5.9x** then **4.4x**.

## session_search output (the defect)
- Browse (no query): returned **exactly 3** sessions; all 3 were cron
  (`ZQM fleet diagnostics + drift watch`). Interactive visible = **0/71** (100% hidden).
- Discovery (`query=`): hard cap of **3 results per call** for `Garden`,
  `bounty`, AND `node`. Example: `node` returned 2 cron sessions + 1 cli.
- Last-N by start time: in a 10-session window only **1 of 71** interactive
  sessions qualified (99% hidden).

## Is the FTS5 index broken? NO.
- `messages_fts` = **150,668 rows**, fully populated; trigram variant present;
  live insert/update/delete triggers. The index is complete.
- Corpus composition by message volume: cli 147,846 (98.1%), subagent 1,815
  (1.2%), cron 1,009 (0.7%). Avg msgs/session: cli 2,143 vs cron 5.7.
- **Defect is PRESENTATION, not indexing**: both modes cap output at 3 results,
  and discovery ranks by per-session BM25. Recurring cron jobs repeat
  "node"/"garden"/"bounty" dozens of times per run, so they out-rank an
  interactive chat that mentions the term once and dominate the top-3.

## Conclusion
The tool can present at most 3 sessions per call and ranks cron-heavy. Full
enumeration (71 interactive chats) is IMPOSSIBLE through it. Only direct SQL
(`SELECT … FROM sessions ORDER BY started_at`) produces a true census.

## Earlier wrong claims, corrected
- "Browse caps at 10" → **false on this host; verified cap is 3.**
- "FTS5 demotes / is recall-blind / broken" → **false; index is complete.**
  The real defect is the 3-result cap + per-session BM25 over a cron-heavy corpus.
