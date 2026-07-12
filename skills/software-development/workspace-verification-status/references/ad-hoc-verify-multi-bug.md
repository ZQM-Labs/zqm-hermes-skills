# Ad-hoc verification playbook: multi-bug fixes + recurring bug classes

Condensed, task-focused knowledge bank for the `workspace-verification-status`
fallback protocol when you fix several real defects across a repo in one pass
and must produce fresh per-file verification evidence.

## Consolidated verification template (run after editing N files)
One temp script (`hermes-verify-<topic>.py` in %TEMP%), executed with the
repo-local interpreter, that checks every changed file and prints a per-step
PASS/FAIL plus an OVERALL line. Keep it OS-safe and self-cleaning.

```python
import sys, os, py_compile, sqlite3, json
from datetime import datetime
sys.path.insert(0, REPO)
# STEP 0 syntax: py_compile each changed file (doraise=True)
# STEP k behavioral: import module, drive the changed path, assert real state
#   e.g. read the SQLite row the API should have written; open the invoice file
# Report: what was checked, actual output, exit/assert, "ad-hoc not suite green".
```

Order: (0) compile all changed files -> (1..N) one behavioral check per changed
file -> SUMMARY block with per-step PASS/FAIL and OVERALL. Delete the script
after the run.

## Recurring bug classes observed (and the fix/verify pattern)

### A. Cross-user / hardcoded absolute path
Symptom: `FileNotFoundError` at first *write* to a path like
`C:\Users\OtherUser\Desktop\...` that can't be created on the current host.
Fix: retarget constants to `Path(__file__).resolve().parent / "spine_events"`
(project-local), not `Path.home()`.
Verify: run the writer, assert the dir exists and >=1 event file was written.
(Monkeypatch the constant in a temp harness for a no-edit observation first.)

### B. Persistence reads a key the envelope doesn't have (status-key mismatch)
Symptom: API/runner returns an envelope with nested keys
(`"promotion"`, `results[].pass`) but the persistence call reads a non-existent
top-level key (`result.get("status")`, `result.get("pass")`).
Effect: silently writes wrong verdicts (e.g. always "UNKNOWN" or always "FAIL").
Fix: read the key that actually exists (`result.get("promotion") ==
"PROMOTABLE"`).
Verify: drive the endpoint, then SELECT the latest `status` row from the DB and
assert it equals the correct verdict.

### C. Aggregator reads a source the producer never writes
Symptom: billing reads `usage_events.jsonl` but the API writes to a SQLite
`usage_events` table -> empty invoices.
Fix: point the consumer at the real producer source (same DB/table/file).
Verify: generate the artifact (invoice) and assert `usage_details` is non-empty.

### D. Timezone-aware vs naive datetime comparison
Symptom: comparing a naive window bound (`datetime(2026,7,1)`) against
timezone-aware stored timestamps (`...Z` / `+00:00`) raises `TypeError`, which
a bare `except:` swallows -> every event silently filtered out.
Fix: normalize bounds to UTC-aware before comparing
(`start.replace(tzinfo=timezone.utc)`).
Verify: count events in the window and assert > 0.

### E. `KeyError` on undefined dict keys in aggregation
Symptom: `UNIT_RATES[service]` crashes when the producer emits services
(H13-H35) outside the pricing table (only H8-H12 defined).
Fix: `UNIT_RATES.get(service, 0.0)` (treat unknown as $0, don't crash billing).
Verify: run aggregation over a mixed set including the out-of-table service and
assert no crash + it appears in output with charge 0.

## What "verified" means here (and does NOT mean)
- PROVES: the crash/key/wiring/tz bugs are fixed - real run, real DB rows, real
  artifact written.
- DOES NOT change: mock logic the user didn't ask to fix (e.g. hypotheses that
  still hardcode "pass", endpoints that still return hardcoded PASS). Leave
  those scoped out unless told otherwise.
- Always state explicitly: ad-hoc verification, not a committed suite; outputs
  are literal stdout, not reconstructed.
