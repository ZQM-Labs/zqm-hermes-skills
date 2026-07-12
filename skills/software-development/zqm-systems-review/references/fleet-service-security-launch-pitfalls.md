# Fleet Service Security & Launch Pitfalls (ZQM homelab)

Captured from the 2026-07-11 fleet-reliability + "build proper auth" session.
Class-level, not session-specific. Applies whenever you harden or relaunch the
ZBit/LiteLLM/Ollama/Redis stack on this Windows host.

## 1. Redis Windows (Memurai/MSOpenTech build, v3.0.504) — live CONFIG limitation
`CONFIG SET` on this build ACCEPTS only a subset of params at runtime:
- `requirepass <pass>`  -> OK live, takes effect immediately, ALL commands now need AUTH.
- `protected-mode yes`  -> **REJECTED**: `-ERR Unsupported CONFIG parameter: protected-mode`
- `bind 127.0.0.1`    -> **REJECTED**: `-ERR Unsupported CONFIG parameter: bind`
  (these two are STARTUP-ONLY; they require editing `redis.windows.conf` + service restart)

Practical consequence: to close a LAN RCE fast from a remote host you can only
live-set `requirepass`. That enforces auth on every command (CONFIG/FLUSHALL/
MODULE LOAD all return NOAUTH from LAN) — the RCE is dead even though the
socket still LISTENs on all interfaces. Loopback-bind + firewall are defense-in-depth
that MUST be finished via the conf-file + restart path (cannot be done live).

Full Redis auth package pattern (verified working):
1. From remote (unauth) `CONFIG SET requirepass <48hex>` -> RCE closed immediately.
2. From remote (now authed) finish `bind`/`protected-mode` attempts -> they fail live;
   note it and move to step 3.
3. On the Redis host (elevated): write `redis.windows.conf`
   (`bind 127.0.0.1`, `requirepass`, `protected-mode yes`),
   add Windows FW rule `Block-Redis-LAN` (deny tcp/6379 from 192.168.1.0/24),
   `Restart-Service Redis -Force`.
4. Persist the pass to a SECRET FILE (e.g. `C:\ProgramData\Redis\redis.pass`)
   with ACL = SYSTEM+Administrators ONLY (disable inheritance, deny others) —
   NOT in the .ps1 or committed. Never display the pass in chat output longer than
   the one session it is set; tell the user to store it.
5. Verify: loopback `redis-cli -h 127.0.0.1 -a <pass> ping` -> PONG;
   LAN `redis-cli -h <ip> ping` -> NOAUTH/timeout.

Trace-first rule: before locking a service, prove it has NO legitimate consumer
(netstat ESTABLISHED by pid, then `tasklist`/`Get-CimInstance` the pid, then
grep the fleet configs for the host:port). The N2 Redis had only an orphaned
self-connection (my own probe socket) + venv library references (apscheduler redis
jobstore, botocore elasticache examples) — i.e. NOTHING real used it. So
hardening broke nothing. Locking a service that DOES have a live consumer would
break that consumer (it would need the new AUTH).

## 2. LiteLLM launch quirk on this host
`litellm.exe` under `ZBit_api\venv\Scripts\` is a compiled PE launcher
(self-bootstrapping venv). It must be run DIRECTLY:
    C:\Users\zqmco\ZBit_api\venv\Scripts\litellm.exe --config litellm_config.yaml --host 127.0.0.1 --port 4001
These ALL FAIL:
- `python.exe venv\Scripts\litellm.exe`  -> `No module named litellm`
  (python treats the .exe as a module to import; venv site-packages not on
  python312's path)
- `venv\Scripts\python.exe -m litellm` -> `No module named litellm.__main__`
  (litellm is a package, has no __main__.py)
Launch persistently with Hermes `terminal(background=true)` from `C:\Users\zqmco\ZBit_api`
cwd; do NOT use `start cmd /c` (bash→cmd quoting mangles paths/redirects and
the process dies with the subshell). After launch, verify `:4001` LISTENING +
`/v1/models` returns the virtual models.

## 3. litellm_config reliability edit (verified)
`zbit-heavy -> hermes3:latest @ N2:11434` had NO `timeout:` + `Model Group
Fallbacks=None` in litellm.log -> default 120s hang on cold hermes3 load
(N2 VRAM evicts hermes3 when other models load). Fix (live, rerouted instead
of hard-fail): add `timeout: 45` + `model_group_fallback: [zbit-fast]` to the
zbit-heavy block. Verified: POST zbit-heavy returned 200 in <3s (was 120s).
litellm_config.yaml is the file; edits are reversible (delete the 2 lines).

## 4. Coined-verb + label-precision discipline (user preference)
- The user uses coined/standing verbs ("investigate fully", "hash claims",
  "study patterns", "genesis", "learn more", "approve with branches and forks").
  Decode each into a concrete action + FLAG THE ASSUMPTION before acting.
  Example: "approve with branches and forks" = git branch + fork (PR) workflow;
  but the fleet-review artifacts (swarm/fleet_endpoint_review/*, litellm_config.yaml)
  live in NON-git dirs, so the verb can't apply in-place — first must identify the
  right existing repo home. Deep-look found 49 repos; `zqm-localhost-findings`
  (clean, 0 dirty, purpose-named, remote ZQM-Computing/zqm-localhost-findings)
  is the natural target. Never `git init`/`add`/`.` blindly; name the repo + confirm.
- When you LABEL a finding (mistake / accidental / by-design / intentional),
  be defensible and do NOT overstate fault. The user WILL challenge overstated
  labels ("why is that a mistake?"). Correct procedure when challenged:
  * retract to the precise label (e.g. "accidental default drift" -> "unintended
    default (not proven a deliberate mistake)"),
  * keep the contrast that matters (Ollama LAN-exposure = documented intent +
    real consumer = by-design; Redis UNAUTH = stock-default config + no consumer +
    no documented intent = unintended-default),
  * the RISK is identical regardless of label — fixing does not depend on blame.
  Do not re-assert the overstated word after correction.
