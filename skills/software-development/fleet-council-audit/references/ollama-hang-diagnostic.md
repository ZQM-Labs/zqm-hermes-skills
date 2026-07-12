# Ollama Generate-Hang Diagnostic (escalating + control shot)

The single most repeated FALSE POSITIVE in ZQM fleet audits: declaring a node
"HARD HUNG / fault migrated" from one `curl -m 45 /api/generate` returning `000`.
A slow large "thinking" model (qwen3:32b, qwq:32b) emits full chain-of-thought and
takes 25-50s on a cold load — a single 45s shot catches the slow tail and looks like a
wedge. COLD-LOAD != HANG. Use this recipe so the LEAD never mislabels a slow model.

## The three-way probe (per node)
```bash
IP=192.168.1.215
M=$(curl -s -m 5 "http://$IP:11434/api/tags" \
   | python -c "import json,sys;d=json.load(sys.stdin);print(d['models'][0]['name'])" \
   | tr -d '\r')
# 1) CONTROL SHOT — 1 token, proves model+VRAM path is alive (ignores CoT slowness)
curl -s -m 15 -o /dev/null -w "control=%{http_code} t=%{time_total}\n" -X POST \
  "http://$IP:11434/api/generate" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$M\",\"prompt\":\"ping\",\"stream\":false,\"num_predict\":1}"
# 2) ESCALATING full-gen — 20s, then 45s on timeout
curl -s -m 20 -o /dev/null -w "gen20=%{http_code}\n" -X POST \
  "http://$IP:11434/api/generate" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$M\",\"prompt\":\"ping\",\"stream\":false}"
curl -s -m 45 -o /dev/null -w "gen45=%{http_code} t=%{time_total}\n" -X POST \
  "http://$IP:11434/api/generate" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$M\",\"prompt\":\"ping\",\"stream\":false}"
```

## Interpretation table
| control(num_predict:1) | gen20 | gen45 | verdict |
|---|---|---|---|
| 200 fast (~0.5s) | 200 | (n/a) | HEALTHY — slow full-gen = CoT cold-load, NOT a hang |
| 200 fast | 000 | 200 mid-window | SLOW COLD-LOAD (healthy) — model just loaded slowly |
| 000 (timeout) | 000 | 000 | **PERMANENT HANG / inference wedge** — emit 1 token fails => path wedged |
| 400 (<0.1s) | — | — | PAYLOAD BUG (CRLF \r in model name), NOT a hang — strip CR and re-probe |
| 401 | — | — | AUTH-GATED (OLLAMA_API_KEY) — unrelated to hang |
| 000 (tags) | — | — | service/port DOWN, node unreachable |

## Live proofs (ZQM fleet, 2026-07-11)
- **v2, N4 .215, qwen3:32b:** control=200@0.57s, gen20=000, gen45=200@35.81s => HEALTHY-SLOW.
  The v2 LEAD "N4 HARD HANG / fault migrated N2->N4" was a FALSE POSITIVE (single 45s shot).
- **v3, N4 .215, qwen3:32b:** control=**000@15s**, gen45=000@45s => REAL permanent hang
  (control failing is the decisive discriminator; inference path genuinely wedged this time).
- **v3, N2 .21, llava:7b:** control=200@7.3s, gen20=200 => HEALTHY.

## Hard rules
- Control shot is MANDATORY before any "hang" / "fault migrated" claim (see LEAD re-verify gate).
- `tr -d '\r'` on the model name — MSYS/git-bash appends CRLF, a `qwen3:32b\r` body => instant 400.
- Never trust a subagent's "HANG CONFIRMED" without the control-shot result in hand.
- Reusable: inline probe above, or ollama-recovery/scripts/escalating_generate_probe.sh.
