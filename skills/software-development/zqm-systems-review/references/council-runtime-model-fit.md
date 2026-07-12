# Council Runtime Model-Fit Gate
## Hard rule for this workstation
- Available RAM: ~16 GB; available headroom taxed by OS and apps.
- 36B-class Ollama models here exceed practical memory budget; expect `/api/generate` timeouts even at `max_tokens=8`.
- Therefore council must pass this gate before reporting usable deliberation:
  1. Confirm model inventory via `/api/tags`.
  2. Directly probe `/api/generate` for timeout/failure.
  3. If timeout occurs, classify council as **degraded runtime** regardless of transport health.
  - Approved fix paths on this host:
    - Preferred: pull `qwen3:8b` (`ollama pull qwen3:8b`), rerun `/council/round` + `/council/last`, and keep `qwen3.6:latest` on disk.
    - Contingency: if coexistence is later rejected for operational simplicity, delete `qwen3.6:latest` (`ollama rm qwen3.6:latest`) to reclaim disk/RAM and eliminate accidental fallback.
  - Do not declare coexistence impossible until both verifications have been attempted:
    1. `/api/tags` shows both models listed.
    2. `/council/last` `text` fields are populated after `/council/round` with `qwen3:8b`.

## Verified host state
- Ollama version: 0.31.2
- Confirmed-bad model: `qwen3.6:latest`, Q4_K_M, ~23.9 GB; **can time out on `/api/generate` even though `/api/tags` lists it**
- Confirmed-good model: `qwen3:8b`, ~5 GB, 16 GB RAM host
- `council_engine.py` now prefers `ZQM_COUNCIL_MODEL` / `OLLAMA_MODEL` / `qwen3.6:latest`, with adaptive fallback to any installed model; cached discovery; uses resolved model for stream and non-stream paths
- After switching to `qwen3:8b`, rerun the generation probe and `/council/last` text inspection before declaring utilization successful.

## qwen3-family parsing pitfall
- Symptom: `/council/round` succeeds, `/council/last` shows `message_count > 0`, but all `text` fields are `""`.
- Root cause: Qwen3-family models in Ollama 0.31.x split reasoning from completion; internal chain-of-thought is returned in a top-level `thinking` field, while `response` can be empty when `num_predict` is too small or when reasoning is still active.
- First probe: call `POST /api/generate` directly and inspect full JSON keys for `thinking`.
- Fix path: update the consuming code to prefer `thinking` when `response` is empty, or raise `num_predict` / disable reasoning if the wrapper expects completion-only output.
- Do not repeat model-swap / capacity optimizations until the `thinking` vs `response` mismatch is ruled out; empty deliberation is almost always a parsing problem first, hardware second.

## Evidence capture order
1. Runtime model inventory size and quantization.
2. Direct generation probe outcome and inspect for `thinking` field.
3. Council topic/round response + `/council/last` populated-text confirmation.
4. After any model-fit fix, rerun generation probe and `/council/last` before declaring council restored.

## Empty deliberation guard
- `/council/round` can return success with populated `message_count` but empty `text` fields.
- Empty `text` across all turns means backend generation did not return content in the expected field, not that deliberation finished cleanly.
- Do not report council utilization successful when `/council/last` `text` arrays are empty.