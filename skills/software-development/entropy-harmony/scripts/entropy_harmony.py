from __future__ import annotations

import math
import sys
from dataclasses import dataclass
from typing import Dict, Optional, Sequence


@dataclass(frozen=True)
class EntropyHarmony:
    domain: str
    entropy: float
    harmony: float
    temperature: float
    energy: float
    interval: str
    action: str
    recommended_delta: Optional[float] = None


def _clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def shannon_normalized_entropy(dist: Sequence[float]) -> float:
    total = sum(dist)
    if total <= 0:
        return 0.0
    ps = [float(x) / total for x in dist if x > 0]
    if len(ps) <= 1:
        return 0.0
    log2n = math.log2(len(ps))
    if log2n == 0:
        return 0.0
    h = -sum(p * math.log2(p) for p in ps)
    return h / log2n


def physics_metrics(dist: Sequence[float]) -> Dict[str, float]:
    h = shannon_normalized_entropy(dist)
    return {
        "entropy": _clamp(h),
        "harmony": _clamp(1.0 - h),
        "temperature": _clamp(h),
    }


def music_metrics(pitch_dist: Sequence[float], rhythm_dist: Sequence[float]) -> Dict[str, float]:
    h_p = shannon_normalized_entropy(pitch_dist)
    h_r = shannon_normalized_entropy(rhythm_dist)
    dissonance = 0.60 * h_p + 0.40 * h_r
    return {
        "entropy": _clamp((h_p + h_r) / 2.0),
        "harmony": _clamp(1.0 - dissonance),
        "temperature": _clamp((h_p + h_r) / 2.0),
    }


def comms_metrics(dist: Sequence[float]) -> Dict[str, float]:
    h = shannon_normalized_entropy(dist)
    return {
        "entropy": _clamp(h),
        "harmony": _clamp(1.0 - h),
        "temperature": _clamp(h),
    }


def security_metrics(secret_space_score: float, signal_variance: float) -> Dict[str, float]:
    h_a = _clamp(secret_space_score)
    v_d = _clamp(signal_variance)
    e_adv = 0.55 * h_a + 0.45 * v_d
    return {
        "entropy": _clamp(e_adv),
        "harmony": _clamp(1.0 - e_adv),
        "temperature": _clamp(e_adv),
    }


def software_metrics(coupling: float, complexity: float, failure_entropy: float) -> Dict[str, float]:
    h_c = _clamp(coupling)
    c_c = _clamp(complexity)
    h_f = _clamp(failure_entropy)
    s_s = 0.40 * h_c + 0.35 * c_c + 0.25 * h_f
    return {
        "entropy": _clamp(s_s),
        "harmony": _clamp(1.0 - s_s),
        "temperature": _clamp(s_s),
    }


def classify(domain: str, entropy: float, harmony: float) -> tuple[str, str]:
    if domain == "music":
        if harmony >= 0.60:
            return "harmonic", "preserve"
        if harmony >= 0.40:
            return "balanced", "tune"
        return "tense", "tune"
    if domain == "comms":
        if harmony >= 0.70:
            return "harmonic", "preserve"
        if harmony >= 0.45:
            return "balanced", "tune"
        return "tense", "tune"
    if domain == "security":
        if harmony >= 0.70:
            return "harmonic", "preserve"
        if harmony >= 0.50:
            return "balanced", "harden"
        return "tense", "harden"
    if domain == "software":
        if harmony >= 0.65:
            return "harmonic", "preserve"
        if harmony >= 0.45:
            return "balanced", "refactor"
        return "tense", "refactor"
    # physics/default
    if harmony >= 0.70:
        return "harmonic", "preserve"
    if harmony >= 0.45:
        return "balanced", "tune"
    return "tense", "tune"


def compute(
    domain: str,
    dist: Optional[Sequence[float]] = None,
    pitch_dist: Optional[Sequence[float]] = None,
    rhythm_dist: Optional[Sequence[float]] = None,
    secret_space_score: Optional[float] = None,
    signal_variance: Optional[float] = None,
    coupling: Optional[float] = None,
    complexity: Optional[float] = None,
    failure_entropy: Optional[float] = None,
    target_harmony: Optional[float] = None,
) -> EntropyHarmony:
    domain = domain.lower().strip()
    if domain == "physics":
        if dist is None:
            raise ValueError("physics requires dist")
        m = physics_metrics(dist)
    elif domain == "music":
        if pitch_dist is None or rhythm_dist is None:
            raise ValueError("music requires pitch_dist and rhythm_dist")
        m = music_metrics(pitch_dist, rhythm_dist)
    elif domain == "comms":
        if dist is None:
            raise ValueError("comms requires dist")
        m = comms_metrics(dist)
    elif domain == "security":
        if secret_space_score is None or signal_variance is None:
            raise ValueError("security requires secret_space_score and signal_variance")
        m = security_metrics(secret_space_score, signal_variance)
    elif domain == "software":
        if coupling is None or complexity is None or failure_entropy is None:
            raise ValueError("software requires coupling, complexity, failure_entropy")
        m = software_metrics(coupling, complexity, failure_entropy)
    else:
        raise ValueError(f"unsupported domain: {domain}")

    entropy = _clamp(float(m["entropy"]))
    harmony = _clamp(float(m["harmony"]))
    temperature = _clamp(float(m.get("temperature", 1.0 - harmony)))
    energy = entropy + (1.0 - harmony) ** 2
    interval, action = classify(domain, entropy, harmony)

    rec_delta = None
    if target_harmony is not None:
        target_harmony = _clamp(target_harmony)
        rec_delta = _clamp(target_harmony - harmony, -0.5, 0.5)

    return EntropyHarmony(
        domain=domain,
        entropy=entropy,
        harmony=harmony,
        temperature=temperature,
        energy=energy,
        interval=interval,
        action=action,
        recommended_delta=rec_delta,
    )


def self_test() -> int:
    cases = 0
    failures = 0
    for case in [
        {"domain": "physics", "dist": [0.5, 0.5]},
        {"domain": "physics", "dist": [1.0]},
        {"domain": "music", "pitch_dist": [1.0 / 12.0] * 12, "rhythm_dist": [0.9, 0.05, 0.05]},
        {"domain": "comms", "dist": [0.7, 0.2, 0.1]},
        {"domain": "security", "secret_space_score": 0.8, "signal_variance": 0.2},
        {"domain": "software", "coupling": 0.6, "complexity": 0.3, "failure_entropy": 0.2},
    ]:
        cases += 1
        try:
            result = compute(**case)
            assert 0.0 <= result.entropy <= 1.0
            assert 0.0 <= result.harmony <= 1.0
            assert round(result.temperature + result.harmony, 6) <= 1.0 + 1e-9
        except Exception as e:
            failures += 1
            print(f"SELF-TEST FAIL: {case} => {e}")

    print(f"SELF-TEST done: cases={cases}, failures={failures}")
    return 1 if failures else 0


def main(argv: Sequence[str]) -> int:
    if not argv or argv[0] in ("--help", "-h", "help"):
        print("Usage: entropy_harmony.py compute|self-test ...")
        return 0
    cmd = argv[0]
    if cmd == "self-test":
        return self_test()
    if cmd != "compute":
        print(f"unknown command: {cmd}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(tuple(sys.argv[1:])))
