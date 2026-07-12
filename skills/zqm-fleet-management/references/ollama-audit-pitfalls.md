# Ollama Audit Pitfalls (2026-07-10)

Three non-obvious traps that surfaced during a live 3-agent "council" audit of the ZQM
Ollama fleet. Each cost real cycles; encode them so the next audit skips them.

## 1. Dark /24 scan = "not installed"
A host that does not answer `:11434` from the LAN is frequently an Ollama bound to
`127.0.0.1` (localhost-only), NOT an absent install.

Observed: Node-3 (192.168.1.46) was ALIVE from the agent's LAN vantage — SSH:22 and
WinRM:5985/5986 returned OPEN — but `:11434` returned `000` even at a 5s timeout, and a
sweep of alternate ports (11435-11437, 11500, 8888, 9000, 3000, 8080, 12798) found no
Ollama API.

Correct conclusion: "Ollama installed but localhost-bound / not LAN-exposed" — which is
the SECURE posture (not reachable by LAN peers, so not an unauthenticated-exposure risk).
Flag it as an UNVERIFIED-install gap: confirm with `ollama list` on the host itself, or
WinRM in with that node's break-glass cred.

Never fold a localhost-bound host into "no Ollama on the LAN" counts. Always re-probe a
known host with a generous timeout (e.g. `curl -m 6 --connect-timeout 5`) before declaring
it dark — a 1s scan times out on slow-but-present services and reads as 000.

## 2. /api/ps is dynamic — timestamp your snapshots
Loaded-model state changes between probes as models auto-load/unload on first use and
expire after idle.

Observed in one session:
- Probe A: Node-4 had `qwq:32b` loaded (14.86 GB VRAM, Q4_K_M, 40960 ctx). Node-1/2 empty.
- Council window: Node-2 had `deepseek-r1:1.5b` loaded (5.53 GB VRAM, Q4_K_M, 131072 ctx).
  Node-4 empty. (A subagent reported "all three empty" — STALE, not ground truth.)
- Re-probe: state differed again.

Discipline:
- When a loaded-model fact matters, run `/api/ps` in the SAME turn you report it.
- Label it TIME-STAMPED / point-in-time. Never present it as a fixed property of the host.
- If a subagent/council reports "/api/ps empty on all hosts," treat it as a possibly-stale
  snapshot and re-verify before recording it as fact.

## 3. Version currency = GitHub releases API, NOT web_search
`web_search` for "latest Ollama version" returned a STALE "v0.30.10 (June 2026)" — wrong.

Authoritative source:
    curl -s "https://api.github.com/repos/ollama/ollama/releases?per_page=8" \
      | python -c "import json,sys; [print(r['tag_name'], r.get('published_at')) for r in json.load(sys.stdin)]"

This session that returned: v0.32.0-rc0 (a release candidate — NOT stable) ABOVE the real
latest stable v0.31.2 (published 2026-07-06). All three ZQM hosts run 0.31.2 = CURRENT.

Rules:
- Take the newest tag that does NOT end in `-rc` / `-rc0` / `prerelease` as "latest stable."
- Do not trust a search-engine summary for currency — it lags.
- `/api/version` exposes ONLY the version string in 0.31.x (the `build` date field was
  dropped); compare the host's version against the API-derived latest stable.

## Bonus: proving "no auth gate" without firing a real prompt
To confirm Ollama is unauthenticated, you do NOT need to run a real generation:
- `POST /api/show {"model":"<existing>"}` -> HTTP 200 (metadata returned, no creds) = read is open.
- `POST /api/generate {"model":"__nonexistent__","prompt":"x"}` -> HTTP 404 (not 401/403).
  The 404 means the request REACHED the engine (which then reported the model missing); an
  auth gate would have returned 401/403. This is proof of credential-free WRITE reachability
  without sending a live prompt. Ollama ships with no native auth on 0.0.0.0 binds.
