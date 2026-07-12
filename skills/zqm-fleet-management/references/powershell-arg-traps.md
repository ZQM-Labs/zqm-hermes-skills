# PowerShell argument-passing traps (cost 9 failed SSH-auth-proof attempts, 2026-07-10)

When driving external EXEs from PowerShell 5.1 (agent host), these mangle silently.

## 1. ssh-keygen empty passphrase
- `ssh-keygen -t ed25519 -f $key -q -N ''`  -> "Too many arguments"
- `ssh-keygen ... -N '""'`                  -> embeds quotes IN THE FILENAME
  (key created as `zqm_verify_key""`, `.pub` never matches `$key.pub`)
- RELIABLE: pipe an empty line so ssh-keygen reads the passphrase from stdin:
  `"" | ssh-keygen.exe -t ed25519 -f $key -q`
- Alt: `& ssh-keygen.exe -t ed25519 -f $key -q -N ([string]::Empty)` then write the
  public key via a method that doesn't need `-N`.
