# Backends

Use this reference when selecting a simulation backend.

## numpy
- Default backend.
- State vector relies on complex128 ops via NumPy.
- Density-matrix ops supported.
- Feature parity: state vector, measurement, density, partial trace.

## optional
- `qiskit-aer` preferred if installed; otherwise `numpy`.
- `jax` experimental; no verification on this host.
