#!/usr/bin/env python3
"""Noise models and fidelity helpers."""
from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from typing import Optional

import numpy as np


@dataclass
class NoiseModel:
    bit_flip_probability: float = 0.0
    phase_flip_probability: float = 0.0
    depolarizing_probability: float = 0.0
    amplitude_damping_gamma: float = 0.0

    def is_identity(self) -> bool:
        return not any(
            [
                self.bit_flip_probability,
                self.phase_flip_probability,
                self.depolarizing_probability,
                self.amplitude_damping_gamma,
            ]
        )


def _bit_flip(prob: float) -> np.ndarray:
    p = max(0.0, min(1.0, prob))
    return np.array(
        [[math.sqrt(1 - p), math.sqrt(p)], [math.sqrt(p), -math.sqrt(1 - p)]],
        dtype=np.complex128,
    )


def _phase_flip(prob: float) -> np.ndarray:
    p = max(0.0, min(1.0, prob))
    return np.array(
        [[1, 0], [0, math.cos(p) + 1j * math.sin(p)]],
        dtype=np.complex128,
    )


def noisy_channel(noise: NoiseModel) -> np.ndarray:
    if noise.is_identity():
        return np.eye(2, dtype=np.complex128)

    bit = _bit_flip(noise.bit_flip_probability)
    phase = _phase_flip(noise.phase_flip_probability)

    depolarizing = 1.0 - noise.depolarizing_probability
    q = max(0.0, noise.depolarizing_probability)
    pauli = [
        math.sqrt(q / 3) * np.array([[0, 1], [1, 0]], dtype=np.complex128),
        math.sqrt(q / 3) * np.array([[0, -1j], [1j, 0]], dtype=np.complex128),
        math.sqrt(q / 3) * np.array([[1, 0], [0, -1]], dtype=np.complex128),
    ]

    amplitude_damping = np.array(
        [
            [1, 0],
            [0, math.sqrt(max(0.0, 1 - noise.amplitude_damping_gamma))],
        ],
        dtype=np.complex128,
    )
    if noise.bit_flip_probability and noise.phase_flip_probability:
        combined: np.ndarray = phase @ bit
    elif noise.bit_flip_probability:
        combined = bit
    elif noise.phase_flip_probability:
        combined = phase
    else:
        combined = np.eye(2, dtype=np.complex128)

    # Weighted average of Pauli noise through linear superposition.
    for p in pauli:
        combined = depolarizing * combined + p

    if noise.amplitude_damping_gamma:
        combined = amplitude_damping @ combined
    return combined


def _safe_sqrtm(matrix: np.ndarray) -> np.ndarray:
    try:
        return np.sqrt(matrix)
    except Exception:
        pass
    out = np.zeros_like(matrix, dtype=np.complex128)
    eigvals, eigvecs = np.linalg.eigh(matrix.astype(np.complex128))
    out = eigvecs @ np.diag(np.sqrt(np.clip(eigvals, 0.0, None))) @ eigvecs.T.conj()
    return out


def fidelity(state_a: np.ndarray, state_b: np.ndarray) -> float:
    if state_a.shape != state_b.shape:
        raise ValueError("State shape mismatch")
    a_flat = state_a.ravel()
    b_flat = state_b.ravel()
    if state_a.ndim == 2 and state_a.shape[0] == state_a.shape[1] and state_b.ndim == 2 and state_b.shape[0] == state_b.shape[1]:
        rho_a = state_a
        rho_b = state_b
    elif a_flat.shape == b_flat.shape:
        rho_a = np.outer(a_flat, np.conjugate(a_flat))
        rho_b = np.outer(b_flat, np.conjugate(b_flat))
    else:
        raise ValueError("Density shape mismatch")
    sqrt_rho_a = _safe_sqrtm(rho_a)
    prod = sqrt_rho_a @ rho_b @ sqrt_rho_a
    sqrt_prod = _safe_sqrtm(prod)
    overlap = float(np.trace(sqrt_prod).real ** 2)
    return max(0.0, min(1.0, overlap))


def counts_entropy(counts: Dict[str, int]) -> float:
    total = sum(counts.values())
    if total <= 0:
        return 0.0
    ps = [float(v) / total for v in counts.values() if v > 0]
    if len(ps) <= 1:
        return 0.0
    return max(0.0, min(1.0, -sum(p * math.log2(p) for p in ps) / max(math.log2(len(ps)), 1e-12)))


def counts_harmony(counts: Dict[str, int], expected_top: Optional[str] = None) -> float:
    ent = counts_entropy(counts)
    top = expected_top or (max(counts, key=counts.get) if counts else "")
    concentration = counts.get(top, 0) / max(sum(counts.values()), 1)
    return float(np.clip(1.0 - 0.6 * ent - 0.4 * (1.0 - concentration), 0.0, 1.0))


def state_sse(state_a: np.ndarray, state_b: np.ndarray) -> float:
    if state_a.shape != state_b.shape:
        raise ValueError("State shape mismatch for SSE")
    diff = (state_a - state_b).ravel()
    return float(np.real(np.vdot(diff, diff)))


def _json_default(obj):
    if isinstance(obj, np.ndarray):
        return {"__ndarray__": True, "shape": obj.shape, "dtype": str(obj.dtype)}
    if isinstance(obj, complex):
        return {"__complex__": True, "real": obj.real, "imag": obj.imag}
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


def _json_dumps(obj) -> str:
    try:
        return json.dumps(obj, ensure_ascii=False, default=_json_default)
    except Exception:
        return str(obj)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bit-flip", type=float, default=0.0)
    parser.add_argument("--phase-flip", type=float, default=0.0)
    parser.add_argument("--depolarizing", type=float, default=0.0)
    parser.add_argument("--amplitude-damping", type=float, default=0.0)
    parser.add_argument("--compare")
    parser.add_argument("--state-a")
    parser.add_argument("--state-b")
    args = parser.parse_args()

    noise = NoiseModel(args.bit_flip, args.phase_flip, args.depolarizing, args.amplitude_damping)
    print("noise_model=" + _json_dumps(noise.__dict__))
    if args.compare == "fidelity" and args.state_a and args.state_b:
        a = np.array([complex(x.strip()) for x in args.state_a.split(",")], dtype=np.complex128)
        b = np.array([complex(x.strip()) for x in args.state_b.split(",")], dtype=np.complex128)
        print("fidelity=" + str(round(fidelity(a, b), 6)))
    if args.compare == "sse" and args.state_a and args.state_b:
        a = np.array([complex(x.strip()) for x in args.state_a.split(",")], dtype=np.complex128)
        b = np.array([complex(x.strip()) for x in args.state_b.split(",")], dtype=np.complex128)
        print("sse=" + str(round(state_sse(a, b), 6)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
