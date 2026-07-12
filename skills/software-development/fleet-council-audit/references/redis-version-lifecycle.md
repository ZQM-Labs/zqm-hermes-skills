# Redis version lifecycle + CVE-date bank

Condensed, reusable research for the "scan deeply around X and its critical dates" forensic verb.
Fuse these dates with the LIVE probe data (process start, last RDB save, uptime) to grade AGE and
patchability. Last refreshed 2026-07-11 from web search; re-verify if the version differs.

## Release / feature timeline (what era a build belongs to)
- Redis 3.0.0 GA: 2015-04-01 (first GA with clustering).
- Redis 3.0.x final: 3.0.7, 2016-02.
- **`protected-mode` introduced: Redis 3.2.0, 2016-05.** Before this, an unauth `CONFIG SET` from
  any interface is NOT auto-refused. So Redis <3.2 has no built-in network safety net.
- ACLs (user/password + command/key scoping): Redis 6.0, 2020. Absent in 3.x/5.x.
- Redis 3.0.504 specifically: a Windows-port patch build (MSOpenTech / tugarida redis-msi lineage)
  on the 3.0.x core. No upstream security fixes since ~2016. EOL ~2016 — ~10 years of unpatched CVEs.

## VERSION AGE ≠ INSTALL AGE (don't conflate — HIT live 2026-07-11)
A frozen-version build says NOTHING about when it was installed. The Windows Redis port
died at 3.0.x, so `redis-msi`/`tugarida` **only ever ships 3.0.504** — a box installed in
2021, 2023, or last week ALL report 3.0.504. So "10-year-old EOL build" is TRUE of the CODE
but does NOT mean "installed 10 years ago." When the user reacts to a version-date claim
("10 years old?!?!?"), they are flagging exactly this conflation. Report precisely:
- "Code is frozen at 2016-era 3.0.504 (EOL, unpatchable)" — about the binary.
- "Install date UNKNOWN — cannot be read without Node-X admin (MSI cache / registry Uninstall
  key)" — about the host.
Never let "EOL 2016" imply "ancient hardware / 10-year-old install." The danger is the frozen
version + default-open config, not the install's age.

## INSTALLER ATTRIBUTION (how to tell what put Redis there — no creds needed)
On Windows, a stock `redis-msi` (MSOpenTech / tugarida redis-msi lineage) install is
identifiable from the live `CONFIG GET *` / `INFO server` with NO credentials:
- `config_file` = `C:\Program Files\Redis\redis.windows-service.conf` (or redis.windows.conf)
- runs as a **Windows SERVICE** (PID via `CONFIG GET process_id`), auto-start
- `dir` = `C:\Program Files\Redis`, `dbfilename` = `dump.rdb`
- `pidfile` = `/var/run/redis.pid` (a *nix default path that was NEVER customized)
=> all-default, zero tuning, zero data = a **stock leftover / orphaned dependency**, NOT a
purpose-built service. This strongly supports "locking it down is low-risk" — but the DEFINITIVE
owner/purpose still needs Node-X admin (grep the host for what references :6379). Do NOT claim a
purpose you haven't verified.

## Relevant CVEs for 3.0.x (with disclosure dates)
- **CVE-2015-8080** — Integer overflow in `getnum` (lua_struct.c), 2.8.x<2.8.24 / 3.0.x<3.0.6.
  Disclosed 2015-11. DoS / heap corruption via crafted Lua. Requires Lua exec.
- **CVE-2016-10517** — Lua sandbox escape, <3.2.7. CVE entry 2017-11 (NIST initial analysis
  2017-11-15). Allows running restricted commands. Affects 3.0.x.
- CVE-2018-12326 / CVE-2018-12473 — buffer overflows in 3.2/4.x/5.x (>=3.2; may not hit 3.0.5 directly
  but in the family).

## Severity NUANCE for OLD versions
- On 3.0.504 the practical risk is NOT "exploit a CVE" — it's that requirepass is EMPTY + bind is
  EMPTY + protected-mode ABSENT, so ANY LAN host runs any command including `CONFIG SET dir/
  dbfilename` → arbitrary file write → RCE. The CVEs just confirm the build will never be patched.
- Grade as CRITICAL RCE primitive regardless of CVE count. Empty keyspace = no data-exfil component
  (see redis-rce-grading.md "empty-keyspace grading nuance") but the file-write RCE stands.

## Quick age-grading rule
- version < 3.2  → no protected-mode, unpatchable for the safety net → CRITICAL if unauth+unbound.
- 3.2–5.x       → protected-mode exists (blocks unauth CONFIG from non-loopback) but no ACLs.
- >= 6.0        → ACLs available; set requirepass + an ACL user, or bind 127.0.0.1.
- ANY version with empty requirepass + empty bind on a LAN interface = CRITICAL RCE primitive.

## Source notes
- Dates cross-checked via NVD (nvd.nist.gov) + Redis GitHub 00-RELEASENOTES (2.8/3.0/3.2 branches)
  + Debian/OpenCVE security trackers, 2026-07-11.
- For non-Redis "X", replicate this shape: web-search "<product> <version> release date end of life"
  + "<product> <version> CVE disclosure dates", then fuse with live probe timestamps.
- Version/install-age + installer-attribution sections added 2026-07-11 from the live Node-2
  3.0.504 investigation (user flagged the age conflation with "10 years old?!?!?").
