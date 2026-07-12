#!/usr/bin/env python3
"""
Reusable SAFE frontmatter editor for Hermes SKILL.md cross-referencing.
WHY: regex/string edits to YAML frontmatter silently corrupt it (a dangling
`metadata:` block BEFORE `---` breaks skill loading). This tool parses with
PyYAML, mutates ONLY `metadata.hermes.related_skills`, round-trip-validates,
and never touches the body. Used live 2026-07-11 to fix 17 corrupted files.

USAGE:
  # union <partner> into one skill's related_skills:
  python safe_frontmatter_edit.py <skill_dir> add <partner>
  # union a full FORWARD map (name -> [partners]) across many skills:
  python safe_frontmatter_edit.py <skills_root> map forward.py
  # validate every SKILL.md parses (run AFTER any bulk edit):
  python safe_frontmatter_edit.py <skills_root> validate

forward.py must define: FORWARD = {"skill_name": ["partner1","partner2", ...]}
Edges are bidirectional-checked but this script only WRITES (union) one
direction; run twice (swap A<->B) or precompute the full undirected map.
"""
import os, re, sys, yaml, shutil

def split_front(txt):
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)$", txt, re.S)
    if not m:
        return None, None, txt
    return yaml.safe_load(m.group(1)), m.group(1), m.group(2)

def set_related(fm, partners):
    fm.setdefault("metadata", {})
    if not isinstance(fm["metadata"], dict): fm["metadata"] = {}
    fm["metadata"].setdefault("hermes", {})
    if not isinstance(fm["metadata"]["hermes"], dict): fm["metadata"]["hermes"] = {}
    cur = fm["metadata"]["hermes"].get("related_skills") or []
    if isinstance(cur, str): cur = [cur]
    fm["metadata"]["hermes"]["related_skills"] = sorted(set(list(cur) + list(partners)))

def load_name(path):
    raw = open(path, encoding="utf-8-sig").read().replace("\r\n","\n")
    fm,_,_ = split_front(raw)
    return fm.get("name") if isinstance(fm, dict) else None

def edit_one(path, partners):
    raw = open(path, encoding="utf-8-sig").read().replace("\r\n","\n")
    fm, raw_fm, body = split_front(raw)
    if not isinstance(fm, dict):
        return False, "no frontmatter"
    n_before = len(set(fm.get("metadata",{}).get("hermes",{}).get("related_skills") or []))
    set_related(fm, partners)
    new_fm = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True, default_flow_style=False)
    try: yaml.safe_load(new_fm)
    except Exception as e:
        return False, "dump invalid: "+str(e)[:60]
    tf = path + ".tmp"
    open(tf, "w", encoding="utf-8").write("---\n" + new_fm + "---\n" + body)
    shutil.move(tf, path)
    return True, f"ok ({n_before}+{len(partners)} partners)"

def validate(root):
    bad = 0; n = 0
    for r,_,fs in os.walk(root):
        if "SKILL.md" not in fs: continue
        p = os.path.join(r,"SKILL.md"); n += 1
        raw = open(p, encoding="utf-8-sig").read().replace("\r\n","\n")
        m = re.match(r"^---\s*\n(.*?)\n---\s*\n", raw, re.S)
        if not m: print("  BAD", os.path.basename(r), "NO_FM"); bad += 1; continue
        try:
            d = yaml.safe_load(m.group(1))
            if not isinstance(d, dict): print("  BAD", os.path.basename(r), "not dict"); bad += 1
        except Exception as e: print("  BAD", os.path.basename(r), "YAML:", str(e)[:50]); bad += 1
    print(f"validated {n} files, {bad} problems")
    return bad

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    target, mode = sys.argv[1], sys.argv[2]
    if mode == "validate":
        sys.exit(0 if validate(target)==0 else 1)
    if mode == "add" and len(sys.argv) >= 4:
        p = os.path.join(target, "SKILL.md")
        ok, msg = edit_one(p, [sys.argv[3]])
        print(("OK " if ok else "FAIL ")+os.path.basename(target)+" "+msg)
    elif mode == "map" and len(sys.argv) >= 4:
        ns = {}
        exec(open(sys.argv[3]).read(), ns)
        FORWARD = ns.get("FORWARD", {})
        for name, partners in FORWARD.items():
            found = None
            for r,_,fs in os.walk(target):
                if "SKILL.md" in fs and load_name(os.path.join(r,"SKILL.md")) == name:
                    found = os.path.join(r,"SKILL.md"); break
            if not found: print("  skip (not found):", name); continue
            ok, msg = edit_one(found, partners)
            print(("OK " if ok else "FAIL ")+name+" "+msg)
    else:
        print(__doc__); sys.exit(1)

if __name__ == "__main__":
    main()
