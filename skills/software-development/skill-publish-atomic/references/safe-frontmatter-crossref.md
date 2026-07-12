# Safe Hermes skill YAML frontmatter editing (cross-reference wiring)
Use this whenever you bulk-edit `related_skills` / `metadata.hermes.*` across many SKILL.md files.

## Why this exists
A regex/substring rewrite of the frontmatter (`re.sub(r"related_skills:\[.*?\]", ...)`) prepended a
STRAY DANGLING `metadata:` block BEFORE the opening `---` on 17 files, breaking YAML parsing. Recovered by
restoring a pre-edit `cp -r` backup and re-running with PyYAML.

## SAFE METHOD (PyYAML — never regex the frontmatter)
1. Split file into frontmatter (between first `---` and next `---`) + body.
2. `yaml.safe_load(fm)` -> dict. Mutate ONLY `metadata.hermes.related_skills`
   (`fm.setdefault("metadata",{}); fm["metadata"].setdefault("hermes",{}); rs = sorted(set(existing+new))`).
3. `new_fm = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True, default_flow_style=False)`.
4. Round-trip validate `yaml.safe_load(new_fm)` BEFORE overwriting.
5. Write to `<file>.tmp` then `shutil.move` over the original (atomic).
6. After the run: parse EVERY SKILL.md with a BOM/CRLF-tolerant `yaml.safe_load` and assert 0 problems.

## Bidirectional edge check
Build an undirected edge set {new_skill -> [partners]}. For each edge ensure BOTH ends list each other.
Skip edges whose partner is NOT in the canonical tree (e.g. skills that live only in a stale duplicate
tree — they cannot receive a back-link). Count orphans: every new skill needs >=1 canonical back-link.

## Recovery
Always `cp -r "$DST" /tmp/skills_backup_<ts>` BEFORE editing. If validation fails:
`rm -rf "$DST" && cp -r /tmp/skills_backup_* "$DST"`, then re-run the safe method.

## Gotchas
- Read with `encoding="utf-8-sig"` (BOM) and `.replace("\r\n","\n")` (CRLF) before YAML parse.
- Resolve skills by their `name:` field, not guessed disk paths.
- MSYS/bash: pass Windows-native paths to Python via `cygpath -w` or raw `r"C:\..."` — MSYS `/c/...`
  can resolve to `C:\c\...` and write to the wrong (stale) tree.
