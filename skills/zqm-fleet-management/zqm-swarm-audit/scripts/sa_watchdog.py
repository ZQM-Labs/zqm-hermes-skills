#!/usr/bin/env python3
# ZQM SA WATCHDOG  (read-only fleet situational-awareness logger)
# - Probes the 4 fleet nodes + critical AI/Redis ports every run.
# - Appends a reachability row to fleet_endpoint_audit.db :: sa_watchdog_log
#   (SEPARATE table from claim_hash / hash_drift_log -- does NOT touch the
#    existing 15-min hash-drift monitor).
# - Writes nothing to the fleet; logs only.
# - Prints output ONLY when node/port state CHANGES vs last run (watchdog
#   pattern: silent when stable, so cron delivery stays quiet).
# Schedule: Hermes cron "ZQM SA watchdog (reachability drift)" every 15m.
import socket, json, sqlite3, datetime, time

DB = r"C:\Users\zqmco\swarm\fleet_endpoint_review\fleet_endpoint_audit.db"
FLEET = {  # node -> (ip, [tracked ports])
    "N1": ("192.168.1.218", [22,135,139,445,5985,5986,11434]),
    "N2": ("192.168.1.21",  [22,135,139,445,5985,5986,6379,11434]),
    "N3": ("192.168.1.46",  [22,135,139,445,5985,5986,11434]),
    "N4": ("192.168.1.215", [22,135,139,445,5985,5986,11434]),
}
TIMEOUT = 0.6

def probe(ip, p):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(TIMEOUT)
    try:
        return 0 == s.connect_ex((ip, p))
    except Exception:
        return False
    finally:
        try: s.close()
        except Exception: pass

def state():
    st = {}
    for node,(ip,ports) in FLEET.items():
        openp = [p for p in ports if probe(ip,p)]
        st[node] = {"ip":ip, "up": len(openp)>0 or probe(ip,445), "open": openp}
    return st

def sig(st):
    return json.dumps({n: (s["up"], sorted(s["open"])) for n,s in st.items()})

def main():
    st = state()
    now = datetime.datetime.now().isoformat(timespec="seconds")
    con = sqlite3.connect(DB); c = con.cursor()
    c.execute("""CREATE TABLE IF NOT EXISTS sa_watchdog_log (
        ts TEXT, up_nodes TEXT, down_nodes TEXT,
        n2_redis INTEGER, n1_ollama INTEGER, n2_ollama INTEGER, n4_ollama INTEGER,
        sig TEXT, note TEXT)""")
    c.execute("CREATE TABLE IF NOT EXISTS sa_watchdog_state (k TEXT PRIMARY KEY, v TEXT)")
    prev = c.execute("SELECT v FROM sa_watchdog_state WHERE k='sig'").fetchone()
    prev_sig = prev[0] if prev else None
    cur_sig = sig(st)

    up   = [n for n,s in st.items() if s["up"]]
    down = [n for n,s in st.items() if not s["up"]]
    n2r  = int(6379 in st["N2"]["open"])
    n1o  = int(11434 in st["N1"]["open"])
    n2o  = int(11434 in st["N2"]["open"])
    n4o  = int(11434 in st["N4"]["open"])

    c.execute("INSERT INTO sa_watchdog_log VALUES (?,?,?,?,?,?,?,?,?)",
              (now, ",".join(up), ",".join(down) or "-",
               n2r, n1o, n2o, n4o, cur_sig,
               "state-change" if prev_sig is not None and prev_sig!=cur_sig else "stable"))
    c.execute("REPLACE INTO sa_watchdog_state (k,v) VALUES ('sig',?)", (cur_sig,))
    con.commit(); con.close()

    if prev_sig is None:
        print(f"[SA-WATCHDOG {now}] baseline captured: up={up} down={down} "
              f"N2redis={n2r} Ollama N1/N2/N4={n1o}/{n2o}/{n4o}")
    elif prev_sig != cur_sig:
        pst = json.loads(prev_sig); cst = {n:(s["up"],sorted(s["open"])) for n,s in st.items()}
        diffs=[]
        for n in FLEET:
            if pst.get(n)!=cst.get(n):
                diffs.append(f"{n}:{pst.get(n)}->{cst.get(n)}")
        print(f"[SA-WATCHDOG ALERT {now}] STATE CHANGE: {'; '.join(diffs)} | "
              f"up={up} down={down} N2redis={n2r} Ollama N1/N2/N4={n1o}/{n2o}/{n4o}")
    # else: silent (stable) -> nothing printed, cron stays quiet

if __name__ == "__main__":
    main()
