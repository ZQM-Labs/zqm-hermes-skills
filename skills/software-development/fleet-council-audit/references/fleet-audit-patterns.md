# Fleet-Council-Audit — session patterns (ZQM, 2026-07-11)

Class-level notes from a full "investigate fully" + "hash claims" + "improve
reliability" pass over a 4-node Windows homelab (N1/N2/N3/N4). The
council+LEAD shape lives in SKILL.md; this file holds the
fleet-topology + reliability patterns that recurred.

## Topology SPOF pattern (flag in every fleet audit)
- Map EACH inference route to its backing node. A LiteLLM config like
  `zbit-router/fast/heavy` all pointing at ONE node (N2) = single
  point of failure. If that node's Ollama dies, 3/4 routes break.
- Confirm with: `Select-String -Path litellm_config.yaml -Pattern api_base`
  and a live `/v1/models` probe.
- N3 bound to localhost-only (127.0.0.1) is INTENTIONAL design,
  not a gap — don't flag it as "down".

## Reboot-gap pattern (top reliability finding)
- After any reboot, services with NO scheduled task / Startup link stay
  DOWN until manual launch. In this fleet only Ollama.lnk + OpenClaw
  Gateway task auto-started; ZBit (:8400) + LiteLLM (:4001) did NOT
  → agent stack dead post-reboot. Fix = AtStartup scheduled task
  (gated on UAC in background; user must run elevated).

## "Exposed on purpose?" genesis split (DO NOT lump exposures)
- BY DESIGN: Ollama fleet bound to LAN IPs with a config comment
  ("Hot LB = N2 open"). Accepted architecture for a trusted private LAN.
- ACCIDENTAL: Redis `bind` empty + `requirepass` empty + `protected-mode *0`
  (vanilla install, switches disabled). The only true CRITICAL.
- OS DEFAULT: WinRM-HTTP 5985, SSH, SMB — expected, not misconfig.
Report the split; only the ACCIDENTAL item earns CRITICAL.

## Hash-claim ledger (drift-detectable)
Persist each headline claim as SHA-256(claim+status), recompute LIVE
each re-run. See `local-service-verification` > "Hash-Claim Ledger" for
the schema + the recv-truncation/`"id":` matcher pitfall. Expect
STABLE across consecutive runs once the checker bug is fixed; one FALSE
claim (e.g. "US-gov controls DNS root post-2016") is normal.

## Redis = BOTH security + reliability hazard
An unauth LAN Redis is a CRITICAL RCE (CONFIG SET dir, MODULE LOAD,
FLUSHALL) AND a reliability landmine (any LAN host can wipe N2).
Treat the two as one finding. Forensic method: `scripts/redis_trace.py`
under `local-service-verification` (no redis-cli needed).

## Council re-verify note
LEAD must re-derive the headline claims LIVE (not trust the leaves'
returns). This session: leaves swept N2/N3/N4; LEAD re-probed N1 +
external fleet + hash-ledger and confirmed every claim. The
`audit-sqlite-sink` shape is the persistence target.
