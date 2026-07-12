# Fleet log forensics — reframe misdiagnoses via log-cadence + signature mining

Use this when a prior finding is based on a log symptom (error counts, "timeout",
"401") and you need to REFRAME it against ground truth instead of guessing. This
session reframed F45 ("N4 cold/unloaded") -> "zbit-heavy cold-load timeout", and
isolated the 401 source. The method is reusable.

## The reframe loop (4 steps)
1. **Bucket the errors** by type with a Counter over the last N lines of the log:
   ```python
   import collections, re
   cats = collections.Counter()
   for ln in lines:
       low = ln.lower()
       if 'authenticationerror' in low or ' 401 ' in low: cats['auth401'] += 1
       elif 'timeout' in low: cats['timeout'] += 1
       elif '500' in low or 'internalservererror' in low: cats['http500'] += 1
       elif 'exception' in low: cats['exception'] += 1
   ```
   A high `timeout` count with a specific `Model Group` in the same lines != "node
   dead" -- it's a slow/cold load (see ollama-health-ops for the control-shot
   disambiguation).

2. **Mine recurring signatures** (normalize timestamps/ids, count exact shapes):
   ```python
   sig = collections.Counter()
   for ln in lines:
       if any(k in ln.lower() for k in ['authenticationerror','timeout','500','unable to allocate']):
           norm = re.sub(r'\d{2}:\d{2}:\d{2}','T',ln)
           norm = re.sub(r'0x[0-9a-f]+','X',norm)
           sig[norm[:90]] += 1
   ```
   The dominant signature tells you the REAL failure class. This session:
   `[2x] openai.AuthenticationError: 401 - 'unauthorized: missing/invalid Bearer'`
   -> requests reach an upstream WITHOUT the api_key attached (key-gated node drops
   them), NOT a wrong key. Distinct from "wrong key" -- fix = ensure every
   model_list entry carries api_key.

3. **Cross-check the symptom against live state** (don't trust the log alone):
   - "401 from upstream" -> probe the upstream WITH and WITHOUT the key the proxy
     sends (`curl -H "Authorization: Bearer <key>"` vs bare). If it accepts the
     key, the 401 is a *key-attachment gap on certain routes*, not a cred mismatch.
   - "timeout on zbit-heavy" -> hit the proxy route live (`POST /v1/chat/completions`
     with `{"model":"zbit-heavy",...}`); a reproducible HTTP 000 = cold-load
     latency, fixable with keep_alive TTL + health-check warmup (see
     fleet-integration-deploy.md + agent-revival-via-litellm.md).

4. **RETRACT, don't DELETE.** When a finding is superseded, update severity/status
   + append the correction to the ledger row. Honest, reproducible history beats a
   silent delete. This session F45 went from "N4 cold/unloaded" to "zbit-heavy
   cold-load timeout (target on N2 slow/unloaded)" -- both recorded, old text kept.

## 5. FALSE-FAIL in automated re-verify — fix the TEST, don't record a contradiction
When an automated re-verification pass (the "investigate fully" / claim-chain
re-hash step) returns FAIL, distinguish a REAL contradiction from a TEST ARTIFACT
before writing it to the ledger. This session's re-verify threw 2 false FAILs that
were both test bugs, not system changes:
- **Wrong HTTP method**: probing `:8400/v1/whatever` returned 404, mis-read as
  "auth gate broken". The endpoint needs POST; a GET hits nothing → 404/405, not
  401. Re-test with the CORRECT method (POST `/v1/mesh/scan` no-key → expect 401).
- **Wrong regex**: scanning netstat for `:::11434` missed the actual `0.0.0.0:11434`
  line (IPv4-mapped vs IPv6 form). The "drift not present" FAIL was a regex miss,
  not a config change.
DISCIPLINE: when a re-verify FAILs, FIRST ask "was my probe correct?" (right
method? right regex? right vantage? transient timeout?). Re-run with a corrected
probe. Only if it STILL fails do you record a contradiction — and if it now passes,
note "initial FAIL was a test artifact; re-verified PASS" rather than flipping the
finding. This is the inverse of the RETRACT rule: don't RETRACT a finding on a
flaky test, and don't CONTRADICT the ledger on a flaky test either.

## Worked reframes (this session)
- **F45**: assumed N4 cold -> logs showed zbit-heavy timeout. Live test: N4 serves
  45 models HTTP 200; zbit-heavy routes to N2 hermes3 (present but not warm) ->
  first request after idle >8s -> proxy drops. ROOT = cold-load, not fleet coldness.
- **F54/F55**: hypothesized N4 rejects LiteLLM's `sk-na` key -> live test proved all
  nodes (N1/N2/N4) accept `sk-na` (N1 requires *a* key, sk-na satisfies it). The
  53 "AuthenticationError 401" in litellm.log are LITELLM PROXY-LEVEL (callers
  without the proxy's own key, or LiteLLM wrapping upstream timeout as auth error)
  -- NOT an upstream credential mismatch. Hypothesis REFUTED by live test.
- **F56**: `InternalServerError 500 - llama-server reported out-of-memory during
  startup: unable to allocate CUDA_Host buffer` -> a fleet node OOM'd loading a
  model too big for its VRAM. Fleet-health signal: cap context/concurrency per node.

## Pattern signals worth recording to the ledger (motif scan)
Across all findings, count motif prevalence with a regex over evidence text:
`LAN exposure/firewall`, `no-auth/missing key`, `config drift/stale comment`,
`false-negative/transient probe`, `cold-load/resource pressure`,
`over-reliance on one node`. This session: firewall(19) > no-auth(8) > config-drift(6)
> false-negative(5) > cold-load(5) > over-reliance(4). The dominant motif tells you
where the real risk concentrates.
