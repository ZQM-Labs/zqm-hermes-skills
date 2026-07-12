# Council repo-maintenance telemetry

Read-only observability for the 32-seal council to reason about host repo health.

## Files

- `tools/repo_tools.py`: `_git(args,cwd)`, `repo_status(path)`, `known_repo_telemetry()`, `KNOWN_PATHS`
- `tools/maintenance_tool.py`: `score_repo_health(telemetry)`, `maintenance_brief()`
- `tools/__init__.py`: package init for relative imports

## Usage

```python
from tools.repo_tools import known_repo_telemetry
from tools.maintenance_tool import maintenance_brief

for t in known_repo_telemetry():
    print(t["path"], t.get("branch"), t.get("ahead"), t.get("behind"), t.get("dirty"))

print(maintenance_brief())
```

## Scoring rules

- clean repo: 100
- branch error: -40
- ahead >= 1: -15
- behind >= 1: -10
- dirty >= 10: -20
- dirty == 1..9: -5
- clamped to 0..100

## Constraints

- Do not edit `service.py`, `utils/helpers.py`, `config.py` while the repo has unmerged conflicts (`AA`/`UD`/`UU`).
- Introduce clean new modules in subpackages (`tools/`, `utils/next/`) instead.
- Wire new modules into the service layer only after the merge is resolved.
- Do not perform destructive recursive pycache removal when denied; proceed with authored-only commit instead.

## Minimal safe merge path

When histories are nearly aligned but merge state is dirty:

1. `git merge --abort`
2. `git reset --soft origin/master`
3. Unstage pycache adds/deletes without removing disk files
4. Update `.gitignore` to intended ignore rules
5. Preserve authored deletions/changes
6. Commit only authored files
7. Do not force-push without explicit confirmation

## Ad-hoc verification

Use `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*.py`, assert coverage, scoring, and seal fields, then delete the probe.

## council_engine.py sealed schema

- `SEAL_TAXONOMY`: `council-01`..`council-32` -> `(seal, domain)`; length == 32
- `VOID_TAG = "void"`
- Deliberation messages emit `sealTags` and `voidTag`
