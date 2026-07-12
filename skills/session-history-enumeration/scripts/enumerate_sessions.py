#!/usr/bin/env python3
"""
Authoritative Hermes session-store enumerator.

WHY: `session_search` (the tool) is NOT a census. Both its BROWSE shape (no
query) and its DISCOVERY shape (query) hard-cap output at 3 results per call,
and discovery ranks by per-session BM25 over a cron-heavy FTS5 corpus, so it
buries the interactive chats. Any count derived from it is wrong. The real
session store is a SQLite DB on disk. This script reads it read-only and
prints a true full index.

USAGE:
    python enumerate_sessions.py                 # default profile state.db
    python enumerate_sessions.py --profile NAME  # ~/.hermes/profiles/NAME/state.db
    python enumerate_sessions.py --db PATH.db    # explicit path

It prints:
  - every CLI (interactive chat) session, chronological, with title/msgs/date
  - per-source counts (cli / cron / subagent / tool)
  - distinct recurring cron JOBS (grouped by title prefix), with run counts
  - subagent count + date span
"""
import sqlite3
import os
import sys
from datetime import datetime
from collections import Counter

DEFAULT_DB = r"C:\Users\zqmco\AppData\Local\hermes\state.db"


def resolve_db(profile=None, db=None):
    if db:
        return db
    if profile:
        return os.path.expanduser(f"~/.hermes/profiles/{profile}/state.db")
    return DEFAULT_DB


def fmt(ts):
    try:
        if isinstance(ts, (int, float)):
            return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
    except Exception:
        pass
    return str(ts)[:16]


def main():
    profile = None
    db = None
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--profile":
            profile = args[i + 1]; i += 2
        elif a == "--db":
            db = args[i + 1]; i += 2
        else:
            i += 1

    path = resolve_db(profile, db)
    if not os.path.exists(path):
        print(f"ERROR: state.db not found at {path}", file=sys.stderr)
        sys.exit(1)

    # Open read-only so we never lock the live store.
    c = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    try:
        rows = c.execute(
            "SELECT id,title,source,model,started_at,message_count "
            "FROM sessions ORDER BY started_at ASC"
        ).fetchall()
    except sqlite3.OperationalError as e:
        print(f"ERROR reading sessions table: {e}", file=sys.stderr)
        sys.exit(1)

    cli = [r for r in rows if r[2] == "cli"]
    cron = [r for r in rows if r[2] == "cron"]
    sub = [r for r in rows if r[2] == "subagent"]
    tool = [r for r in rows if r[2] == "tool"]

    print(f"=== SESSION STORE: {path} ===")
    print(f"TOTAL RECORDS: {len(rows)}  (cli={len(cli)} cron={len(cron)} "
          f"subagent={len(sub)} tool={len(tool)})")

    print(f"\n=== INTERACTIVE CLI SESSIONS: {len(cli)} ===")
    for n, (sid, title, src, model, sa, mc) in enumerate(cli, 1):
        print(f"{n:2d}. {fmt(sa)} | {sid} | {(title or '(untitled)')[:50]} | msgs={mc}")

    # distinct cron jobs: group by title before the ' · ' separator
    jobs = Counter()
    for sid, title, src, model, sa, mc in cron:
        key = (title or "alpha").split("·")[0].strip() or "alpha"
        jobs[key] += 1
    print(f"\n=== CRON JOBS: {len(cron)} runs, {len(jobs)} distinct ===")
    for k, v in sorted(jobs.items(), key=lambda x: -x[1]):
        print(f"  {v:4d}  {k}")

    if sub:
        sa_min = fmt(min(r[4] for r in sub))
        sa_max = fmt(max(r[4] for r in sub))
        print(f"\n=== SUBAGENT (delegated children): {len(sub)} "
              f"(range {sa_min}..{sa_max}) ===")

    print("\nNOTE: counts above are the AUTHORITATIVE census from state.db. "
          "Do NOT trust session_search browse/discovery for totals (both cap at 3).")


if __name__ == "__main__":
    main()
