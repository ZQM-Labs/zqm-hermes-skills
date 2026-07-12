#!/usr/bin/env python3
import argparse, json, subprocess
from pathlib import Path

SEVERITY_PENALTY = {
    "Critical": 25,
    "High": 15,
    "Medium": 5,
    "Low": 2,
}


def _score(score: int, penalty: int):
    return max(0, score - penalty)


def check_git(root: Path, score: int):
    issues = []
    if not (root / ".git").exists():
        issues.append((str(root), "Low", "Not a git repository"))
        return _score(score, SEVERITY_PENALTY["Low"]), issues
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "status", "--porcelain"],
            capture_output=True,
            text=True,
            check=False,
        )
        if out.stdout.strip():
            issues.append((str(root / ".git"), "Low", f"Dirty: {len(out.stdout.strip().splitlines())} entries"))
            score = _score(score, SEVERITY_PENALTY["Low"])
        branch = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        if branch.stdout.strip() == "HEAD":
            issues.append((str(root / ".git"), "Medium", "Detached HEAD"))
            score = _score(score, SEVERITY_PENALTY["Medium"])
    except Exception as e:
        issues.append((str(root), "Low", f"Git check failed: {e}"))
    return score, issues


def check_yaml(root: Path, score: int):
    issues = []
    try:
        import yaml  # type: ignore
    except Exception:
        issues.append((str(root), "High", "PyYAML unavailable; YAML checks skipped"))
        return _score(score, SEVERITY_PENALTY["High"]), issues
    for p in root.rglob("*.y*ml"):
        try:
            _ = yaml.safe_load(p.read_text(encoding="utf-8", errors="replace"))
        except Exception as e:
            issues.append((str(p), "Medium", f"YAML parse error: {e}"))
            score = _score(score, SEVERITY_PENALTY["Medium"])
    return score, issues


def check_dups(root: Path, score: int):
    issues = []
    seen = {}
    for pkg in root.rglob("node_modules/package.json"):
        p = pkg.parent
        try:
            text = pkg.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        name = None
        version = None
        for line in text.splitlines():
            if line.strip().startswith('"name"'):
                name = line.split(":", 1)[1].strip().strip('",')
            if line.strip().startswith('"version"'):
                version = line.split(":", 1)[1].strip().strip('",')
        if not name:
            continue
        key = f"{name}"
        prev = seen.get(key)
        if prev and prev != version:
            issues.append((str(pkg), "Medium", f"Duplicate package: {name}={version}; prev={prev}"))
            score = _score(score, SEVERITY_PENALTY["Medium"])
        else:
            seen[key] = version
    return score, issues


def check_ports(root: Path, score: int):
    issues = []
    try:
        out = subprocess.run(["netstat", "-ano"], capture_output=True, text=True, check=False)
        used = {}
        for line in out.stdout.splitlines():
            parts = line.strip().split()
            if len(parts) >= 5 and parts[0].upper() == "TCP":
                addr_port = parts[1]
                if ":" not in addr_port:
                    continue
                port = addr_port.rsplit(":", 1)[-1].split("]")[0]
                pid = parts[-1]
                used.setdefault(port, {}).setdefault(pid, 0)
                used[port][pid] += 1
        for port, pids in used.items():
            if len(pids) > 1:
                issues.append((str(root), "High", f"Port {port} conflict: PIDs {', '.join(sorted(pids, key=lambda x: int(x)))}"))
                score = _score(score, SEVERITY_PENALTY["High"])
    except Exception as e:
        issues.append((str(root), "Low", f"Port check failed: {e}"))
    return score, issues


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path, default=Path("."), nargs="?")
    ap.add_argument("--checks", default="yaml,dup,git,port")
    ap.add_argument("--human", action="store_true")
    ap.add_argument("--json", dest="to_json", action="store_true")
    args = ap.parse_args()
    root = args.root.resolve()
    score = 100
    wants = [c.strip() for c in args.checks.split(",") if c.strip()]
    all_issues = []
    if "yaml" in wants:
        score, issues = check_yaml(root, score)
        all_issues.extend(issues)
    if "git" in wants:
        score, issues = check_git(root, score)
        all_issues.extend(issues)
    if "dup" in wants:
        score, issues = check_dups(root, score)
        all_issues.extend(issues)
    if "port" in wants:
        score, issues = check_ports(root, score)
        all_issues.extend(issues)
    out = {
        "path": str(root),
        "harmony_score": score,
        "checks": wants,
        "issues_count": len(all_issues),
        "issues": [{"path": p, "severity": s, "detail": d} for p, s, d in all_issues],
    }
    if args.to_json:
        print(json.dumps(out, indent=2))
    elif args.human:
        print(f"System harmony: {score}/100 ({out['issues_count']} issues)")
        for i in out["issues"]:
            print(f"  [{i['severity']}] {i['path']}: {i['detail']}")
    else:
        print(json.dumps(out))


if __name__ == "__main__":
    main()
