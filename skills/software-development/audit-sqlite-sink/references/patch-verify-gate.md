# Ad-Hoc Patch Verification Gate (non-git, pre-apply safety)

When you have a PATCH SCRIPT that will mutate live files (configs, source,
firewall rules) but there is NO git repo to `git diff`/revert, the standard
pre-commit pipeline does not apply. Use this gate instead: prove the patch is
safe BEFORE it touches anything.

Proven 2026-07-11 (ZQM genesis-hygiene patches: INVARIANT->Ed25519, scan_lan
scope, foreign-path cleanup). All three patches shipped dry-run + a temp-copy
py_compile check; live files were never modified until explicit --apply.

## The gate (3 stages, all read-only until the user says apply)

**Stage 1 — DRY-RUN shows the anchors match.**
Every patch script MUST default to --dry-run (print the diff, write nothing) and
only mutate on an explicit --apply flag. Run the dry-run and confirm ZERO
"[WARN] anchor not found" lines. A clean dry-run means the surgical string
replacements will land exactly where intended. If an anchor is missing, STOP —
the live file diverged from what you assumed; do not force it.

**Stage 2 — SYNTAX-CHECK on a temp copy (never the original).**
Copy the target dir to %TEMP% (or /tmp), run the patch's apply logic against the
COPY, then py_compile every .py in the copy. Zero compile errors = the patched
result is syntactically valid.
    import os, shutil, tempfile, py_compile
    SRC = r"C:\path\to\live\modules"
    TMP = tempfile.mkdtemp(prefix="hermes-patchtest-")
    shutil.copytree(SRC, TMP, dirs_exist_ok=True)
    # run the patch against TMP (override its ROOT/paths to TMP, or exec with apply forced)
    for dp,_,fs in os.walk(TMP):
        for f in fs:
            if f.endswith(".py"):
                py_compile.compile(os.path.join(dp,f), doraise=True)  # raises on SyntaxError
    shutil.rmtree(TMP, ignore_errors=True)   # destroy the copy; LIVE files untouched
Key points:
- Force apply on the copy by monkeypatching the script's path constant or
  replacing '"--apply" in sys.argv' with 'True' before exec()-ing it.
- The live SRC is never in the py_compile path. If you accidentally reference
  SRC instead of TMP, the check is meaningless — keep them separate.
- py_compile catches SyntaxError/IndentationError but NOT runtime import
  failures from missing deps. For those, a guarded import in a venv that has the
  deps is a stronger check (optional).

**Stage 3 — report status as AD-HOC, not "verified/suite-green".**
State explicitly: anchors matched (dry-run), patched copy compiles (syntax gate),
live files UNTOUCHED. This is NOT a test suite pass — it proves the patch is
well-formed and will apply, not that it is correct in behavior.

## When this gate is the right tool
- User wants patches DRAFTED + VALIDATED but NOT APPLIED yet ("A+B", "stage it",
  "ready-to-apply").
- Target is a user's home-dir source tree, not a git repo (no clean revert).
- Firewall/registry/service changes where a bad apply could break the host.

## Hand-off to real apply
Only after the user says "apply": run the three with --apply, then RE-RUN the
syntax gate on the LIVE files (now they exist and are patched) + re-run any
domain re-verification (e.g. re-hash the claim chain, re-read the firewall rule).
The gate's value is that "apply" becomes a low-risk button-press, not a leap.

## Pitfalls
- Forgetting to destroy the temp copy -> leaves a stale duplicate of live code
  lying around (clean it up; it's an artifact, not a backup).
- Trusting the patch script's own "APPLIED" print without the py_compile gate —
  the script may have written invalid Python. Compile the RESULT, not the claim.
- exec()-ing a patch script inside execute_code: pass {"os":os,"sys":sys} into
  the namespace or the script's own `import os` won't resolve (NameError). Simpler:
  run each patch as a real terminal subprocess, not via exec.
