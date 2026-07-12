# Windows Fleet — Reliability Hardening + Proper-Auth (session learnings)

Class of work that emerged this session: "investigate fully" on the ZQM
fleet routinely ends in a reliability/security *fix*, not just a report.
The user said "improve the reliability of the garden" and "build the proper
auth" after the audit. Treat those as IN-SCOPE continuations.

## "investigate fully" = re-derive + re-hash, every time
- LEAD re-verifies every headline claim LIVE (process/service/security)
  AND re-runs the SHA-256 claim ledger, flagging drift.
- The hash-drift checker is the tamper-evident control. A recurring
  bug: naive `recv(200)` truncated the model list and a `"id":`
  substring matcher false-flagged DRIFT. Fix: recv(1024) and match
  `"id":` exactly. After the fix, 7 consecutive runs = STABLE.
- Full fleet set: 16 claims (15 PROVEN / 1 FALSE = "US-gov controls
  DNS root post-2016", which is FALSE after the 2016 NTIA transition).

## Genesis labels — be precise, not blame-loaded
- The user corrected an overstated "mistake" label on N2 Redis UNAUTH.
- Use "unintended-default" when: no config documents intent to expose
  the service, AND no consumer references it. Contrast with by-design
  exposure (e.g. Ollama LAN mesh) which HAS documented intent
  (litellm_config.yaml comments: "open nodes N2/N3 live") + a real
  consumer (N1's litellm routes to it).
- Risk is identical either way; the label only changes blame, not the fix.

## Proper auth on a live unauth service (Redis case)
- `CONFIG SET requirepass <48hex>` takes effect IMMEDIATELY via an
  unauth peer connection. LAN unauth commands then return NOAUTH →
  RCE closed the same minute.
- BUT Windows/Memurai Redis **v3.0.504** REJECTS live
  `CONFIG SET bind` / `protected-mode` ("Unsupported CONFIG parameter").
  Those are startup-only → must go via redis.windows.conf + service
  restart, run ON the target node (needs its break-glass cred).
- Firewall LAN-block (deny 6379 from 192.168.1.0/24, allow
  loopback) is defense-in-depth, also node-side.
- Credential handling: NEVER persist the generated pass to a file you
  write. Display once; tell user to store on the target node
  (C:\ProgramData\Redis\redis.pass, ACL SYSTEM+Admins only, deny
  inheritance). Rotate via the node-side script.
- Before locking: prove NO legitimate consumer exists. Trace from the
  peer: `netstat -ano | findstr :6379` + map PID → process, and
  grep local configs for the IP:port. If only your own orphaned
  socket + venv LIBRARIES (apscheduler redis jobstore, botocore
  elasticache examples) match, it's safe to lock (breaks nothing).

## Git-coined verb: "approve with branches and forks"
- Framing (user coined; per standing rule coined verbs need a defined
  framing): = git branch + fork + PR workflow, not commit-to-main.
- GATE surfaced this session: neither `swarm/` nor `ZBit_api/` (where
  all the changed scripts + litellm_config edit live) is a git repo.
  You cannot `git branch` or `gh fork` a non-repo.
- Do NOT git-init blindly into a dir the user didn't designate, and do
  NOT `gh fork` to an unknown remote. Surface the gate.
- The SQLite ledger (fleet_endpoint_audit.db) is the durable artifact;
  git is optional hygiene. Offer: (A) git-init a feature branch
  locally, (B) point at the existing repo the scripts belong in,
  (C) skip git — ledger is source of truth.

## Windows fleet pitfalls (command layer)
- litellm.exe is a self-bootstrapping PE. Launch it DIRECTLY:
  `venv\Scripts\litellm.exe --config litellm_config.yaml --host 127.0.0.1 --port 4001`
  NOT `python.exe litellm.exe` (fails "No module named litellm")
  and NOT `python -m litellm` (fails "litellm is a package and
  cannot be directly executed").
- Restarting a service from git-bash: `start cmd /c "..."` with
  redirects often dies with the subshell; prefer `terminal(background=true)`
  for long-running processes, or PowerShell `Start-Process` with
  `-WorkingDirectory`.
- PowerShell substring trap: `"FOUND" in "TASK_NOT_FOUND"` is True.
  Use `.StartsWith()` / exact match for status checks.
- netstat via subprocess.run in some hosts silently eats cmd stdout;
  use a bare terminal redirect `powershell -NoProfile -Command "cmd /c 'netstat -ano -p TCP' | Select-String LISTENING" > file` then parse the file.
