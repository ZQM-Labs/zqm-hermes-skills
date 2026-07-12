#!/usr/bin/env python3
"""Generate a complete, dated markdown index of Hermes session history.

Querying state.db directly is the ONLY reliable way to enumerate sessions — the
session_search tool's browse mode caps at 10 rows and its FTS5 discovery mode lets
recurring cron jobs bury interactive chats. Run this to produce a durable artifact.

Usage:
    python generate_index.py [--db PATH] [--out PATH]

Defaults resolve the current-profile state.db and write to <cwd>/session_history_index.md.
Opens the DB read-only so it never locks the live store.
"""
import sqlite3, os, argparse, datetime

DEFAULTS = [
    r"C:\Users\zqmco\AppData\Local\hermes\state.db",
    os.path.expanduser(r"~\.hermes\state.db"),
    os.path.expanduser(r"~\.local\share\hermes\state.db"),
]

def fmt(x):
    try:
        return datetime.datetime.fromtimestamp(x).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return str(x)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=None)
    ap.add_argument("--out", default=os.path.join(os.getcwd(), "session_history_index.md"))
    a = ap.parse_args()

    db = a.db or next((p for p in DEFAULTS if os.path.exists(p)), None)
    if not db:
        raise SystemExit("state.db not found; pass --db PATH")
    print("Reading (read-only):", db)

    c = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    out = []
    out.append("# Hermes Session History Index\n")
    out.append("Generated: %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
    out.append("Source: `%s` (queried directly, NOT via session_search browse).\n" % db)

    total = c.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    cli = c.execute("SELECT COUNT(*) FROM sessions WHERE source='cli'").fetchone()[0]
    cron = c.execute("SELECT COUNT(*) FROM sessions WHERE source='cron'").fetchone()[0]
    sub = c.execute("SELECT COUNT(*) FROM sessions WHERE source='subagent'").fetchone()[0]
    tool = c.execute("SELECT COUNT(*) FROM sessions WHERE source='tool'").fetchone()[0]
    out.append("## Summary")
    out.append("- Total records: **%d**" % total)
    out.append("- Interactive CLI chats: **%d**" % cli)
    out.append("- Cron runs: **%d**" % cron)
    out.append("- Delegated subagents: **%d**" % sub)
    out.append("- Tool sessions: **%d**\n" % tool)
    out.append("> LESSON: session_search browse caps at 10; FTS5 discovery lets cron runs")
    out.append("> bury interactive chats. For complete enumeration, query state.db directly:")
    out.append("> `SELECT id,title,source,started_at,message_count FROM sessions ORDER BY started_at`\n")

    out.append("## Interactive CLI Sessions (%d)\n" % cli)
    out.append("| # | Date/Time | Title | Model | Msgs | Session ID |")
    out.append("|---|-----------|-------|-------|------|------------|")
    for i, (sid, title, model, sa, mc) in enumerate(
        c.execute("SELECT id,title,model,started_at,message_count FROM sessions "
                  "WHERE source='cli' ORDER BY started_at ASC").fetchall(), 1):
        out.append("| %d | %s | %s | %s | %d | %s |" % (
            i, fmt(sa), (title or "(untitled)").replace("|", "/"), model, mc, sid))

    out.append("\n## Recurring Cron Jobs (%d runs)\n" % cron)
    out.append("| Runs | Job |")
    out.append("|------|-----|")
    crons = c.execute("SELECT id,title FROM sessions WHERE source='cron'").fetchall()
    names = {}
    for sid, title in crons:
        key = (title.split("·")[0].strip() if title and title != "alpha"
               else "alpha (%s)" % sid.split("_2026")[0][:14])
        names[key] = names.get(key, 0) + 1
    for k, v in sorted(names.items(), key=lambda x: -x[1]):
        out.append("| %d | %s |" % (v, k))

    out.append("\n## Delegated Subagents (%d)\n" % sub)
    rng = c.execute("SELECT MIN(started_at), MAX(started_at) FROM sessions WHERE source='subagent'").fetchone()
    out.append("- Range: %s .. %s" % (fmt(rng[0]), fmt(rng[1])))
    out.append("- Worker children of parallel eval/audit runs; not standalone chats.\n")

    content = "\n".join(out) + "\n"
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(content)
    print("WROTE %s (%d bytes)" % (a.out, len(content)))
    print("cli=%d cron=%d sub=%d tool=%d total=%d" % (cli, cron, sub, tool, total))

if __name__ == "__main__":
    main()
