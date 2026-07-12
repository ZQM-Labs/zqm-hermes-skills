# Skill library topology + discovery recipe (learned 2026-07-11)

## Problem observed
A naive `find $APPDATA/hermes/skills -name SKILL.md` returned EMPTY (and errored)
on a Windows/MSYS host, yet `skills_list` reported 88 registered skills. Root
cause: on this host `$APPDATA` resolves to `C:\Users\zqmco\AppData\Roaming`, but
Hermes loads skills from `AppData\Local\hermes\skills`. The `Roaming\hermes\skills`
path is empty. The registry is the source of truth, not the disk.

## Canonical loaded tree (what the registry actually loads)
- `C:\Users\zqmco\AppData\Local\hermes\skills`  (99 SKILL.md found; registry loads 88)
  -> use this as the source of truth for on-disk files.

## Discovery recipe (run in terminal, POSIX/MSYS syntax)
1. Get the AUTHORITATIVE loaded set first — never trust disk counts:
   `skills_list` (via tool) -> count registered skills + categories.
2. Find the on-disk canonical dir:
   `ls -d "$APPDATA/Local/hermes/skills"`            # Local, NOT Roaming
   # If empty, fall back to literal:
   `ls -d "/c/Users/zqmco/AppData/Local/hermes/skills"`
3. Count files per candidate tree to locate the canonical one:
```sh
for d in \
  "/c/Users/zqmco/AppData/Local/hermes/skills" \
  "/c/Users/zqmco/.hermes/skills" \
  "/c/Users/zqmco/.hermes/shared/skills" \
  "/c/Users/zqmco/.zqm-auth/shared/skills" \
  "/c/Users/zqmco/zqm-hermes-skills" ; do
  n=$(find "$d" -name SKILL.md 2>/dev/null | wc -l); echo "$n  ->  $d"; done
```
4. Reconcile: registry count (e.g. 88) <= canonical tree file count (e.g. 99).
   The delta = duplicate/legacy SKILL.md under the same umbrella or non-loaded copies.

## Duplicate / stale trees (present on disk, NOT all live)
- `/c/Users/zqmco/.hermes/skills`              182 SKILL.md
- `/c/Users/zqmco/.hermes/skills/skills`         90
- `/c/Users/zqmco/.hermes/shared/skills`        182
- `/c/Users/zqmco/.zqm-auth/shared/skills`      182
- `/c/Users/zqmco/.zqm-auth/skills`             182
- `/c/Users/zqmco/zqm-hermes-skills`            160
- `/c/Users/zqmco/.hermes/instances/{alice,bob}/skills`  (per-instance)

These are copies/mirrors. A dedup/cleanup pass is warranted but OUT OF SCOPE for a
review; just note the divergence and report the registry count as the live number.

## Pitfalls
- `$APPDATA` = Roaming on Windows; skills live in Local. Never probe
  `$APPDATA/hermes/skills` for the loaded set.
- Do not equate disk SKILL.md count with registered skills — registry is authoritative.
- `find ... 2>/dev/null` can exit 1 while still returning valid partial output; do not
  treat a non-zero exit as "no skills exist".
