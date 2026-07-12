-- SQLite schema for three-layer service / C2 investigations.
-- Reuse for every "investigate fully" pass; one DB per service or per combined sweep.
-- Never store secrets (keys/tokens) — only auth presence/absence + observed codes.

CREATE TABLE IF NOT EXISTS run_meta ( k TEXT, v TEXT );
CREATE TABLE IF NOT EXISTS process_layer ( pid INT, field TEXT, value TEXT );
CREATE TABLE IF NOT EXISTS net ( pid INT, kind TEXT, peer TEXT );
CREATE TABLE IF NOT EXISTS service_probe ( service TEXT, endpoint TEXT, code TEXT, note TEXT );
CREATE TABLE IF NOT EXISTS verdict ( layer TEXT, finding TEXT, verdict TEXT );

-- C2 egress helper (run after populating net):
-- SELECT pid, peer FROM net WHERE kind='EST'
--   AND peer NOT LIKE '127.%' AND peer NOT LIKE '::1%'
--   AND peer NOT LIKE '192.168.1.%' AND peer NOT LIKE '0.0.0.0%';
-- empty => no external egress for that PID => C2=FALSE (by topology)
