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
linked_files:
  scripts:
    - scripts/simulate.py
    - scripts/noise.py
    - scripts/test_quantum.py
    - scripts/run_tests.sh
  references:
    - references/algorithms.md
    - references/backends.md
    - references/verification-notes.md
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

After any change to algorithm dispatch, `argparse` choices, or `test_quantum.py`:
- `python scripts/test_quantum.py`
- If this fails, the work is unverified; repair before reporting done.

## Rules

- Prefer zero-cost NumPy over optional frameworks.
- Default to density matrix under noisy runs for mixed-state fidelity.
- Fail loudly on missing optional backends rather than silent fallback.

## Verification

Use `scripts/run_tests.sh` as the canonical regression entrypoint.
Do not claim completion unless the most recent run exits 0 with fresh passing evidence. After any change to algorithm dispatch, `argparse` choices, or `test_quantum.py`, rerun `bash scripts/run_tests.sh`; if it fails, repair before reporting done.

## Metric extension

For new state-level metrics beyond `fidelity`, follow `scripts/noise.py` and `scripts/test_quantum.py` `test_noise_metrics()` as the template.
Reference: `references/noise-metrics.md`.

## Regression hygiene

- Preserve compile + algorithm sweep + noise metrics coverage in one run when changing CLI tests.
- Keep qubit-override cases for algorithms with strict minimums in test automation.
- When adding algorithms, update `argparse` choices, benchmark dispatch, circuit builders, and test cases together.
- Keep function signatures in sync between dispatch, circuit builder, and tests; mismatched arity is a recurring failure mode after expansion.
- Use `np.exp` over `math.exp` when building complex-dtype phase matrices; `math.exp` can raise `TypeError: must be real number, not complex` in that path.

## Pitfalls / Debugging Notes

### Teleport qubit handling
`teleport` currently models 3 qubits. Accept `>= 3` and pad extra qubits with identity gates; do not hard-fail on `num_qubits != 3`.

### CLI argparse completeness
Every supported algorithm must appear in `argparse` `choices`. Omitting one breaks the CLI while internal benchmark paths still work.

### `fidelity()` / `state_sse()` shape dispatch
When extending fidelity or SSE, prefer explicit ndim/2D checks over chained tuple equality. If refactoring density-matrix branches, complete `sqrt_rho_a`, `prod`, and `sqrt_prod` before `np.sqrt`/trace/einsum operations.

### Test selection hygiene
`test_quantum.py` should only cover implemented algorithms. Do not add placeholder cases for unimplemented algorithms; they will fail and poison the suite.

### Verification
Use `scripts/test_quantum.py` as the single-source regression check: compile + algorithm sweep + CLI noise metrics in one pass.
