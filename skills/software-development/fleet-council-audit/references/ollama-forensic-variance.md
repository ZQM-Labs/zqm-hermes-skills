# Ollama forensic variance test — intermittent vs persistent hang

## The trap
A single `POST /api/generate` that times out (30s, HTTP 000) looks like a "dead GPU/VMM".
It is NOT sufficient evidence. A cold model load into VRAM also times out once, then works.

## The test (run it N times + a concurrency test, don't judge from one sample)
```python
import urllib.request, json, time, concurrent.futures
def gen(ip, model, to=35):
    body = json.dumps({"model": model, "prompt": "x", "stream": False,
                       "options": {"num_predict": 2}}).encode()
    try:
        t0 = time.time()
        urllib.request.urlopen(
            urllib.request.Request(f"http://{ip}:11434/api/generate",
                                   data=body, headers={"Content-Type": "application/json"}),
            timeout=to).read()
        return int((time.time() - t0) * 1000)
    except Exception as e:
        return -1   # -1 = hang/timeout

ip = "192.168.1.21"
samples = [gen(ip, "deepseek-r1:1.5b") for _ in range(10)]   # -1 == hang
print("sequential:", samples, "hangs=", samples.count(-1))

def worker(i): return gen(ip, "deepseek-r1:1.5b", to=40)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
    print("concurrent(4):", list(ex.map(worker, range(4))))
```

## Reading the verdict
- works sometimes (sub-second to tens of seconds) AND hangs sometimes -> INTERMITTENT flap.
  BUT: a concurrency test (4 parallel generates) that ALSO passes means it is NOT load-correlated
  — it's a rare sporadic glitch, NOT "VRAM contention under load". Do NOT over-call it
  load-correlated. Restart only if hangs CLUSTER (reproducible on demand), not for one-off
  transient timeouts. Retract any prior "persistent dead VMM" finding.
- hangs every time, even warm model + escalating timeouts (30/60/90s) -> PERSISTENT (wedged
  VMM / stuck process). Restart Ollama + `nvidia-smi -r`.
- `/api/tags` instant + `/api/generate` dead = classic GPU/VMM pattern (tags don't touch VRAM).

## Cross-checks
- `GET /api/ps` empty during a hang -> no model loaded in VRAM (consistent with contention).
- `POST /api/embed` works while generate hangs -> embedding path is lighter; inference path is
  the one starving. Confirms load-dependent, not total process death.
- Embedding-only models (nomic-embed-text, all-minilm) return HTTP 400 on `/api/generate` -
  expected, not a fault; pick the smallest *text-generation* model for the test.

## Live case (ZQM fleet, 2026-07-11)
Node-2 `.21:11434` first declared "persistent hang" (30s + 60s timeouts by council root).
Forensic re-probe 10 sequential + 4 parallel: ZERO hangs (176-8436ms sequential; 327-353ms
concurrent). So the earlier 30s timeouts were real at that moment but rare/intermittent, NOT a
dead card and NOT load-correlated (it survived 4-way concurrency). Verdict corrected in the
ledger to "INTERMITTENT hang (GPU/VMM flap)", monitor not restart.
