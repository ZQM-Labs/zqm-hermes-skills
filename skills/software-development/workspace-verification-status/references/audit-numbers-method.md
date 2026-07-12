# Audit: explain numbers, classify computed vs hardcoded

Use this when the user asks to "investigate" / "reflect real numbers" / explain
what values mean — as opposed to just proving code runs.

## Workflow

1. Read every file in the target dir (use read_file + search_files in parallel
   batches; for dirs, `find . -type f` via terminal first).
2. Stand up a real environment: `uv venv --python 3.11 .venv` then
   `uv pip install -p .venv/Scripts/python.exe -r requirements.txt` (+ add any
   runtime deps the code imports but requirements omit, e.g. fastapi/uvicorn/
   httpx). uv is available on this Windows host; `python3` is NOT.
3. Write a temp verify script (`hermes-verify-*.py`) that:
   - imports the modules, runs each hypothesis/function, and dumps the REAL
     returned payload (not just pass/fail).
   - For code that crashes on a hardcoded cross-user path (e.g.
     `C:\Users\OtherUser\...`), retarget the path constant to a temp dir in the
     harness instead of editing the repo; report that you did.
   - Re-runs after any edit so verification is fresh (the runtime will flag
     "unverified" if you edit then don't re-run).
4. Classify and explain each result:
   - COMPUTED: result came from a real formula over inputs (e.g. SHA3 of a
     string, cavity f = c/2·sqrt(...), horn-torus volume 2π², Plücker minors).
     State the formula, the numeric output with units, and what it physically
     means. Note if the math is right but the physical analogy is invalid
     (e.g. modeling the Great Pyramid as a metal rectangular cavity).
   - HARDCODED: a literal constant compared to a threshold it was chosen to pass
     (e.g. `fidelity:0.95` checked `>0.9`; a string "Microwatts" checked to
     contain "Micro"). Label the verdict self-fulfilling. Flag decorative
     p_values (0.001–0.05 constants) and literal counts (e.g. "11 algorithms
     tested") as not real measurements.
5. Separate any narrative/fiction markdown (resonant-network, multiverse,
   "first light activation") from engineering evidence. Say plainly it is not
   backed by the code.
6. Report as AD-HOC verification (not suite green), with the actual output
   shown. Clean up temp scripts.

## Hardening class-level skills

If a loaded/umbrella skill governed this task, embed the lesson there (user
wants real numbers explained, not PASS/PROMOTABLE). Memory alone is not enough
for behavioral preferences.
