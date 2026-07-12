# Escalating-timeout generate probe — cold-load vs PERMANENT hang (Ollama)

## Why a single timeout is unsafe
A one-shot `/api/generate` with a fixed `--max-time` conflates two very different states:
1. **Slow cold-load** — model loads and answers, just takes a while (fine; not a fault).
2. **Permanent hang** — GPU/VMM wedge; never answers (real fault, needs recovery).

If the fixed timeout sits between them (e.g. 45s), a slow-but-healthy model times out and
you wrongly declare a HARD HANG → you bounce the GPU / restart Ollama for no reason.

This happened in the 2026-07-11 swarm LEAD pass: it called Node-4 (.215, qwen3:32b) a
"HARD HANG (000@45s)" from a single 45s shot. The LEAF B ESCALATING re-probe returned
**200@35.81s** — i.e. healthy, slow cold-load. The "fault migration N2→N4" headline was a
FALSE POSITIVE.

## Method (escalating)
1. `GET /api/tags` (5s) → confirm service up, grab `models[0].name`.
2. `POST /api/generate {"model":<name>,"prompt":"ping","stream":false}` at **20s**.
   - 200 → HEALTHY (cold-load fine).
   - 000 (timeout) → escalate to **45s**.
3. At 45s:
   - 200 → **SLOW COLD-LOAD, NOT a hang** (model loaded in <45s).
   - 000 → **PERMANENT HANG / inference wedge** → recovery needed.

## qwen3:32b / qwq:32b "thinking" gotcha (the major false-hang source)
- These 32B models emit FULL chain-of-thought. Even a "ping" prompt yields 100+ tokens,
  so full (non-capped) generation runs **25-50s**.
- Control shot: same model, `num_predict:1` → loads + answers in **~0.5s** (N4 example:
  0.57s, load 267ms). Fast control + slow full-gen = SLOW MODEL, not a wedge.
- Rule: before labeling any 32B+ thinking model "hung", run the escalating probe AND a
  `num_predict:1` control. Only escalate to recovery if both 45s attempts AND a capped
  control still 000.

## MSYS/git-bash CRLF pitfall (silent 400)
- On the Windows agent shell, `read`/process-substitution can append a trailing `\r` to the
  model name. `qwen3:32b\r` makes the JSON body invalid → Ollama returns **400 in ~0.01s**
  (instant). Looks alarming but is NOT a hang.
- Fix: `M=$(curl ... | python ... | tr -d '\r')` and always `-H 'Content-Type: application/json'`.
- Diagnostic: a sub-0.1s 400 is a PAYLOAD BUG, never a node fault. Real hangs return 000 (timeout).

## 2026-07-11 LEAF B result table (all four ZQM nodes)
| Node | tags | model_count | total_GB | gen(20s) | gen(45s) | verdict |
|------|------|-------------|----------|----------|----------|---------|
| N1 .218 | 401 | NA | NA | (auth) | (auth) | 401 auth-gated (OLLAMA_API_KEY) |
| N2 .21  | 200 | 8  | 55.41 | 200 @1.70s | — | HEALTHY (v1 hard-hang GONE) |
| N3 .46  | 000 | NA | NA | 000 (retry 10s) | 000 | UNRESOLVED — not marked down (host alive per LEAF C ICMP) |
| N4 .215 | 200 | 45 | 451.6 | 000 @20s | 200 @35.81s | HEALTHY-SLOW cold-load (NOT hung) |

## Reconcile vs v1 / LEAD
- v1: N1/N4 healthy, N2 hard-hang. Now: N1=401 auth (changed), N2=HEALTHY (recovered),
  N4=healthy-but-slow (not v1's clean 13s warm, but functional), N3=unreachable from sandbox.
- LEAD "N4 hard hang / fault migrated N2→N4" = FALSE POSITIVE (single 45s shot, slow CoT tail).
  Re-classify N4 as HEALTHY-SLOW. Q2 (permanent vs cold-load) = RESOLVED slow-coldload.
