---
name: quantum-computing
description: Quantum circuit simulation, noise modeling, and algorithm benchmarking on local Windows. Use for quantum simulation, circuit execution, algorithm design, and entropy/harmony measurement of quantum states.
version: 1.0
category: software-development/quantum-computing
tags: [quantum-computing, simulation, noise-modeling, algorithms]
required_commands: []
required_environment_variables: []
missing_required_environment_variables: []
missing_required_commands: []
setup_needed: false
setup_skipped: false
readiness_status: available
linked_files: scripts=scripts/simulate.py,scripts/noise.py,scripts/test_quantum.py,scripts/run_tests.sh references=references/algorithms.md,references/backends.md,references/verification-notes.md
---

# Quantum Computing

Local quantum circuit simulation with physics-grounded noise and algorithm benchmarking.

## Usage

`python scripts/simulate.py --help`

## Steps

1. Choose backend: `numpy` (default), `qiskit-aer`, or `jax`.
2. Build circuit via `QuantumCircuit(num_qubits)`.
3. Apply gates from `simulate.py`.
4. Apply noise via `noise.py`.
5. Run measurement with shots.
6. Inspect results via `scripts/noise.py`.

## Output

- stdout JSON with counts, depth, gate_counts, shots.
- optional raw state vector if requested.

## Verification

Use `scripts/test_quantum.py` as the single-source regression check: compile + algorithm sweep + CLI noise metrics in one pass.
Do not claim completion unless the most recent run exits 0 with fresh passing evidence. After any change to algorithm dispatch, `argparse` choices, or `test_quantum.py`, rerun `python scripts/test_quantum.py`; if it fails, repair before reporting done.
After edits, verify in this order: `python -m py_compile scripts/simulate.py scripts/noise.py scripts/test_quantum.py`, then `python scripts/test_quantum.py`.

## Rules

- Prefer zero-cost NumPy over optional frameworks.
- Default to density matrix under noisy runs for mixed-state fidelity.
- Fail loudly on missing optional backends rather than silent fallback.

## Regression hygiene

- Preserve compile + algorithm sweep + noise metrics coverage in one run when changing CLI tests.
- Keep qubit-override cases for algorithms with strict minimums in test automation.
- When adding algorithms, update `argparse` choices, benchmark dispatch, and test cases together.

## Pitfalls / Debugging Notes

### Teleport qubit handling
`teleport` currently models 3 qubits. Accept `>= 3` and pad extra qubits with identity gates; do not hard-fail on `num_qubits != 3`.

### CLI argparse completeness
Every supported algorithm must appear in `argparse` `choices`. Omitting one breaks the CLI while internal benchmark paths still work.

### `fidelity()` shape dispatch
When extending `fidelity()`, prefer explicit ndim/2D checks over chained tuple equality. If refactoring the density-matrix branch, ensure `sq @ rho_b @ sq` and `prod` are computed before `np.sqrt(prod)`.

### Test selection hygiene
`test_quantum.py` should only cover implemented algorithms. Do not add placeholder cases for unimplemented algorithms; they will fail and poison the suite.