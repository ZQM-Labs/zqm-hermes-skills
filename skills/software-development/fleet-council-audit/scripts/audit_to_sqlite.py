"""
audit_to_sqlite.py — reusable SQLite persistence builder for fleet-council-audit swarms.
COPY this into your swarm run dir, fill the DATA section, run:  python audit_to_sqlite.py [db_path]
Creates a .db with: run_meta, nodes, probes, open_questions, swarm_log.

Schema is the proven shape from the 2026-07-10 fleet-Ollama swarm. Keep raw probe rows
(incl. retries) as evidence; mark questions RESOLVED/UNRESOLVED honestly; log failures.
"""
import sqlite3, os, datetime, sys

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "fleet_swarm.db"

# ---- FILL THESE from the blackboard / leaf results (copy + edit) ----
RUN_META = ("20260710_swarm1",
            "<GOAL text>",
            "192.168.1.218",
            datetime.datetime.now().isoformat(timespec='seconds'))

# node, ip, host_alive, ollama_lan_exposed, models(int|None), size_gb(float|None), generate_health, verdict
NODES = [
    # ("N1", "192.168.1.218", "yes", "yes", 2, 29.16, "200 12.4s no-hang", "LAN-exposed Ollama"),
    # ("N3", "192.168.1.46", "yes (ping 4ms)", "no", None, None, "could not run", "NOT LAN-exposed"),
]

# node, method, attempt(int), result, note
PROBES = [
    # ("N3", "curl :11434/api/tags", 1, "HTTP 000 timeout", "10s-spaced retry"),
]

# qid, question, status("RESOLVED"|"UNRESOLVED"), resolution
QUESTIONS = [
    # ("Q1", "Is N3 localhost-bound or not running?", "UNRESOLVED", "Needs on-host check on .46"),
]

LOG = [
    # "swarm dispatched: 3 leaves",
    # "LEAF C did not append to blackboard (coordination gap)",
]

def build(db_path, run_meta, nodes, probes, questions, log):
    if os.path.exists(db_path):
        os.remove(db_path)
    con = sqlite3.connect(db_path)
    c = con.cursor()
    c.executescript("""
    CREATE TABLE run_meta (
      run_id TEXT PRIMARY KEY, goal TEXT, control_plane TEXT, created TEXT);
    CREATE TABLE nodes (
      node TEXT PRIMARY KEY, ip TEXT, host_alive TEXT, ollama_lan_exposed TEXT,
      models INTEGER, size_gb REAL, generate_health TEXT, verdict TEXT);
    CREATE TABLE probes (
      id INTEGER PRIMARY KEY AUTOINCREMENT, node TEXT, method TEXT,
      attempt INTEGER, result TEXT, note TEXT);
    CREATE TABLE open_questions (
      qid TEXT PRIMARY KEY, question TEXT, status TEXT, resolution TEXT);
    CREATE TABLE swarm_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, event TEXT);
    """)
    c.execute("INSERT INTO run_meta VALUES (?,?,?,?)", run_meta)
    c.executemany("INSERT INTO nodes VALUES (?,?,?,?,?,?,?,?)", nodes)
    c.executemany("INSERT INTO probes (node,method,attempt,result,note) VALUES (?,?,?,?,?)", probes)
    c.executemany("INSERT INTO open_questions VALUES (?,?,?,?)", questions)
    for e in log:
        c.execute("INSERT INTO swarm_log (ts,event) VALUES (?,?)",
                  (datetime.datetime.now().isoformat(timespec='seconds'), e))
    con.commit()
    con.close()

if __name__ == "__main__":
    build(DB_PATH, RUN_META, NODES, PROBES, QUESTIONS, LOG)
    print("wrote", DB_PATH,
          "nodes=%d probes=%d questions=%d log=%d" %
          (len(NODES), len(PROBES), len(QUESTIONS), len(LOG)))
