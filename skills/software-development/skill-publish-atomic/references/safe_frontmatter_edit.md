# safe_frontmatter_edit.md — non-corrupting Hermes SKILL.md cross-ref / frontmatter edit
# Reusable method backing skill-publish-atomic rule #2 (CROSS-REFER).
# WHY: regex/string replacement of YAML frontmatter silently corrupts — a dangling
# `metadata:` block before `---` breaks skill loading (17 files lost this way, 2026-07-11;
# fixed only by restore-from-backup + PyYAML rewrite). USE PyYAML to parse -> mutate -> dump.
# Validate every file after.

## The safe pattern (Python, stdlib + pyyaml)
```python
import os, re, yaml

DST = r"C:\Users\zqmco\AppData\Local\hermes\skills"

def split_front(txt):
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", txt, re.S)
    if not m: return None, None, txt
    fm = yaml.safe_load(m.group(1))
    if not isinstance(fm, dict): return None, None, txt
    return fm, m.group(1), m.group(2)

def set_related(fm, partners):
    fm.setdefault("metadata", {})
    if not isinstance(fm["metadata"], dict): fm["metadata"] = {}
    fm["metadata"].setdefault("hermes", {})
    if not isinstance(fm["metadata"]["hermes"], dict): fm["metadata"]["hermes"] = {}
    existing = fm["metadata"]["hermes"].get("related_skills") or []
    if isinstance(existing, str): existing = [existing]
    fm["metadata"]["hermes"]["related_skills"] = sorted(set(list(existing) + list(partners)))

# 1) BACKUP first (cheap insurance against a bad run):
#    cp -r "$DST" /c/tmp/skills_backup_$(date +%Y%m%d_%H%M%S)
# 2) Walk, parse, merge, dump — never regex the frontmatter:
for root, _, fs in os.walk(DST):
    for f in fs:
        if f != "SKILL.md": continue
        p = os.path.join(root, f)
        raw = open(p, encoding="utf-8-sig").read().replace("\r\n", "\n")  # BOM + CRLF tolerant
        fm, _, body = split_front(raw)
        if fm is None: continue
        nm = fm.get("name")
        if nm not in EDGES: continue            # EDGES = {skill: [partners]}
        set_related(fm, EDGES[nm])
        new_fm = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True, default_flow_style=False)
        open(p, "w", encoding="utf-8").write("---\n" + new_fm + "---\n" + body)
# 3) VALIDATE every file after (one broken --- = skill fails to load):
#    for each SKILL.md: yaml.safe_load(frontmatter) must succeed.
```

## Rules
- Union, don't overwrite: keep existing `related_skills`, add desired partners. Idempotent.
- `yaml.safe_dump(sort_keys=False)` preserves key order; `allow_unicode=True` keeps unicode.
- BOM (`utf-8-sig`) + CRLF (`\r\n`->`\n`) tolerant read avoids false "no frontmatter" failures.
- If a run corrupted files (dangling `metadata:` atop the file): restore the backup, re-run
  THIS method. Do NOT hand-edit the dangling block.
- Resolve skills by their `name:` field, not disk path, so you never guess locations.
