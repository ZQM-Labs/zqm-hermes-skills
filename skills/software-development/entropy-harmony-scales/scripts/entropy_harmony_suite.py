#!/usr/bin/env python3
import argparse, io, json, sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", type=Path, default=Path("."))
    ap.add_argument("--human", action="store_true")
    ap.add_argument("--json", dest="to_json", action="store_true")
    args = ap.parse_args()
    target = args.path
    out = {
        "path": str(target),
        "data_entropy": None,
        "system_harmony": None,
        "creative_harmony": None,
    }
    try:
        from data_entropy import stats as data_stats
        sample = target if target.is_file() else target
        out["data_entropy"] = {
            "unit": "B",
            **data_stats(sample, "B", 256 * 1024),
        }
    except Exception as e:
        out["data_entropy"] = {"error": str(e)}
    try:
        from system_harmony import main as system_main
        sys.argv = ["system_harmony.py", str(target), "--json"]
        buf = io.StringIO()
        old = sys.stdout
        sys.stdout = buf
        try:
            system_main()
        finally:
            sys.stdout = old
        out["system_harmony"] = json.loads(buf.getvalue() or "null")
    except Exception as e:
        out["system_harmony"] = {"error": str(e)}
    try:
        from audio_harmony import analyze_audio
        if target.is_file() and target.suffix.lower() in {
            ".wav", ".mp3", ".flac", ".m4a", ".ogg", ".wma", ".aiff"
        }:
            out["creative_harmony"] = analyze_audio(target)
        else:
            from data_entropy import stats as data_stats
            out["creative_harmony"] = {
                "mode": "proxy_from_data",
                **data_stats(target if target.is_file() else target, "C", 256 * 1024),
            }
    except Exception as e:
        out["creative_harmony"] = {"error": str(e)}
    if args.to_json:
        print(json.dumps(out, indent=2))
    elif args.human:
        print(f"Suite result for: {target}")
        if isinstance(out["data_entropy"], dict) and "entropy_bits" in out["data_entropy"]:
            d = out["data_entropy"]
            print(
                f"  data entropy: {d['entropy_bits']:.3f} bits, normalized={d['normalized_entropy']:.2%}"
            )
        if isinstance(out["system_harmony"], dict) and "harmony_score" in out["system_harmony"]:
            sh = out["system_harmony"]
            print(f"  system harmony: {sh['harmony_score']}/100 ({sh['issues_count']} issues)")
        if isinstance(out["creative_harmony"], dict):
            ch = out["creative_harmony"]
            if "chroma_entropy_norm" in ch:
                print(
                    f"  creative harmony: tonal={ch.get('chroma_entropy_norm',0):.2%}, "
                    f"dissonance={ch.get('dissonance_energy',0):.2f}, "
                    f"consonance={ch.get('consonance_energy',0):.2f}"
                )
            elif ch.get("mode") == "proxy_text":
                print(
                    f"  creative proxy: entropy={ch.get('entropy_bits',0):.3f}, "
                    f"normalized={ch.get('normalized_entropy',0):.2%}"
                )
    else:
        print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
