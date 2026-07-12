#!/usr/bin/env python3
"""Standalone verification for quantum-computing skill."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent / "quantum-computing"
SCRIPTS = ROOT / "scripts"


def run_sim(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPTS / "simulate.py"), *args],
        capture_output=True,
        text=True,
        timeout=120,
    )


def run_noise(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPTS / "noise.py"), *args],
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_compile() -> dict:
    cp = subprocess.run(
        [sys.executable, "-m", "py_compile", str(SCRIPTS / "simulate.py"), str(SCRIPTS / "noise.py")],
        capture_output=True,
        text=True,
    )
    return {"returncode": cp.returncode, "stdout": cp.stdout.strip(), "stderr": cp.stderr.strip()}


def test_algorithms() -> dict:
    results: Dict[str, dict] = {}
    cases = [
        ("ghz", ["--algorithm", "ghz", "--json"], {}),
        ("qft", ["--algorithm", "qft", "--json"], {}),
        ("grover", ["--algorithm", "grover", "--json"], {}),
        ("bell", ["--algorithm", "bell", "--json"], {"qubits": 2}),
        ("teleport", ["--algorithm", "teleport", "--json"], {"qubits": 3}),
    ]
    for name, base_args, overrides in cases:
        args = list(base_args)
        q = overrides.get("qubits")
        if q is not None:
            args = ["--algorithm", name, "--qubits", str(q), "--json"]
        cp = run_sim(*args)
        results[name] = {"returncode": cp.returncode, "ok": cp.returncode == 0, "cmd": args}
        if cp.returncode != 0:
            results[name]["stderr"] = cp.stderr.strip()
    return results


def test_noise_metrics() -> dict:
    # Regression: CLI passes 1D state vectors; must not crash.
    cp = run_noise("--bit-flip", "0.1", "--phase-flip", "0.2", "--compare", "fidelity", "--state-a", "1,0", "--state-b", "0,1")
    out = {"returncode": cp.returncode, "stdout": cp.stdout.strip(), "stderr": cp.stderr.strip()}
    out["ok"] = cp.returncode == 0 and "fidelity=" in cp.stdout
    # Non-orthogonal states should still produce a bounded numeric fidelity.
    cp2 = run_noise("--compare", "fidelity", "--state-a", "1,0", "--state-b", "0.70710678,0.70710678")
    out2 = {"returncode": cp2.returncode, "stdout": cp2.stdout.strip(), "stderr": cp2.stderr.strip()}
    out2["ok"] = cp2.returncode == 0 and "fidelity=" in cp2.stdout
    # SSE metric must emit a non-negative numeric value for 1D inputs.
    cp3 = run_noise("--compare", "sse", "--state-a", "1,0", "--state-b", "0.70710678,0.70710678")
    out3 = {"returncode": cp3.returncode, "stdout": cp3.stdout.strip(), "stderr": cp3.stderr.strip()}
    out3["ok"] = cp3.returncode == 0 and "sse=" in cp3.stdout
    res = {"cli_1d_states": out, "nonorthogonal_states": out2, "sse": out3}
    return res


def test_new_algorithms() -> dict:
    cases = [
        ("bernstein_vazirani", ["--algorithm", "bernstein_vazirani", "--qubits", "5", "--json"]),
        ("simon", ["--algorithm", "simon", "--qubits", "5", "--json"]),
        ("w_state", ["--algorithm", "w_state", "--qubits", "3", "--json"]),
        ("swap_test", ["--algorithm", "swap_test", "--qubits", "2", "--state-a", "1,0", "--state-b", "0.70710678,0.70710678", "--json"]),
        ("vqe_h2", ["--algorithm", "vqe_h2", "--qubits", "2", "--json"]),
        ("qaoa_maxcut", ["--algorithm", "qaoa_maxcut", "--qubits", "2", "--graph", "0,1", "--theta", "0.1", "--gamma", "0.2", "--json"]),
    ]
    results = {}
    for name, args in cases:
        cp = run_sim(*args)
        results[name] = {"returncode": cp.returncode, "ok": cp.returncode == 0, "cmd": args}
        if cp.returncode != 0:
            results[name]["stderr"] = cp.stderr.strip()
    return results


def main() -> int:
    results = {
        "compile": test_compile(),
        "algorithms": test_algorithms(),
        "noise_metrics": test_noise_metrics(),
        "new_algorithms": test_new_algorithms(),
    }
    all_ok = (
        results["compile"]["returncode"] == 0
        and all(v["ok"] for v in results["algorithms"].values())
        and all(v["ok"] for v in results["noise_metrics"].values())
        and all(v["ok"] for v in results["new_algorithms"].values())
    )
    print(str(results))
    return 0 if all_ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
