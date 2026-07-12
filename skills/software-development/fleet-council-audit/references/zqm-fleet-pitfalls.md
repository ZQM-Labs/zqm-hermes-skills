# ZQM Fleet — Pitfalls, Techniques & Verification Patterns
Condensed from the 2026-07-11 "investigate fully" session. Task-focused; not a narrative.

## 1. Windows Redis (Memurai / MSOpenTech build, v3.0.504) hardening
- **`CONFIG SET protected-mode` and `CONFIG SET bind` are REJECTED live** ("-ERR Unsupported CONFIG parameter").
  Only `requirepass` is live-settable. `bind`/`protected-mode` are startup-only → must go in
  `redis.windows.conf` + **service restart** to apply.
- **Immediate RCE closure from a remote host (no creds needed if currently unauth):**
  `CONFIG SET requirepass <48hex>` over the open socket. After that, ALL unauth commands
  (CONFIG/FLUSHALL/MODULE) return `NOAUTH`. RCE neutralized same-second.
- `INFO server` / `CONFIG GET` work unauth pre-fix → full forensic trace possible read-only.
- **Consumer check before lock-down:** scan the calling host for ESTABLISHED conns to `:6379`
  AND grep local configs for `6379`/`redis`. If only venv libs (apscheduler, botocore elasticache
  examples) match — it's an orphan; lock-down breaks nothing.
- Lane to full proper-auth: generate 48-hex pass, store in `C:\ProgramData\Redis\redis.pass`
  with ACL SYSTEM+Admins only (disable inheritance, remove all others), write conf
  (bind 127.0.0.1 + requirepass + protected-mode yes), add Win FW rule "Block-Redis-LAN"
  (deny tcp/6379 from 192.168.1.0/24), restart service.

## 2. Launching Windows Python services from git-bash/MSYS terminal
- **`python.exe litellm.exe` FAILS** ("No module named litellm"). `litellm.exe` is a self-bootstrapping
  PE launcher — run it DIRECTLY: `venv\Scripts\litellm.exe --config ... --host 127.0.0.1 --port 4001`.
- For long-running daemons use `terminal(background=true)` (Hermes tracks PID + lifecycle).
  `start "title" /min cmd /c "..."` from bash often dies with the subshell.
- `cd /d C:\path` breaks under git-bash (gets "too many arguments") — use `cd /c/Users/...` (MSYS path).

## 3. git-bash heredoc / quote mangling (Python scripts)
- Passing Python via `terminal` heredoc with `\"` escapes → SyntaxError. The shell rewrites quotes.
- **Rule:** write the `.py` to disk with `write_file` (single-quote strings inside, no `\"`),
  then `python.exe script.py`. Avoid inline heredocs for anything non-trivial.
- Same for PowerShell `Select-String -Pattern 'a|b'` inside bash `powershell -Command "..."` →
  the `|` and `{}` get mangled. Put PS in a `.ps1` file and call `-File`.

## 4. Verification gate (system "unverified edit" flag)
- After any file edit, the harness demands fresh evidence. **Pattern:** write a temp script
  `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-<topic>-<date>.py`, run it against
  LIVE behavior (not just file presence), report as AD-HOC (not suite green), then `rm` it.
- Catch substring-match bugs in your own assertions (e.g. `"FOUND" in "TASK_NOT_FOUND"` → true).
  Use `.startswith()` / exact equality.
- Persist verification results to SQLite (`fleet_endpoint_audit.db`) so re-runs are comparable.

## 5. "Investigate fully" / "hash claims" / "study patterns" methodology (this skill)
- council (parallel leaves, ≤3) + LEAD live re-verify every headline claim.
- hash-claims: SHA-256 each claim+status; re-probe and recompute; drift = mismatch.
  Ledger table `hash_drift_log` (stable/drift counts). Self-correcting checker bug (recv truncation)
  is the cautionary tale — verify the verifier.
- "study patterns": separate RECURRING (boot-correlated sshd, post-fix stable drift) from
  SINGLE (one power-off) and RECENT-CLUSTERED (litellm timeout after config edit).

## 6. Genesis / intent labeling (USER PREFERENCE — precise, no blame-overstatement)
- Distinguish **by-design** (documented intent + real consumer; e.g. Ollama LAN mesh in
  litellm_config.yaml comments, N1 litellm is its consumer) from **unintended-default**
  (stock config, no doc intent, no consumer — e.g. N2 Redis UNAUTH).
- Do NOT call an unintended-default a "mistake" unless intent to misconfigure is proven.
  User corrected this explicitly. Label = "unintended default (not proven a deliberate mistake)".

## 7. ZQM fleet reference facts (verified 2026-07-11)
- Nodes: N1 .218 / N2 .21 / N3 .46 (localhost-bound Ollama) / N4 .215.
- N1 runs ZBit Agent API :8400 (loopback, X-Api-Key) + LiteLLM :4001 (loopback).
- Ollama LAN-exposed on N1/N2/N4 = by-design ZBit inference mesh. N3 localhost-only by design.
- N2 Redis :6379 was the only CRITICAL (unauth RCE) → auth-gated live 19:02, RCE closed;
  bind/firewall pending N2 break-glass cred.
- LiteLLM `zbit-heavy` → N2 hermes3; add `timeout:45` + `model_group_fallback:[zbit-fast]`
  to kill the 120s default-timeout hard-fail on cold model loads.
- Break-glass creds are PER-NODE and DIFFER — never reuse/guess across nodes.
