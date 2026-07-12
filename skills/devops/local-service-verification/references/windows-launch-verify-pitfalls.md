# Windows Service Launch & "Verified" Pitfalls (learned 2026-07-11)

When you kill + relaunch a Windows service from git-bash, the naive path
silently fails and you may report "verified" on a DEAD service. This
session restarted LiteLLM 3x with a broken launch command while
reporting success — only a post-restart re-probe caught it was down.

## LiteLLM.exe is a PE launcher, not a python script
`venv\Scripts\litellm.exe` is a compiled console launcher (MZ header,
"cannot run in DOS mode"). Running `python.exe litellm.exe` fails with
`No module named litellm` (python tries to import the .exe as a module,
and the venv site-packages isn't on the system python's path).
- RUN IT DIRECTLY: `venv\Scripts\litellm.exe --config litellm_config.yaml --host 127.0.0.1 --port 4001`
- Its shebang resolves the venv itself. `-m litellm` also fails (litellm
  has no `__main__`). Do NOT wrap it in `python.exe`.

## git-bash `start` mangles Windows launches
`start "title" /min exe --args` from git-bash mangles quoting and the
detached process dies with the bash subshell. Use:
`terminal(background=true, notify_on_complete=true)` to launch persistent
Windows services — it survives the turn. `timeout N exe` in foreground
leaves the service DEAD when the timeout fires.

## PREMATURE "verified"
After editing runtime config + restarting, do NOT claim verified from the
restart's own stdout. Re-probe the LIVE contract 5-10s later:
- `:port` LISTENING via fresh netstat (not TIME_WAIT)
- `/v1/models` returns data (not connection-refused)
- functional POST returns <expected-time (e.g. zbit-heavy 200 in <50s,
  not the old 120s hang)
This session's "applied+verified" was premature; the post-restart
re-probe is the only real check.

## Change-verification hook (system-enforced)
When the system flags "unverified edits", write a fresh
`%LOCALAPPDATA%\Temp\hermes-verify-*.py`, run it against LIVE behavior
(not file contents alone), report ad-hoc (explicit pass/fail), then delete it.
The one behavior-changing edit (e.g. litellm_config.yaml `timeout:` /
`model_group_fallback:`) must be proven LIVE, not just present on disk.

## Bash quote-mangling
Never embed `\"` or `'` inside a Python string written through
git-bash `write_file`/`terminal` — it rewrites them and breaks the script
at runtime (`TypeError: a bytes-like object is required`). Use single-quoted
Python strings with `'\r\n'` literals.
