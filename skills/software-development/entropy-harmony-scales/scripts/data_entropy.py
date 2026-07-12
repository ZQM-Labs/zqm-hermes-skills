#!/usr/bin/env python3
import argparse, json, math, os, sys
from pathlib import Path

BIN_ASCII_LOWER = [chr(c) for c in range(ord("a"), ord("z") + 1)]


def _read(path: Path, sample_bytes: int) -> bytes:
    data = path.read_bytes()
    return data[:max(1, sample_bytes)]


def _counts(data: bytes, unit: str):
    if unit == "B":
        bins = 256
        counts = [0] * bins
        for b in data:
            counts[b] += 1
    elif unit == "C":
        bins = len(BIN_ASCII_LOWER)
        counts = [0] * bins
        idx = {c: i for i, c in enumerate(BIN_ASCII_LOWER)}
        for b in data:
            c = chr(b).lower()
            if c in idx:
                counts[idx[c]] += 1
    elif unit == "W":
        bins = 2
        counts = [0, 0]
        for b in data:
            counts[1 if chr(b).isspace() else 0] += 1
    elif unit == "S":
        bins = 2
        shell_sig = frozenset(
            [
                ord(" "),
                ord("\t"),
                ord("\n"),
                ord("`"),
                ord("$"),
                ord("\\"),
                ord("&"),
                ord("|"),
                ord(";"),
                ord("<"),
                ord(">"),
                ord("("),
                ord(")"),
                ord("{"),
                ord("}"),
                ord("["),
                ord("]"),
                ord("!"),
                ord("?"),
                ord("*"),
                ord("~"),
                ord("'"),
                ord('"'),
                ord("#"),
                ord("="),
                ord("\r"),
            ]
        )
        counts = [0, 0]
        for b in data:
            counts[1 if b in shell_sig else 0] += 1
    else:
        raise ValueError(f"Unknown unit: {unit}")
    return bins, counts


def _entropy(counts, total):
    total = float(total)
    out = 0.0
    effective = 0
    for c in counts:
        if c <= 0:
            continue
        p = c / total
        out -= p * math.log2(p)
        effective += 1
    return out, effective


def stats(path: Path, unit: str, sample_bytes: int):
    data = _read(path, sample_bytes)
    total = len(data)
    if total == 0:
        return {
            "path": str(path),
            "bytes": 0,
            "unit": unit,
            "entropy_bits": 0.0,
            "normalized_entropy": 0.0,
            "effective_bins": 0,
        }
    bins, counts = _counts(data, unit)
    h, eff = _entropy(counts, total)
    return {
        "path": str(path),
        "bytes": total,
        "unit": unit,
        "entropy_bits": h,
        "normalized_entropy": h / math.log2(bins) if bins > 1 else 0.0,
        "bins": bins,
        "effective_bins": eff,
    }


def human(s: dict) -> str:
    return (
        f"{Path(s['path']).name}: entropy={s['entropy_bits']:.3f} bits, "
        f"normalized={s['normalized_entropy']:.2%}, bins={s['bins']}, "
        f"effective={s['effective_bins']}"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--unit", choices=["B", "C", "W", "S"], default="B")
    ap.add_argument("--sample-bytes", type=int, default=256 * 1024)
    ap.add_argument("--human", action="store_true")
    ap.add_argument("--json", dest="to_json", action="store_true")
    args = ap.parse_args()
    s = stats(args.path, args.unit, args.sample_bytes)
    if args.to_json:
        print(json.dumps(s, indent=2))
    elif args.human:
        print(human(s))
    else:
        print(json.dumps(s))


if __name__ == "__main__":
    main()
