---
name: entropy-harmony-scales
description: >
  Three entropy/harmony calculators:
  (1) data entropy — Shannon entropy over files/streams with byte/char/token samplers;
  (2) system harmony — config/repo/service coherence scoring via YAML parse, duplicate,
     missing-reference, circular-dependency, and port-owner checks;
  (3) creative/audio harmony — tonal entropy from audio via chroma/spectral features,
     plus chordal dissonance/consonance scoring.
  Use when asked for entropy, harmony, disorder, coherence, compactness, entropy-score,
  system-hygiene, or chordal/tonal metrics.
version: 0.1.0
category: software-development
tags: [entropy, harmony, data, system-harmony, audio]
required_commands: []
required_environment_variables: []
missing_required_environment_variables: []
missing_required_commands: []
setup_needed: false
setup_skipped: false
readiness_status: available
linked_files:
  scripts:
    - scripts/data_entropy.py
    - scripts/system_harmony.py
    - scripts/audio_harmony.py
    - scripts/entropy_harmony_suite.py
---

# Entropy & Harmony Scales

Quantify disorder across data, systems, and music. Run individual samplers or an `all` sweep.

## 1) Data entropy

### CLI
```bash
python scripts/data_entropy.py <path> [--unit B|C|W|S] [--sample-bytes N] [--human]
```

### Rules
- Read raw bytes up to `--sample-bytes` (default 256 KiB).
- Split into equal bins by `--unit`:
  - `B` byte values (256 bins)
  - `C` lower-case ASCII a-z
  - `W` whitespace vs non-whitespace (2 bins)
  - `S` shell-significant bytes
- Shannon entropy:
```math
H = -\sum p_i \log_2 p_i
```
- Report `entropy_bits`, `normalized_entropy` in `[0,1]` where 1 = perfectly uniform, plus `effective_bins` and `chi2` if useful.

### Behaviour
- If `--human`, print one-line human summary + JSON to stdout.
- Non-existent path -> raise with clear message.
- Symlinks -> follow and hash contents; identical-size spoofs OK.

## 2) System harmony

### CLI
```bash
python scripts/system_harmony.py <root> [--checks yaml,dup,dep,port,git] [--human]
```

### Checks
- `yaml`: parse all `.yaml`/`.yml` under `root`.
- `dup`: duplicate `node_modules/<pkg>/package.json` version strings + identical hash.
- `dep`: missing references / circular A->B->A inferences across `package.json`/`pyproject.toml` (edges only).
- `port`: `netstat`/`Get-NetTCPConnection` equivalent port conflicts owned by named processes.
- `git`: repo cleanliness: detached HEAD, merge conflicts, submodule issues.

### Scoring
- Base 100.
- Deduct per issue by severity: Critical -25, High -15, Medium -5, Low -2.
- Cap floor at 0. Report inputs/checks, issues table, final `harmony_score`.

## 3) Creative / audio harmony

### CLI
```bash
python scripts/audio_harmony.py <file> [--human] [--chroma-bins 12] [--fft 2048]
```

### Features
- Require `numpy`.
- Load audio if path exists and has audio stream.
- Compute chroma vector + mean spectral rolloff + tempo proxy via onset strength envelope rate.
- Tonal entropy: Shannon entropy over 12 chroma bins normalized to [0,1].
- Chordal dissonance proxy: ratio of energy in minor 2nds/7ths intervals vs octaves/perfect 5ths.

### Behaviour
- Without `numpy`, fallback to file-size-based creative entropy proxy from data sampler.
- Human flag -> human-readable summary + JSON.

## Cross-cutting

### JSON output
All CLIs support:
- `--json` -> only JSON to stdout
- `--human` -> human summary + optional JSON footer block
- default -> human summary only

### Limits / Windows quirks
- Cap parser/file stream reads to 256 KiB for entropy.
- When checking ports on Windows 10, prefer `Get-NetTCPConnection` via `powershell` only if `netstat` flags differ; otherwise skip.
- No network egress.

## Quick: all-of-the-above

```bash
python scripts/entropy_harmony_suite.py --path <target> [--human]
```

Sequences 2 then 3 if path is dir; if path has audio extension or is detected audio, run 3 directly; otherwise synthesize a proxy from 1.

## Windows / CI notes

- `scripts/run_tests.sh` should invoke explicit Python 3.12: `C:\Users\zqmco\AppData\Local\Programs\Python\Python312\python.exe -m pytest ...`.
- Session teardown on Windows can lock `state.db`; close the DB before `shutil.rmtree()` and use a short retry loop on `PermissionError`.
- `HOME` monkeypatching affects `os.path.expanduser("~")` on Windows. Prefer explicit `os.environ.get("HOME")` with fallback in test-sensitive helpers.

## Verification

```bash
cd skills/entropy-harmony-scales
python -m py_compile scripts/*.py
# optional
python scripts/data_entropy.py README.md --human
python scripts/system_harmony.py . --checks yaml,gib --human
python scripts/audio_harmony.py  --human   # fallback proxy
python scripts/entropy_harmony_suite.py --path . --human
```
