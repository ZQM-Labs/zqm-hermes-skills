#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python -m py_compile simulate.py noise.py test_quantum.py
python test_quantum.py
