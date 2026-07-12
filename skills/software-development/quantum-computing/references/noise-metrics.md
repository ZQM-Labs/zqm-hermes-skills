# Noise Metrics Reference

Current metric surface in `scripts/noise.py`:
- `state_sse(state_a, state_b)` -> float
- `fidelity(state_a, state_b)` -> float in [0, 1]

CLI entrypoint:
- `python scripts/noise.py --compare sse|fidelity --state-a <csv> --state-b <csv>`

Extending metrics:
- Add a top-level helper next to `state_sse`/`fidelity`.
- Add an `args.compare == "<name>"` block in `main()`.
- Add a regression block in `test_noise_metrics()` inside `scripts/test_quantum.py`.

