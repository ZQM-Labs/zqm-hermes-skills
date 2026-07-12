---
name: audit-sqlite-sink
description: 'Standardize how fleet/host AUDIT findings land as a SQLite database
  (the user''s standing rule: ''audit findings must land as a SQLite DB, not just
  markdown''). Codifies the proven schema, the write helpers, and the LEAD-RE-VERIFY-BEFORE-INSERT
  contract — the council''s headline numbers must be re-checked against live output
  before they are written as fact. Use for any multi-agent ''council'' sweep, host
  audit, or fleet inventory that must persist to disk as queryable evidence.'
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags:
    - zqm
    - audit
    - sqlite
    - council
    - evidence
    - verification
    - persistence
    related_skills:
    - codebase-truth-audit
    - data-eda
    - fleet-council-audit
    - hermes-cron-ops
    - runtime-codebase-verification
    - skill-publish-atomic
    - verified-repo-diagnostics
    - windows-host-audit
    - zqm-ollama-fleet
    - zqm-systems-review
---
# Audit → SQLite Sink

## When to use
- Any "investigate fully", "audit this box/fleet", "council sweep", or inventory task.
- The user wants findings as a DATABASE, not a chat summary or markdown file.
- A multi-agent council produced candidate numbers that must be verified before storage.

## THE CONTRACT (do not skip)
1. Council/leaves produce candidate findings on a shared blackboard.
2. LEAD re-verifies each HEADLINE number against LIVE output (re-run the probe, read
   the real stdout) before it is INSERTed. Unverified = `UNRESOLVED`, never `True`.
3. Every raw probe (including retries and failures) is stored as evidence rows — not
   just the conclusion.
4. Questions that can't be resolved from the sandbox are `UNRESOLVED` with a note on
   what on-host check is needed. Never fabricate to fill a row.

## Canonical schema (proven shape, 2026-07-11 ZQM swarm — 70 probes persisted)
The reusable builder is `scripts/audit_to_sqlite.py`. Tables actually used + VERIFIED this
session (this is the shape that WORKED; the prior 07-10 doc shape was stale — do not
reuse it):
- `nodes(node TEXT, ip TEXT, role TEXT, alive TEXT, models TEXT, base TEXT, exposed TEXT, verdict TEXT)`
- `probes(id INT, node TEXT, method TEXT, attempt TEXT, result TEXT, note TEXT)`  ← raw evidence, keep retries
- `findings(fid TEXT, title TEXT, severity TEXT, status TEXT, evidence TEXT)`
- `open_questions(qid TEXT, question TEXT, status TEXT, resolution TEXT)`
- `swarm_log(id INT, ts TEXT, event TEXT)`

Extend columns for the domain but keep the 5 core tables so cross-audit queries stay
portable. NOTE: `findings` is **5 columns** (fid,title,severity,status,evidence) —
a tuple with 4 or 6 fields throws `sqlite3.ProgrammingError: Incorrect number of
bindings`. Count columns before every INSERT.

## SQLite write pitfalls (burned 2026-07-11 — each cost an exit 1)
1. **Arity = live schema columns, not the tuple length you assume.** `INSERT INTO
   findings VALUES(?,?,?,?)` (4 placeholders) against a 5-col table with a 4-tuple
   → ProgrammingError. Run `PRAGMA table_info(<t>)` first if unsure of the live shape.
2. **Prefer parameterized `executemany("... VALUES(?,?,?,?,?)", rows)` over f-string
   SQL.** An f-string builder broke on embedded single quotes in evidence text
   (exit 1, unescaped `'`). Parameterized `?` placeholders are quote-safe.
3. **Single quotes inside Python string literals in the .py file.** Writing
   `r"... .openclaw\gateway ..."` or `r"quarantine\ folder ..."` renders a bare
   backslash before a letter → `SyntaxWarning: invalid escape sequence` and can corrupt
   the row. Use raw strings `r"..."` for backslash paths, and for apostrophes inside a
   normal string either double them or keep the text quote-free.
4. **Ad-hoc verifier false-negative (this skill's own trap).** When you write a
   post-change verifier whose assertion string is malformed (e.g. looked for
   `"Action:                               Block"` with rigid spacing), it reports FAIL even
   though system state is correct. If a direct read (`netsh ... show rule`) contradicts
   the verifier's FAIL, TRUST THE DIRECT READ, call the FAIL a non-finding, and re-run
   with a corrected (regex/flexible) parser — do NOT loop patching the code-under-test
   to satisfy a broken assertion. Report the direct read as authoritative.
   5. **Inconsistent per-source tuple widths (burned 2026-07-11 fleet endpoint review).**
    When the SAME endpoints table is fed from a LEAD source (N1 rows = 7-tuple WITH a
    `bind` field) AND from leaves (N2/N3/N4 rows = 6-tuple, NO `bind`), a fixed
    `for port,svc,bind,exp,risk,ver,notes in eps` unpack throws
    "not enough values to unpack (expected 7, got 6)". Normalize at ingest:
    `if len(row)==7: port,svc,bind,exp,risk,ver,notes=row else: port,svc,exp,risk,ver,notes=row; bind=exp`.
    Also `INSERT INTO nodes VALUES(?,?,?,?,?,?,?,?)` (8 ?) against a 7-field tuple threw
    "Incorrect number of bindings" — count the LIVE schema columns, not the tuple you
    assume; prefer naming columns explicitly in INSERT. Root cause = same as pitfall #1:
    the live schema is the contract and source rows may not all match it.

   ## Tamper-evident CLAIM CHAIN (proven 2026-07-11 ZQM swarm)
After findings are persisted, ANCHOR them so the audit record can later be
proven unaltered. This is now a standing deliverable for "hash claims" tasks.
```python
import sqlite3, hashlib, json, datetime
DB="fleet_swarm.db"
con=sqlite3.connect(DB); cur=con.cursor()
rows=cur.execute("SELECT fid,title,severity,status,evidence FROM findings ORDER BY fid").fetchall()
prev='0'*64; chain=[]
for fid,title,sev,status,ev in rows:
    canon=f"{fid}|{title}|{sev}|{status}|{ev}"
    h=hashlib.sha256(canon.encode()).hexdigest()
    this=hashlib.sha256((prev+h).encode()).hexdigest()  # bind prev -> tamper-evident
    chain.append((fid,h,prev,this)); prev=this
root=prev
# store per-claim chain links INSIDE the db (so db edits break the chain)
cur.execute("CREATE TABLE IF NOT EXISTS claim_hashes(fid TEXT,content_hash TEXT,prev_hash TEXT,chain_hash TEXT)")
cur.executemany("INSERT INTO claim_hashes VALUES(?,?,?,?)", chain)
# independent witness OUTSIDE the db (a tamperer who edits the db can't also edit this unless they find it)
db_sha=hashlib.sha256(open(DB,'rb').read()).hexdigest()
manifest={"db_sha256":db_sha,"chain_root":root,"claims":[{"fid":c[0],"content_hash":c[1],"prev_hash":c[2],"chain_hash":c[3]} for c in chain]}
json.dump(manifest, open("claim_manifest.json","w"), indent=2)
```
To later PROVE unaltered: re-hash the DB file, re-walk `claim_hashes`
from the first fid, and confirm both match `claim_manifest.json`. Any edit to a
finding row changes its content_hash -> breaks every downstream chain_hash -> the
stored root won't reproduce. (This is why the manifest lives OUTSIDE the DB.)

### EXACT re-hash algorithm used (anchoring pass — copy this shape)
```python
import sqlite3, hashlib, json, datetime
DB="fleet_swarm.db"
con=sqlite3.connect(DB); cur=con.cursor()
now=datetime.datetime.now().isoformat()
rows=cur.execute("SELECT fid,title,severity,status,evidence FROM findings ORDER BY fid").fetchall()
db_hash=hashlib.sha256(open(DB,'rb').read()).hexdigest()   # hash DB BYTES after commit
gen=now
chain_root=hashlib.sha256((db_hash+gen+",".join(r[0] for r in rows)).encode()).hexdigest()
prev=chain_root; ch={}
for fid,title,sev,status,ev in rows:
    h=hashlib.sha256((prev+fid+title+sev+status+ev).encode()).hexdigest()
    ch[fid]={"c":h,"p":prev}; prev=h
final_root=prev   # = chain_root of THIS pass
cur.execute("DROP TABLE IF EXISTS claim_hashes")
cur.execute("CREATE TABLE claim_hashes(fid TEXT PRIMARY KEY,claim_hash TEXT,prev_hash TEXT,chain_root TEXT,generated TEXT)")
for fid in ch:
    cur.execute("INSERT INTO claim_hashes VALUES(?,?,?,?,?)",(fid,ch[fid]["c"],ch[fid]["p"],final_root,gen))
manifest={"db_path":DB,"db_sha256":db_hash,"chain_root":final_root,"generated":gen,
          "claim_count":len(rows),
          "re_hash_reason":"<what changed this pass>",
          "live_verdicts":{"N2_redis":"PROVEN:+PONG","N1_sshd":"PROVEN:0.0.0.0:22"},
          "correction":"<if a prior claim was corrected, note it>"}
json.dump(manifest, open("claim_manifest.json","w"), indent=2)
con.commit(); con.close()
```
This session ran this ~8 times as findings mutated (council added F28-F36, genesis
F37-F42, an F26 correction). Each pass DROPs+reCREATES `claim_hashes`, recomputes
`db_sha256` on the NEW DB bytes, and writes a fresh `chain_root`. The manifest's
`re_hash_reason` + `live_verdicts` make the audit trail self-describing.

### GENESIS / SOURCE-HYGIENE deep-dive (read-only, when user says 'genesis'/'investigate <agent code>')
Lead-only read of the suspect module(s) — do NOT auto-run them. Pattern that worked:
1. READ the module(s) fully (read_file). Identify egress: does anything fire at
   import/`__main__`/from a live service path? Grep the tree for imports of the
   module + any auto-invoke (e.g. `import beacon`, `beacon.start`, `broadcast_recruitment`).
2. CONFIRM wiring: read the `__init__.py` / `app.py` that references it — does a live
   route call it (and behind what auth)? Confirm `if __name__=='__main__'` gates keep
   the noisy path inert unless manually run.
3. JUDGE egress class: LAN-multicast UDP self-promo + fixed-string lore (BENIGN) vs
   TCP egress / file-or-cred exfil / callback URL (MALICIOUS). Here `qseal_recruitment`
   broadcast only on `__main__`; content = worldbuilding; NO exfil -> benign.
4. FLAG hygiene (the user's actual interest): (a) hardcoded symmetric shared secret
   across files (forgeable signatures -> fix = per-node Ed25519, reuse existing
   `cryptography` lib); (b) FOREIGN-USER hardcoded absolute paths (e.g.
   `C:/Users/AlexZelenski/...`) = borrowed code, provenance tell + minor info-leak ->
   fix = relative/`Path.home()` paths; (c) LAN scan noise -> scope to fleet subnet + opt-in.
5. RECORD findings (F-IDs) with severity INFO/LOW + the read-only evidence, re-hash.
Pairs with artifact-provenance-review (provenance discipline) + codebase-truth-audit.
Re-run after every findings mutation so `chain_root` stays current.
- **RE-HASH RULE (standing):** after ANY findings INSERT/UPDATE/DELETE, re-walk the
  chain over ALL findings and rewrite claim_hashes + claim_manifest.json
  (DROP+reCREATE claim_hashes, recompute db_sha256 on the new DB bytes, new
  chain_root). This session mutated the ledger ~8 times and re-hashed each pass —
  the manifest is only trustworthy if it reflects the CURRENT row set. Log the
  re-hash reason + new chain_root in swarm_log so the audit trail shows each
  anchoring event.
- **FALSE-CONTRADICTION RECOVERY:** when a re-verify flips a PROVEN claim to
  CONTRADICTED, suspect the TOOLING before the claim. This session a subprocess
  netstat capture returned 0 rows + a regex returned 0 matches, producing 5
  false CONTRADICTED verdicts. Recovery: (1) re-run the probe with the PROVEN
  bare-terminal form (see windows-host-audit S2d netstat gotchas), (2) fix the
  regex, (3) re-derive, (4) only THEN flip the verdict. Never persist a
  contradiction that traces to a tooling bug — that corrupts the ledger.

## Memory -> vectorization system ingestion (proven 2026-07-11)
"memory to sql vectorization systems" often means feeding durable audit memory
into an in-repo RAG (e.g. ZQM-AI-Council/rag/). GOTCHAS that burned turns:
- LOCATE the real sink first. `rag/` here is IN-MEMORY only (RAGRetriever
  holds docs+embeddings in Python lists) — there is NO SQLite/Chroma/FAISS store,
  despite `config.py` defining `data/embeddings/` + `data/documents/`. dirs
  that don't even exist yet. Don't assume "vectorization" = a SQL store.
- PROBE the embedding endpoint BEFORE writing. `LocalAIEmbeddings` calls
  LocalAI `/v1/embeddings`; if that backend is DOWN it returns a 384-dim
  ZERO vector (fail-safe in embeddings.py). Ingesting then = fabricating
  meaningless vectors. CHECK the endpoint (netstat for LocalAI ports, or
  `urllib` POST a test embed) and REFUSE to vectorize if dead — instead
  pre-build the corpus + record the blocker in a `_INGEST_STATUS.json`.
- Build the corpus from the ledger + agent memory in the repo's OWN
  DocumentLoader schema (chunked {content,source,start,end}), persist to
  `data/documents/`, and write an `rag/ingest_corpus.py` that uses the
  repo's existing RAGRetriever/DocumentLoader. Then it's one command away
  from real vectorization once the backend is live. See references/rag-ingest.md.

## Verify the write (do not trust the print line alone)
```bash
python -c "import sqlite3;c=sqlite3.connect('fleet_swarm.db');\
print('probes',c.execute('SELECT COUNT(*) FROM probes').fetchone());\
print('findings',dict(c.execute('SELECT severity,COUNT(*) FROM findings GROUP BY severity').fetchall()))"
```

## Usage
```bash
# 1. copy scripts/audit_to_sqlite.py into the run dir
# 2. fill the DATA section (RUN_META, NODES, PROBES, QUESTIONS, LOG)
# 3. run
python audit_to_sqlite.py fleet_swarm_20260711.db
# => wrote fleet_swarm_20260711.db nodes=4 probes=12 questions=2 log=5
```
Then VERIFY the write by reading it back (don't trust the print line alone):
```bash
python -c "import sqlite3;c=sqlite3.connect('fleet_swarm_20260711.db');\
print(c.execute('SELECT node,verdict FROM nodes').fetchall())"
```

## Authoring a new audit DB without the script
Build inline (Python stdlib only — no deps):
```python
import sqlite3, datetime
con = sqlite3.connect("audit.db")
con.executescript(open("schema.sql").read())  # or the CREATE TABLE block above
con.execute("INSERT INTO run_meta VALUES (?,?,?,?)",
            ("run1", "goal", "192.168.1.218", datetime.datetime.now().isoformat()))
con.commit()
```

## Re-verify idiom (lead duty)
Before INSERT of any headline, re-run the leaf's probe and compare. If it diverges,
store BOTH the leaf claim and the re-verified value in `probes` with a note, and mark
the node `verdict` accordingly. The DB is evidence — contradictory rows are fine,
silent correction is not.

## Pitfalls
- Filling `NODES` straight from the blackboard without re-probing = storing fiction.
- Deleting failed/retry probe rows = destroying the audit trail. Keep them.
- Marking `UNRESOLVED` rows as `RESOLVED` to "look complete" — the user explicitly
  rejects this; emit real numbers or an honest UNRESOLVED.
- **HASH-DRIFT-CHECK is a standing deliverable, not optional.** For any persisted
  claim set, add a `claim_hash(id,claim,status,evidence,sha256,reverify)` table +
  a re-run script that RECOMPUTES each SHA-256 from a FRESH live re-probe and
  compares to stored. STABLE=N / DRIFT=0 proves the ledger is unaltered and the
  underlying state has not drifted — do NOT trust the stored claim; re-derive it.
  Schema pitfall (burned): the re-compute must use the SAME (claim+status) string
  the original hash used, else a stale-state mismatch looks like drift. If a verifier
  reports DRIFT, first confirm the live state actually changed (re-run the probe
  bare) before trusting the flag — a truncated socket recv or wrong substring match
  (e.g. looked for `"model":` but LiteLLM emits `"id":`) is a FALSE drift, not
  real state change. Fix the checker, re-run, confirm STABLE. (See references/council-drift-patterns.md.)
- **PATTERN study is a first-class deliverable for "study patterns".** Separate RECURRING
  (with cadence) from SINGLE/one-off and RECENT-CLUSTERED (triggered regression).
  A single unexpected-shutdown + 3 boot-correlated sshd crashes + recent-clustered
  litellm timeouts + post-fix-stable drift-log told a coherent "not a crash loop,
  one power-off, triggered config regression, ledger provably stable" story that raw
  error counts would have mis-framed as "unstable".

## References
- `scripts/audit_to_sqlite.py` — generic canon builder (copy + fill DATA)
- `scripts/audit_claim_chain.py` — tamper-evident SHA-256 claim chain over findings + external manifest witness
- `references/rag-ingest.md` — feeding audit memory + ledger into an in-repo RAG (locate sink, probe endpoint, refuse zero-vector fabricaton)
- `references/genesis-hygiene.md` — read-only deep-dive of borrowed/agent source: egress classification, INVARIANT shared-secret + foreign-user-path hygiene flags
- `references/patch-verify-gate.md` — AD-HOC patch safety: dry-run anchor check + temp-copy py_compile, for when there is NO git to revert and the user wants patches staged-not-applied
- `references/stability-diagnostic.md` — read-only reliability diagnostic (supervision gap, bind drift, routing flakiness) + dry-run staging of fixes; pairs with windows-host-audit §2d for the host layer
- `references/council-drift-patterns.md` — re-derive/re-verify workflow + PATTERN study: the HASH-DRIFT-CHECK pattern (recompute SHA-256 of every claim from a FRESH live re-probe, compare to stored, flag drift — proves ledger integrity without trusting the ledger), the recurring-vs-one-off PATTERN study (boot-correlated / recent-clustered / post-fix-stable), and the AD-HOC-VERIFIER REGEX-SUBSTRING trap (looked for `"FOUND" in "TASK_NOT_FOUND"` → false-positive; use `.startswith()` not `in`). Burned 2 turns this session.
- `references/remediation-vectors.md` — when a fix is blocked: enumerate EVERY remote+local execution vector (SSH/RDP/WinRM/agent-mesh/cached-cred/self-run) + prove viable vs dead before declaring stuck; pairs with fleet-council-audit 'investigate all possibilities'.
- `references/remediation-execution.md` — TIERED remediation model (Tier1 local/reversible apply, Tier2 disruptive-restart, Tier3 creds/lockout-gated), clarify-timeout→safe-default behavior, plaintext-secret REDACTION recipe, and the LiteLLM 401 "missing/invalid Bearer" diagnostic (key-not-attached vs cold-load-timeout).
- `references/reconcile-ledgers.md` — DUAL-LEDGER reconciliation (Option B): diff schemas, declare canonical, archive (mv not delete) the stray, record discrepancy, never `git add .` in a stray repo. Use when two audit DBs with conflicting counts both claim to be "the fleet audit".
- `references/reconcile-merge-canonical.md` — Option A MERGE/PROMOTE: keep the fragment in place as single ledger, import the stray's complete chain+findings as NEW tables, preserve fragment-unique tables, cron-safety check, handle schema-divergent `findings` + file-locked empty siblings. Use when the fragment has unique tables a running monitor reads and the stray has the intact chain.
- `references/attempted-solutions-enumeration.md` — query bank + classification taxonomy for the user's "full enumeration of attempted solutions" review ask; reads reliability_applied / remediations / reliability / open_questions from the fleet ledger; cron-safety caveat.
- PERSIST STABILITY FINDINGS too: when the user says "diagnostics / improve systems stability", run the read-only diagnostic, store F-findings (supervision gap MEDIUM, bind drift MEDIUM, routing LOW, event-log-clean INFO, resource-health INFO) + Q-items (Q20 supervision, Q21 bind fix, Q22 retry) into the SAME ledger, then RE-HASH. The claim chain covers all finding classes, not just security.
- fleet-council-audit (the parallel multi-agent pattern that feeds this sink)

## Ad-hoc verification + status reporting (standing)
When you edit code and the harness flags "no fresh passing verification evidence":
write a FOCUSED temp verifier under %TEMP% with a `hermes-verify-` prefix, run it
against the CHANGED behavior, then DELETE it. Report explicitly as "ad-hoc
verification, not suite green" — never claim a test suite passed when there is none.
If true verification is impossible (e.g. dead backend), state the CONCRETE BLOCKER
instead of asserting the work is fully verified. This session's genesis-hygiene
patches were staged + validated via references/patch-verify-gate.md without ever
touching live files until explicit --apply.

## Reconciling dual / competing audit ledgers (user's 'B' reconcile)
When an audit leaves TWO SQLite DBs both claiming to be "the fleet audit" with conflicting counts (e.g. canonical `fleet_endpoint_audit.db` = 16 claims / 4 nodes / 15 tables vs stray `fleet_swarm.db` = 68 claims / 11 nodes / 7 tables, DIFFERENT schema), reconcile before either is cited — standing rule: "no two audit DBs drift":
1. DIFF SCHEMAS FIRST (read-only): `PRAGMA table_info(<t>)` on both. If table names/columns differ (`claim_hash` vs `claim_hashes`, `nodes` 4 vs 11 rows), they are COMPLEMENTARY timepoints, NOT corrupt copies — don't force-merge or "fix" one to match the other.
2. DECLARE CANONICAL by recency + completeness (the one carrying the latest applied fixes — e.g. live `redis_auth`/`reliability` rows, 18 drift runs).
3. PRESERVE, DON'T DELETE the stray: `mv` the whole stray dir → `<canonical_dir>/archive/<name>/` (reversible). Deleting loses the external `claim_manifest.json` + blockchain-style `claim_hashes` your "hash claims" verb required.
4. RECORD the discrepancy in the canonical `meta` table: which DB is authoritative, where the stray now lives, and the count mismatch noted as "earlier broader scope, superseded".
5. NEVER `git add .` in the stray — it is often a separate repo with no remote and may carry secrets (auth.json / ca / cache). Move files only; don't commit.
6. SALVAGE check: if unsure the stray holds UNIQUE findings missing from canonical, diff row keys (fid lists) before archiving; copy any unique rows into canonical.

### Option A — MERGE / PROMOTE the stray into the canonical (cron-safe)
When the decision is A (NOT archive-the-stray): keep the EXISTING fragment DB in place as the
single ledger and IMPORT the stray's complete data into it. Use when the fragment carries
UNIQUE tables a running monitor depends on (e.g. a live cron reads its `claim_hash` table) AND
the stray carries the complete/intact claim chain the fragment lacks.
1. PRE-FLIGHT (mandatory): enumerate ALL `*.db` under the project root — there may be >2
   (this session found 6: 5 empty scaffolds + 1 complete stray + 1 fragment). Classify each
   via PRAGMA table_info + row COUNT.
2. CRON-SAFETY: grep monitor scripts for hard-coded `DB =` / `sqlite3.connect(`. If a running
   cron reads the fragment, you MUST NOT delete/rename/move it. Keep it in place; merge the
   stray's data in.
3. SCHEMA-DIVERGENT findings: if fragment `findings` and stray `findings` have DIFFERENT
   columns, import the stray's rows into a NEW table `swarm_findings` — never INSERT across
   mismatched column counts. Keep both.
4. Import stray `claim_hashes` (idempotent: skip fids already present) + `open_questions` as new
   tables; write a `meta` row declaring canonical_db + reconcile_decision=Option A.
5. VERIFY chain INTACT (walk prev_hash links, single chain_root) and confirm the cron's
   `claim_hash` table is untouched.
6. Archive EMPTY sibling scaffolds via mv; if WinError 32 (file locked by cron/AV) skip —
   confirm 0 rows first, they are inert. (Full recipe + verified end-state in
   references/reconcile-merge-canonical.md.)

## Enumerating ATTEMPTED SOLUTIONS (user's standing 'full enumeration of attempted solutions' review ask)
When the user asks to review what was tried (e.g. "full enumeration of attempted solutions"), do NOT summarize only what succeeded. Pull the applied-state tables from the fleet ledger and classify every vector. The `fleet_endpoint_review` ledger carries these tables (NOT in the minimal swarm schema):
- `reliability_applied(fix/status/evidence/ts)` — what was actually executed: `APPLIED+VERIFIED` / `APPLIED (prior)` / `GATED (UAC)` / `PARTIAL`. Authoritative "done" list.
- `remediations(target/issue/vector/status/blocker,decided)` — every remediation VECTOR with status: `VIABLE-BLOCKED` (needs cred), `VIABLE` (operator action), `REJECTED` (insecure/non-durable), `DEAD` (no listener/cred), `REPORT-ONLY` (user scope). Enumerate ALL, not just the winner.
- `reliability(area/state/risk/fix/gated/ts)` — design-state gaps + their gating.
- `open_questions(qid/status/question/resolution)` — RESOLVED vs OPEN; the change-log of what was settled vs parked.
- `redis_auth` — security fixes applied live (e.g. N2 requirepass).

Classification taxonomy to emit (verified 2026-07-12):
  Applied+Verified | Gated/Blocked (cred or UAC) | Drafted-Open (script on disk, not run) | Rejected/Dead (ruled out)
Give COUNTS per class + one line per item. Serves the user's standing option-enumeration preference.

CRON-SAFETY: the live "ZQM fleet diagnostics + drift watch" cron reads `fleet_endpoint_review/fleet_endpoint_audit.db` (its `claim_hash` + `hash_drift_log` tables) every 15 min. When enumerating/merging, never delete or rename that DB — it breaks the monitor. Query bank in references/attempted-solutions-enumeration.md.

End state: ONE canonical ledger + ONE clearly-named archived historical dir. No ambiguity about which number is "the fleet". (See references/reconcile-ledgers.md for the exact diff + archive commands; references/reconcile-merge-canonical.md for the Option A merge.)
