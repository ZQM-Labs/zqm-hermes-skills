# Ollama fleet stability probe + swarm-blackboard LEAF convention

## Dual-probe stability check (detect flapping model counts)
Question: are reachable nodes' model counts STABLE across repeated probes (no flapping)?
Method: hit `GET /api/tags` twice, ~5s apart, compare `(model_count, total_GB)`.

### Inline one-liner (MSYS bash, per node)
```
curl -s --max-time 5 http://<ip>:11434/api/tags | python -c \
  "import json,sys; d=json.load(sys.stdin); print(len(d['models']), round(sum(m['size'] for m in d['models'])/1e9,2))"
```
Run twice with `sleep 5` between. `size` is BYTES → divide by 1e9 for GB.

### Re-runnable script
`scripts/ollama_stability_probe.py [ip ...] [--gap 5]` (stdlib only; defaults to the 4
ZQM nodes). Prints per-node Run1 / Run2 / STABLE|MISMATCH|UNREACHABLE.

Interpretation: identical (count, GB) both runs ⇒ STABLE. Any drift ⇒ flapping →
investigate Ollama reload / a concurrent `ollama pull` on that node.

## Swarm-blackboard LEAF convention (multi-agent coordination)
For multi-agent swarm runs (dir `swarm/YYYYMMDD_swarmN/`), findings land in
`blackboard.md`. Each independent probe writes a `### LEAF <X> — <topic>` block under
`## ROUND 1 FINDINGS`, resolves the relevant open question (e.g. Q3 = stability), and
states PROVEN (live output shown). Always append the machine-truth (HTTP code, seconds)
separately from interpretation, and never assume a dark node's model list.

## Live result — 2026-07-11 (dual probe, ~5s apart)
| Node | Run 1 | Run 2 | Stable |
|------|-------|-------|--------|
| N1 (.218) | 2 / 29.16 GB | 2 / 29.16 GB | YES |
| N2 (.21)  | 8 / 55.41 GB | 8 / 55.41 GB | YES |
| N4 (.215) | 45 / 451.6 GB | 45 / 451.6 GB | YES |

Q3 RESOLVED: all three reachable nodes are STABLE (no flapping); counts/GB match the
2026-07-10 fan-out seed exactly. N3 (.46) was out of scope (Q1/Q2 localhost-bound target).
