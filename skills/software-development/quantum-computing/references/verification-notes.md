# Verification Notes

Class-level notes for maintaining and extending the quantum-computing skill.

## Verified runners
- `python -m py_compile scripts/simulate.py scripts/noise.py scripts/test_quantum.py`
- `python scripts/test_quantum.py`

## Verified algorithms
- `ghz`
- `qft`
- `grover`
- `bell`
- `teleport`
- `deutsch_jozsa`
- `bernstein_vazirani`
- `simon`

## Verified metrics
- `fidelity(state_a, state_b)`
- `counts_entropy(counts)`
- `counts_harmony(counts, expected_top)`
- CLI fidelity regression: 1D state vectors accepted, bounded `0..1`
- CLI fidelity regression: non-orthogonal states accepted, bounded `0..1`

## Platform notes
- Host: Windows 10
- NumPy is the default/verified backend
- Optional backends `qiskit-aer` and `jax` are documented but not required
- Prefer zero-cost fixes over adding dependency requirements

## Smoke checks
- `python scripts/simulate.py --algorithm <name> --json`
- `python scripts/noise.py --compare fidelity --state-a "1,0" --state-b "0,1" --bit-flip 0.1 --phase-flip 0.2`

## Algorithm-specific notes
- `bell` requires `--qubits 2`
- `teleport` requires `--qubits >= 3`; extra qubits are padded with identity gates
- `deutsch_jozsa` uses `--f {constant,balanced}`
- `bernstein_vazirani` uses `--s <binary>` for hidden string; exposes `hidden_string`
- `simon` uses `--s <binary>` for hidden string; exposes `top_register`; requires `num_qubits > len(s)`

## Known harness pitfalls
- `test_quantum.py` must pass algorithm names via `--algorithm`, not positionally.
- Only test implemented algorithms; placeholder cases for unimplemented algorithms poison the suite.
- When changing algorithm dispatch, update `argparse` choices, `benchmark_algorithm()` cases, and `test_quantum.py` together.

## Fidelity regression boundaries
- CLI `noise.py` supplies 1D vectors; `fidelity()` must reshape to density matrices before sqrt/trace.
- Validate both orthogonal and non-orthogonal inputs; output must be numeric and bounded `0..1`.
- When refactoring density-matrix branches, ensure `sq = np.sqrt(rho_a); prod = sq @ rho_b @ sq` and `np.sqrt(prod)` are computed before `np.trace`.
