# Ollama Hang Disambiguation — Control-Shot + Escalating Recipe

Worked method for telling a COLD-LOAD / thinking-model **false-hang** from a PERMANENT
GPU/VMM **wedge**. The control shot (`num_predict:1`) is the discriminator: a wedge fails
the control; a false-hang passes it in <2s. This is the single most mis-diagnosed outcome
on the ZQM fleet — always run all three shots before calling a node "permanently hung".

## Protocol (run in order, on the node's default/largest model)
```bash
M=http://<ip>:11434; MODEL=qwen3:32b   # strip MSYS CRLF from $MODEL: echo $MODEL | tr -d '\r'
echo "== CONTROL np:1 (max 15s) =="
curl -s -m 15 -o /dev/null -w "http=%{http_code} total=%{time_total}\n" \
  $M/api/generate -d "{\"model\":\"$MODEL\",\"prompt\":\"hi\",\"stream\":false,\"options\":{\"num_predict\":1}}"
echo "== FULL escalate tier1 20s =="
curl -s -m 20 -o /dev/null -w "http=%{http_code} total=%{time_total}\n" \
  $M/api/generate -d "{\"model\":\"$MODEL\",\"prompt\":\"Write one sentence about the sky.\",\"stream\":false}"
echo "== FULL escalate tier2 45s =="
curl -s -m 45 -o /dev/null -w "http=%{http_code} total=%{time_total}\n" \
  $M/api/generate -d "{\"model\":\"$MODEL\",\"prompt\":\"Write one sentence about the sky.\",\"stream\":false}"
echo "== CORROBORATE np:20 (max 60s) =="
curl -s -m 60 -w "\nhttp=%{http_code} total=%{time_total}\n" \
  $M/api/generate -d "{\"model\":\"$MODEL\",\"prompt\":\"Say hello.\",\"stream\":false,\"options\":{\"num_predict\":20}}" | tail -c 300
```

## Interpretation matrix
| control np:1 | full 20s/45s | np:20 | Verdict |
|---|---|---|---|
| 200 <2s | 000 both | 200, eval_count:20 | **FALSE HANG** (thinking CoT) — node healthy |
| 000 | 000 both | 000 / no tokens | **WEDGE** — GPU/VMM stuck |
| 200 <2s | 200 | 200 | healthy; model just slow/cold |

## Live proof — 2026-07-11, Node-4 = 192.168.1.215
Prior lead claim: "N4 PERMANENT HANG, control 000 proves wedge." Re-baseline DISPROVED it:
- control qwen3:32b np:1 → **200@1.79s**, re-run **200@0.62s**  (lead's control=000 NOT reproduced)
- full qwen3:32b → 000@20s, 000@45s  (looks hung on the surface)
- np:20 qwen3:32b → **200@6.1s, eval_count:20, done_reason:"length"**  (REAL tokens emitted)
- mistral:7b full gen → **200@14.3s**  (small non-thinking model completes freely)

Conclusion: classic qwen3 thinking-model false-hang, NOT a wedge. N4 = HEALTHY (slow only
on unbounded CoT models). Tagged **UNRESOLVED / DISPUTED** against the lead; recommended the
lead re-run the control shot. Demonstrates why the control shot is mandatory, not optional.

## curl exit-code 23 caveat
On MSYS/Windows, `curl -s -o /dev/null -w '...'` can return **exit code 23** (write error)
even though the timing/`http=` values printed correctly. Trust the printed `%{http_code}` /
`%{time_total}` numbers; do NOT treat exit 23 as probe failure for timing/generate checks.
