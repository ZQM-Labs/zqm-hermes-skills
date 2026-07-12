#!/usr/bin/env python3
import argparse, json, math, sys
from pathlib import Path

try:
    import numpy as np
except Exception:
    np = None


def _tonal_entropy(chroma):
    if chroma is None:
        raise ValueError("chroma missing")
    chroma = np.maximum(chroma, 0.0)
    s = float(chroma.sum())
    if s <= 0:
        return 0.0
    p = chroma / s
    H = -float(np.sum(p * np.log2(p + 1e-12)))
    return H / math.log2(12.0)


def creative_proxy(path: Path) -> dict:
    data = path.read_bytes()[:256 * 1024]
    counts = [0] * 26
    idx = {chr(ord("a") + i): i for i in range(26)}
    for b in data:
        c = chr(b).lower()
        if c in idx:
            counts[idx[c]] += 1
    total = float(sum(counts))
    h = 0.0
    for c in counts:
        if c <= 0:
            continue
        p = c / total
        h -= p * math.log2(p)
    return {
        "mode": "proxy_text",
        "entropy_bits": h,
        "normalized_entropy": h / math.log2(26) if total > 0 else 0.0,
    }


def analyze_audio(path: Path):
    if np is None:
        return creative_proxy(path)
    try:
        import soundfile as sf

        y, sr = sf.read(str(path))
        if y is None or (hasattr(y, "size") and y.size == 0):
            return creative_proxy(path)
    except Exception:
        return creative_proxy(path)
    y = np.asarray(y, dtype=float)
    if y.ndim > 1:
        y = np.mean(y, axis=1)
    n = len(y)
    if n > 200000:
        n = 200000
    y = y[:n]
    steps = 12
    w = 1024
    if w > n:
        w = max(256, n // 16)
    bands = []
    for i in range(steps):
        lo = 60.0 * (2.0 ** (i / 12.0))
        hi = 60.0 * (2.0 ** ((i + 1) / 12.0))
        bands.append((lo, hi))
    chroma = np.zeros(steps, dtype=float)
    for start in range(0, n, w):
        chunk = y[start : start + w]
        if len(chunk) <= 1:
            continue
        X = np.fft.rfft(chunk * np.hanning(len(chunk)))
        mag = np.abs(X) ** 2
        freqs = np.fft.rfftfreq(len(chunk), 1.0 / sr)
        for i, (lo, hi) in enumerate(bands):
            m = (freqs >= lo) & (freqs < hi)
            chroma[i] += float(mag[m].sum()) if m.any() else 0.0
    octave = float(chroma[0]) + float(chroma[12]) if chroma.shape[0] >= 1 else 0.0
    p5 = float(chroma[7]) + float(chroma[19])
    dissonance = float(chroma[1]) + float(chroma[6]) + float(chroma[11])
    return {
        "mode": "audio_chroma_proxy",
        "chroma_entropy_norm": _tonal_entropy(chroma),
        "dissonance_energy": dissonance,
        "consonance_energy": octave + p5,
        "chroma": chroma.tolist(),
    }


def human(s: dict) -> str:
    if s.get("mode") == "proxy_text":
        return (
            f"Creative harmony proxy: entropy={s['entropy_bits']:.3f} bits, "
            f"normalized={s['normalized_entropy']:.2%}"
        )
    return (
        f"Tonal entropy (norm)={s.get('chroma_entropy_norm', 0):.2%}; "
        f"dissonance={s.get('dissonance_energy', 0):.2f}, "
        f"consonance={s.get('consonance_energy', 0):.2f}"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--human", action="store_true")
    ap.add_argument("--json", dest="to_json", action="store_true")
    args = ap.parse_args()
    s = analyze_audio(args.path)
    if args.to_json:
        print(json.dumps(s, indent=2))
    elif args.human:
        print(human(s))
    else:
        print(json.dumps(s))


if __name__ == "__main__":
    main()
