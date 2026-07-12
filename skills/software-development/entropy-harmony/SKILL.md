---
name: entropy-harmony
description: Unified entropy/harmony measurement scales, tradeoff model, and generative rules across statistical mechanics, music, communication, security, and software systems.
version: 1.0
category: software-development
tags: [entropy, harmony, measurement, thermodynamics, music, security, software]
required_commands: []
required_environment_variables: []
missing_required_environment_variables: []
missing_required_commands: []
setup_needed: false
setup_skipped: false
readiness_status: available
linked_files:
  scripts:
    - scripts/entropy_harmony.py
---

# Entropy / Harmony Scales

Use this skill when you need to model, score, or tune disorder/order in any system.

## Protocol

1. Identify target domain from: thermodynamics, music, communication, security, or software.
2. Choose scales below.
3. Compute tradeoff score with `scripts/entropy_harmony.py`.
4. Suggested starting points:
   - high-reliability target: harmony 0.75-0.95
   - exploratory/research target: harmony 0.35-0.65
   - adversarial target: entropy ≥ 0.60

## Scales

### 1. Thermodynamics / Statistical Mechanics

| Name | Formula / Mapping | Range | Meaning |
|---|---|---|---|
| Shannon entropy per symbol | H = -Σ p_i log2(p_i) | 0 to log2(n) | uncertainty |
| Normalized entropy | H_n = H / log2(n) | 0.00–1.00 | 0.00 = uniform, 1.00 = singleton |
| Thermodynamic entropy proxy | S' = 1 - H_n | 0.00–1.00 | order/energy-structure proxy |
| Harmony | H_harm = S' | 0.00–1.00 | lower entropy → higher harmony |
| Temperature | T = 1 - H_harm | 0.00–1.00 | normalized unrest |
| Phase stability | stable if H_n < 0.45 | bool | below critical entropy |

### 2. Music / Rhythm / Pitch

| Name | Formula / Mapping | Range | Meaning |
|---|---|---|---|
| Pitch entropy | H_p = -Σ p_i log2(p_i), bins over 12-TET classes | 0.00–1.00 | harmonic surprise |
| Rhythmic entropy | H_r = -Σ p_i log2(p_i), bins over onset density | 0.00–1.00 | syncopation/rest |
| Normalized total entropy | H_m = (H_p + H_r) / 2 | 0.00–1.00 | overall unpredictability |
| Dissonance | D = 0.60 * H_p + 0.40 * H_r | 0.00–1.00 | tension |
| Harmony | M_harm = 1 - D | 0.00–1.00 | consonance / resolution |
| Tension bands | very low < 0.25, low 0.25–0.40, neutral 0.40–0.60, tense 0.60–0.75, extreme ≥ 0.75 | bool | style recommendation |

### 3. Communication / Information

| Name | Formula / Mapping | Range | Meaning |
|---|---|---|---|
| Message entropy | H_m = -Σ p_i log2(p_i) | 0.00–1.00 | information surprise |
| Redundancy | R = 1 - H_m | 0.00–1.00 | predictability / harmony |
| Channel capacity tension | C_t = 1 - R if load > 0.82 * capacity else 0 | 0.00–1.00 | saturation risk |
| Harmony | I_harm = R | 0.00–1.00 | legible/stable message |

### 4. Security / Adversarial Systems

| Name | Formula / Mapping | Range | Meaning |
|---|---|---|---|
| Attacker search entropy | H_a = -Σ p_i log2(p_i), over guessable secrets space | 0.00–1.00 | attack noise |
| Variance dispersion | V_d = normalized min-max variance of observable signals | 0.00–1.00 | footprint |
| Adversarial entropy | E_adv = 0.55 * H_a + 0.45 * V_d | 0.00–1.00 | exploitability |
| Harmony | A_harm = 1 - E_adv | 0.00–1.00 | defense coherence |
| Drift alert | E_adv > 0.60 | bool | probable recon window |

### 5. Software / Systems

| Name | Formula / Mapping | Range | Meaning |
|---|---|---|---|
| Coupling entropy | H_c = normalized module coupling variance | 0.00–1.00 | architecture surprise |
| Cognitive complexity | C_c = normalized cyclomatic/complexity density | 0.00–1.00 | mental load |
| Failure-mode entropy | H_f = distinct failure signals vs coverage ratio | 0.00–1.00 | operational surprise |
| System entropy | S_s = 0.40 * H_c + 0.35 * C_c + 0.25 * H_f | 0.00–1.00 | structural disorder |
| Harmony | S_harm = 1 - S_s | 0.00–1.00 | codebase order |
| Refactor trigger | S_harm < 0.45 | bool | recommended intervention |

## Unified Tradeoff Model

Base state:
- state = {"entropy": H_n, "harmony": H_harm, "temperature": T}
- H_harm ∈ [0.00, 1.00]
- T = 1 - H_harm

Optimization modes:
- minimize entropy, maximize harmony → use harmony target constraint
- minimize temperature → minimize both entropy and energy leakage
- maximize entropy → maximize uncertainty/discovery

Energy penalty:
- E = H_n + (1 - H_harm)^2
- Use for comparing states of equal entropy

Interaction rule:
- diagonal energy: ΔE = |H_n - (1 - H_harm)| + 0.25 * |T - H_n|
- smaller ΔE implies more self-consistent system state

## Generative Rules

Rule 1: If harmony target is set, constrain entropy below 1 - target.
Rule 2: If temperature must stay below threshold, avoid uniform distributions that maximize entropy without useful freedom.
Rule 3: In adversarial or creative tasks, prefer state with entropy in [0.35, 0.75], harmony in [0.25, 0.65].
Rule 4: Use energy penalty E to choose between multiple candidate distributions.
Rule 5: log only pairs with delta > 0.05 relative to prior state.

## Cross-Domain Mappings

| Domain | Entropy | Harmony | Optimal Zone |
|---|---|---|---|
| physics | H_n | S' | 0.15–0.40 / phase-stable |
| music | D | M_harm | 0.60–0.85 / consonant |
| message | H_m | R | 0.05–0.25 / redundant-stable |
| security | E_adv | A_harm | 0.25–0.55 / warn-zone |
| software | S_s | S_harm | 0.35–0.60 / refactor-zone |

## Verification

Run `python scripts/entropy_harmony.py --self-test` to validate formulas against known constants.

## Output Contract

Return:
- domain
- entropy ∈ [0.00, 1.00]
- harmony ∈ [0.00, 1.00]
- temperature = 1 - harmony
- energy penalty E
- interval: harmonic | balanced | tense
- action: preserve | tune | refactor | harden
- recommended delta toward target harmony if target provided
