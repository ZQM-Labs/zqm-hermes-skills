#!/usr/bin/env python3
"""Quantum circuit simulator: state vector + density matrix + measurement."""
from __future__ import annotations

import argparse
import json
import math
import random
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np


class QuantumCircuit:
    def __init__(self, num_qubits: int):
        self.num_qubits = num_qubits
        self.dim = 2 ** num_qubits
        self.state = np.zeros((self.dim,), dtype=np.complex128)
        self.state[0] = 1.0 + 0.0j
        self.gate_history: List[str] = []
        self.memory: Dict[str, object] = {}

    def _apply_single(self, matrix: np.ndarray, target: int) -> None:
        # np.kron builds left-to-right; ops[0] acts on the highest qubit index.
        # qubit 0 is the least-significant bit, so its operator sits at the right.
        ops = [matrix if q == (self.num_qubits - 1 - target) else np.eye(2, dtype=np.complex128) for q in range(self.num_qubits)]
        op = ops[0]
        for m in ops[1:]:
            op = np.kron(op, m)
        self.state = op @ self.state

    def _cnot(self, control: int, target: int) -> None:
        perm = np.arange(self.dim)
        for i in range(self.dim):
            bits = format(i, f"0{self.num_qubits}b")
            if bits[self.num_qubits - 1 - control] == "1":
                flipped = list(bits)
                if flipped[self.num_qubits - 1 - target] == "0":
                    flipped[self.num_qubits - 1 - target] = "1"
                else:
                    flipped[self.num_qubits - 1 - target] = "0"
                perm[i] = int("".join(flipped), 2)
        mat = np.zeros((self.dim, self.dim), dtype=np.complex128)
        for i in range(self.dim):
            mat[perm[i], i] = 1
        self.state = mat @ self.state
        self.gate_history.append("CNOT")

    def _cz(self, control: int, target: int) -> None:
        for i in range(self.dim):
            bits = format(i, f"0{self.num_qubits}b")
            if bits[self.num_qubits - 1 - control] == "1" and bits[self.num_qubits - 1 - target] == "1":
                self.state[i] *= -1
        self.gate_history.append("CZ")

    def apply(self, name: str, matrix: np.ndarray, targets: Iterable[int]) -> None:
        targets = list(targets)
        if len(targets) != len(set(targets)):
            raise ValueError(f"Duplicate target qubits in apply({name}, {targets})")
        if len(targets) == 1:
            self._apply_single(matrix, targets[0])
            self.gate_history.append(name)
        elif len(targets) == 2:
            ctrl, tgt = targets
            if name.upper() == "CNOT":
                self._cnot(ctrl, tgt)
            elif name.upper() == "CZ":
                self._cz(ctrl, tgt)
            else:
                raise ValueError("Two-target apply requires CNOT/CZ naming")
        else:
            raise ValueError("Unsupported gate arity")

    def measure(self, shots: int = 1024, seed: Optional[int] = None) -> Dict[str, int]:
        if self.state.size == 0:
            return {}
        probs = (np.abs(self.state) ** 2).real
        probs = probs / max(probs.sum(), 1e-12)
        rng = random.Random(seed)
        counts: Dict[str, int] = {}
        for s in rng.choices(range(self.dim), weights=probs, k=shots):
            bits = format(s, f"0{self.num_qubits}b")
            counts[bits] = counts.get(bits, 0) + 1
        return dict(sorted(counts.items()))

    def density(self) -> np.ndarray:
        return np.outer(self.state, np.conjugate(self.state))

    @staticmethod
    def density_from_state(state: np.ndarray) -> np.ndarray:
        return np.outer(state, np.conjugate(state))

    def partial_trace(self, keep: Iterable[int]) -> np.ndarray:
        keep = sorted(set(keep))
        if not keep:
            return np.eye(self.dim, dtype=np.complex128)
        trace_out = [i for i in range(self.num_qubits) if i not in keep]
        if not trace_out:
            return self.density()
        rho = self.density().reshape([2] * self.num_qubits + [2] * self.num_qubits)
        ket_chars = [chr(ord('a') + q) for q in range(self.num_qubits)]
        bra_chars = [
            ket_chars[q] if q in trace_out else chr(ord('A') + q)
            for q in range(self.num_qubits)
        ]
        return np.einsum(
            f"{''.join(ket_chars)}{''.join(bra_chars)}->{''.join(ket_chars[q] for q in keep)}{''.join(bra_chars[q] for q in keep)}",
            rho,
        )

    def entanglement_entropy(self, subsystem_qubits: Iterable[int]) -> float:
        rho = self.partial_trace(subsystem_qubits)
        eig = np.linalg.eigvalsh(rho)
        eig = np.clip(eig, 1e-12, 1.0)
        eig = eig / eig.sum()
        return max(0.0, float(-np.sum(eig * np.log2(eig))))


def _ptrace_one(rho: np.ndarray, dims: List[int]) -> np.ndarray:
    dim0 = dims[0]
    dim1 = rho.shape[0] // dim0
    shape = (dim0, dim1, dim0, dim1)
    return np.einsum('iaia->ij', rho.reshape(shape))


def ghz_circuit(num_qubits: int) -> QuantumCircuit:
    qc = QuantumCircuit(num_qubits)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    qc.apply("H", h, [0])
    for target in range(1, num_qubits):
        qc.apply("CNOT", np.eye(2, dtype=np.complex128), [0, target])
    return qc


def qft_circuit(num_qubits: int) -> QuantumCircuit:
    qc = QuantumCircuit(num_qubits)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    for target in range(num_qubits):
        qc.apply("H", h, [target])
        for ctrl in range(target + 1, num_qubits):
            k = ctrl - target + 1
            theta = 2 * math.pi / (2 ** k)
            phase = np.eye(2 ** num_qubits, dtype=np.complex128)
            for i in range(2 ** num_qubits):
                bits = format(i, f"0{num_qubits}b")
                if bits[num_qubits - 1 - ctrl] == "1" and bits[num_qubits - 1 - target] == "1":
                    phase[i, i] = math.cos(theta) + 1j * math.sin(theta)
            qc.state = phase @ qc.state
            qc.gate_history.append(f"CR(k={k})")
    return qc


def grover_circuit(num_qubits: int, marked: int, iterations: int = 1) -> QuantumCircuit:
    dim = 2 ** num_qubits
    qc = QuantumCircuit(num_qubits)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    for q in range(num_qubits):
        qc.apply("H", h, [q])
    for _ in range(iterations):
        oracle_diag = np.ones((dim,), dtype=np.complex128)
        if 0 <= marked < dim:
            oracle_diag[marked] = -1
        qc.state = oracle_diag * qc.state
        qc.gate_history.append("ORACLE")
        diff = (2 / dim) * np.ones((dim, dim), dtype=np.complex128) - np.eye(dim, dtype=np.complex128)
        qc.state = diff @ qc.state
        qc.gate_history.append("DIFFUSION")
    return qc


def bell_circuit() -> QuantumCircuit:
    qc = QuantumCircuit(2)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    qc.apply("H", h, [0])
    qc.apply("CNOT", np.eye(2, dtype=np.complex128), [0, 1])
    return qc


def deutsch_jozsa_circuit(f_vals: Dict[str, int]) -> QuantumCircuit:
    n = len(next(iter(f_vals))) if f_vals else 1
    num_q = n + 1
    qc = QuantumCircuit(num_q)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    for q in range(num_q):
        qc.apply("H", h, [q])
    x = np.array([[0, 1], [1, 0]], dtype=np.complex128)
    qc.apply("X", x, [num_q - 1])
    dim = 2 ** num_q
    uf = np.eye(dim, dtype=np.complex128)
    ancilla_bit = num_q - 1
    for i in range(dim):
        bits = format(i, f"0{num_q}b")
        x_bits = bits[:-1]
        fx = f_vals.get(x_bits, 0)
        if fx:
            j = i ^ (1 << ancilla_bit)
            uf[i, i] = 0
            uf[j, i] = 1
            uf[i, j] = 1
            uf[j, j] = 0
    qc.state = uf @ qc.state
    qc.gate_history.append("U_f")
    for q in range(num_q - 1):
        qc.apply("H", h, [q])
    return qc


def bernstein_vazirani_circuit(s: str) -> QuantumCircuit:
    n = len(s)
    qc = QuantumCircuit(n)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    for q in range(n):
        qc.apply("H", h, [q])
    dim = 2 ** n
    oracle = np.eye(dim, dtype=np.complex128)
    for i in range(dim):
        bits = format(i, f"0{n}b")
        dot = sum(int(bits[j]) * int(s[j]) for j in range(n)) % 2
        oracle[i, i] = -1.0 if dot else 1.0
    qc.state = oracle @ qc.state
    qc.gate_history.append(f"ORACLE(s={s})")
    for q in range(n):
        qc.apply("H", h, [q])
    return qc


def simon_circuit(s: str) -> Tuple[QuantumCircuit, List[str]]:
    n = len(s)
    qc = QuantumCircuit(2 * n)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    for q in range(n):
        qc.apply("H", h, [q])
    dim = 2 ** (2 * n)
    oracle = np.eye(dim, dtype=np.complex128)
    for i in range(2 ** n):
        x_bits = format(i, f"0{n}b")
        fx = sum(int(x_bits[j]) * int(s[j]) for j in range(n)) % 2
        for y in range(2 ** n):
            inp = i * (2 ** n) + y
            out = i * (2 ** n) + (y ^ fx)
            if inp != out:
                oracle[inp, inp] = 0
                oracle[out, inp] = 1
                oracle[inp, out] = 0
                oracle[out, out] = 1
    qc.state = oracle @ qc.state
    qc.gate_history.append(f"ORACLE(s={s})")
    for q in range(n):
        qc.apply("H", h, [q])
    return qc, [f"y_{i}" for i in range(n)]


def quantum_teleport_circuit() -> Tuple[QuantumCircuit, Dict[str, np.ndarray]]:
    qc = QuantumCircuit(3)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    x = np.array([[0, 1], [1, 0]], dtype=np.complex128)
    qc.apply("H", h, [1])
    qc.apply("CNOT", np.eye(2, dtype=np.complex128), [1, 2])
    qc.apply("CNOT", np.eye(2, dtype=np.complex128), [0, 1])
    qc.apply("H", h, [0])
    corrections = {
        "00": ("I", np.eye(2, dtype=np.complex128), []),
        "01": ("X", x, [2]),
        "10": ("Z", np.array([[1, 0], [0, -1]], dtype=np.complex128), [2]),
        "11": ("ZX", x @ np.array([[1, 0], [0, -1]], dtype=np.complex128), [2]),
    }
    qc.memory["teleport_corrections"] = corrections
    return qc, corrections


def w_state_circuit(num_qubits: int) -> QuantumCircuit:
    qc = QuantumCircuit(num_qubits)
    if num_qubits < 2:
        raise ValueError("W-state requires at least 2 qubits")
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    ry = lambda angle: np.array([[math.cos(angle/2), -math.sin(angle/2)], [math.sin(angle/2), math.cos(angle/2)]], dtype=np.complex128)
    qc.apply("H", h, [num_qubits - 1])
    for target in range(num_qubits - 2, -1, -1):
        angle = 2 * math.asin(1 / math.sqrt(num_qubits - target))
        qc.apply("RY", ry(angle), [target])
        for ctrl in range(target + 1, num_qubits):
            qc.apply("CNOT", np.eye(2, dtype=np.complex128), [ctrl, target])
    return qc


def swap_test_circuit(state_a: np.ndarray, state_b: np.ndarray) -> QuantumCircuit:
    if state_a.shape != state_b.shape:
        raise ValueError("State shape mismatch for swap test")
    dim = state_a.shape[0]
    num_qubits = int(round(math.log2(dim)))
    if 2 ** num_qubits != dim:
        raise ValueError("State dimension must be a power of 2")
    qc = QuantumCircuit(num_qubits + 1)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    qc.apply("H", h, [0])
    zero = np.zeros((2 ** num_qubits,), dtype=np.complex128)
    zero[0] = 1.0 + 0.0j
    full = np.kron(np.array([1/math.sqrt(2), 1/math.sqrt(2)], dtype=np.complex128), zero)
    full = full + np.kron(np.array([1/math.sqrt(2), -1/math.sqrt(2)], dtype=np.complex128), state_a)
    swap = np.eye(2 ** (num_qubits + 1), dtype=np.complex128)
    for i in range(2 ** num_qubits):
        ai = 0 * (2 ** num_qubits) + i
        bi = 1 * (2 ** num_qubits) + i
        ai2 = 1 * (2 ** num_qubits) + i
        swap[ai, ai] = 0
        swap[bi, ai] = 1
        swap[ai, ai2] = 1
        swap[ai2, ai2] = 0
    qc.state = swap @ qc.state
    qc.gate_history.append("CSWAP")
    qc.apply("H", h, [0])
    return qc


def vqe_h2_circuit(theta: float) -> QuantumCircuit:
    qc = QuantumCircuit(2)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    rx = np.array([[math.cos(theta/2), -1j*math.sin(theta/2)], [-1j*math.sin(theta/2), math.cos(theta/2)]], dtype=np.complex128)
    ry = np.array([[math.cos(theta/2), -math.sin(theta/2)], [math.sin(theta/2), math.cos(theta/2)]], dtype=np.complex128)
    qc.apply("H", h, [0])
    qc.apply("H", h, [1])
    qc.apply("RY", ry, [0])
    qc.apply("RX", rx, [1])
    qc.apply("CNOT", np.eye(2, dtype=np.complex128), [0, 1])
    qc.apply("RY", ry, [0])
    qc.apply("RX", rx, [1])
    return qc


def qaoa_maxcut_circuit(graph: List[Tuple[int, int]], theta: List[float], gamma: List[float]) -> QuantumCircuit:
    if not graph:
        raise ValueError("Graph must have at least one edge")
    nodes = sorted(set(u for edge in graph for u in edge))
    num_qubits = len(nodes)
    if num_qubits < 2:
        raise ValueError("Graph must have at least 2 nodes")
    qc = QuantumCircuit(num_qubits)
    h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
    for q in range(num_qubits):
        qc.apply("H", h, [q])
    index = {node: i for i, node in enumerate(nodes)}
    for p in range(len(theta)):
        for u, v in graph:
            iu, iv = index[u], index[v]
            qc.apply("CNOT", np.eye(2, dtype=np.complex128), [iu, iv])
            rz = np.array([[np.exp(-1j * gamma[p] / 2), 0], [0, np.exp(1j * gamma[p] / 2)]], dtype=np.complex128)
            qc.apply("RZ", rz, [iv])
            qc.apply("CNOT", np.eye(2, dtype=np.complex128), [iu, iv])
        for q in range(num_qubits):
            rx = np.array([[math.cos(theta[p]/2), -1j*math.sin(theta[p]/2)], [-1j*math.sin(theta[p]/2), math.cos(theta[p]/2)]], dtype=np.complex128)
            qc.apply("RX", rx, [q])
    return qc


def apply_noise_to_state(state: np.ndarray, noise) -> np.ndarray:
    if state.size == 0:
        return state
    num_qubits = int(round(math.log2(state.shape[0])))
    mixed = state.ndim == 2 and state.shape[0] == state.shape[1]
    rho = state.copy() if mixed else QuantumCircuit.density_from_state(state)
    if noise.is_identity():
        return rho if mixed else _rho_to_state_vector(rho, state.shape)
    channel = noisy_channel(noise)
    full = np.eye(1, dtype=np.complex128)
    for _ in range(num_qubits):
        full = np.kron(full, channel)
    rho = full @ rho @ full.conj().T
    return rho if mixed else _rho_to_state_vector(rho, state.shape)


def _rho_to_state_vector(rho: np.ndarray, shape: Tuple[int, ...]) -> np.ndarray:
    eigvals, eigvecs = np.linalg.eigh(rho)
    vec = eigvecs[:, int(np.argmax(eigvals))]
    vec = vec / max(np.linalg.norm(vec), 1e-12)
    return vec.reshape(shape if len(shape) > 1 else shape)


def benchmark_algorithm(name: str, num_qubits: int, **kwargs) -> Dict[str, object]:
    if name == "ghz":
        qc = ghz_circuit(num_qubits)
    elif name == "qft":
        qc = qft_circuit(num_qubits)
    elif name == "grover":
        marked = kwargs.get("marked", 0)
        iters = kwargs.get("iterations")
        if iters is None:
            iters = max(1, int(math.pi / 4 * math.sqrt(2 ** num_qubits)))
        qc = grover_circuit(num_qubits, marked, iters)
    elif name == "bell":
        if num_qubits != 2:
            raise ValueError("bell requires 2 qubits")
        qc = bell_circuit()
    elif name == "teleport":
        if num_qubits != 3:
            raise ValueError("teleport requires 3 qubits")
        qc, _ = quantum_teleport_circuit()
        h = np.array([[1, 1], [1, -1]], dtype=np.complex128) * (1 / math.sqrt(2))
        qc.apply("H", h, [0])
    elif name == "deutsch_jozsa":
        f_type = kwargs.get("f", "balanced")
        n = num_qubits - 1
        f_vals = {}
        if f_type == "constant":
            for i in range(2 ** n):
                f_vals[format(i, f"0{n}b")] = 0
        else:
            for i in range(2 ** n):
                f_vals[format(i, f"0{n}b")] = sum(int(b) for b in format(i, f"0{n}b")) % 2
        qc = deutsch_jozsa_circuit(f_vals)
    elif name == "bernstein_vazirani":
        s = kwargs.get("s", "101")
        if len(s) > num_qubits:
            raise ValueError("s length cannot exceed num_qubits")
        qc = bernstein_vazirani_circuit(s)
    elif name == "simon":
        s = kwargs.get("s", "11")
        if len(s) >= num_qubits:
            raise ValueError("simon requires num_qubits > len(s)")
        qc, _ = simon_circuit(s)
    elif name == "w_state":
        qc = w_state_circuit(num_qubits)
    elif name == "swap_test":
        raw_a = kwargs.get("state_a")
        raw_b = kwargs.get("state_b")
        if raw_a is None or raw_b is None:
            raise ValueError("swap_test requires --state-a and --state-b")
        a = np.array([complex(x.strip()) for x in raw_a.split(",")], dtype=np.complex128)
        b = np.array([complex(x.strip()) for x in raw_b.split(",")], dtype=np.complex128)
        qc = swap_test_circuit(a, b)
    elif name == "vqe_h2":
        theta = kwargs.get("theta", 0.1)
        if isinstance(theta, list):
            theta = theta[0] if theta else 0.1
        qc = vqe_h2_circuit(theta)
    elif name == "qaoa_maxcut":
        graph = kwargs.get("graph", [(0, 1)])
        theta = kwargs.get("theta", [0.1])
        gamma = kwargs.get("gamma", [0.2])
        if not isinstance(theta, list):
            theta = [theta]
        if not isinstance(gamma, list):
            gamma = [gamma]
        if len(theta) != len(gamma):
            raise ValueError("qaoa_maxcut requires equal length theta and gamma")
        qc = qaoa_maxcut_circuit(graph, theta, gamma)
    else:
        raise ValueError(f"Unknown algorithm: {name}")
    noise_spec = kwargs.get("noise")
    if noise_spec is not None:
        qc.state = apply_noise_to_state(qc.state, noise_spec)
    counts = qc.measure(shots=kwargs.get("shots", 1024), seed=kwargs.get("seed"))
    out: Dict[str, object] = {
        "algorithm": name,
        "num_qubits": num_qubits,
        "depth": len(qc.gate_history),
        "gate_counts": {g: qc.gate_history.count(g) for g in dict.fromkeys(qc.gate_history)},
        "shots": kwargs.get("shots", 1024),
        "counts": counts,
    }
    if name in {"ghz", "bell"}:
        ent = qc.entanglement_entropy([0])
        ent = max(0.0, min(math.log2(qc.dim), float(ent)))
        out["entanglement_entropy"] = float(ent)
    if name == "teleport":
        out["corrections"] = {k: v[0] for k, v in qc.memory.get("teleport_corrections", {}).items()}
    if name == "deutsch_jozsa":
        c0 = counts.get("0" * (num_qubits - 1), 0)
        out["determination"] = "constant" if c0 > sum(counts.values()) / 2 else "balanced"
    if name == "bernstein_vazirani":
        out["hidden_string"] = (max(counts, key=counts.get) if counts else "")[-len(kwargs.get("s", "101")) :]
    if name == "simon":
        out["top_register"] = (max(counts, key=counts.get) if counts else "")[-len(kwargs.get("s", "11")) :]
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Quantum simulator")
    parser.add_argument("--algorithm", default="bell", choices=["ghz", "qft", "grover", "bell", "teleport", "deutsch_jozsa", "bernstein_vazirani", "simon", "w_state", "swap_test", "vqe_h2", "qaoa_maxcut"])
    parser.add_argument("--qubits", type=int, default=2)
    parser.add_argument("--marked", type=int, default=0)
    parser.add_argument("--iterations", type=int, default=None)
    parser.add_argument("--shots", type=int, default=1024)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--f", default="balanced")
    parser.add_argument("--s", default="101")
    parser.add_argument("--state-a", default=None)
    parser.add_argument("--state-b", default=None)
    parser.add_argument("--theta", default="0.1", help="Comma-separated float parameters for QAOA/VQE")
    parser.add_argument("--gamma", default="0.2", help="Comma-separated float parameters for QAOA")
    parser.add_argument("--graph", default="0,1", help="Comma-separated node indices forming one edge")
    parser.add_argument("--noise", action="store_true", help="Use a standard noise model when supported")
    args = parser.parse_args()
    if args.qubits < 1 or args.qubits > 20:
        print("qubits must be between 1 and 20")
        return 2
    kwargs = {
        "marked": args.marked,
        "iterations": args.iterations,
        "shots": args.shots,
        "seed": args.seed,
        "f": args.f,
        "s": args.s,
        "state_a": args.state_a,
        "state_b": args.state_b,
        "theta": [float(x) for x in args.theta.split(",") if x.strip()] if args.theta is not None else [],
        "gamma": [float(x) for x in args.gamma.split(",") if x.strip()] if args.gamma is not None else [],
        "graph": [tuple(int(x) for x in edge.split(",")) for edge in args.graph.split(" ") if edge.strip()],
    }
    if args.noise:
        from noise import NoiseModel
        kwargs["noise"] = NoiseModel(bit_flip_probability=0.01, phase_flip_probability=0.01, depolarizing_probability=0.05, amplitude_damping_gamma=0.0)
    payload = benchmark_algorithm(args.algorithm, args.qubits, **kwargs)
    print(json.dumps(payload, ensure_ascii=False, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
