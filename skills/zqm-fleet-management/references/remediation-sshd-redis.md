# Remediation recipes — Windows sshd + Redis (design-verified, apply-gated)

Concrete applied fixes for two recurring ZQM fleet findings. Read-only by default:
LIVE-validate state before designing (see "Design discipline" at end). All secrets as
`${REDACTED}`; never write a cred to chat.

## A. sshd password-auth hardening (N1 / 192.168.1.218)
Config `C:\ProgramData\ssh\sshd_config`; service `sshd`.

### WINDOWS TRAP - edit in place, NEVER append at EOF
Windows OpenSSH `sshd_config` ends with a `Match Group administrators` block. Appending
`PasswordAuthentication no` at EOF scopes it to admins-only and silently does nothing for
other users. The default config ships the auth lines COMMENTED
(`#PasswordAuthentication yes`, `#PubkeyAuthentication yes`, `#PermitRootLogin
prohibit-password`) - edit those lines IN PLACE (uncomment + set).

### Lockout pre-checks (do first, every time)
- Admin users MUST use `C:\ProgramData\ssh\administrators_authorized_keys` (NOT
  `~/.ssh/authorized_keys`); strict ACL (owned by BUILTIN\Administrators,
  SYSTEM:R + Administrators:R).
- Confirm a pubkey login WORKS before disabling passwords. Keep RDP / a second console
  open during the restart.

### Apply
```powershell
$cf='C:\ProgramData\ssh\sshd_config'; $c=Get-Content $cf
$c=$c -replace '^#?\s*PasswordAuthentication\s+.*','PasswordAuthentication no'
$c=$c -replace '^#?\s*PubkeyAuthentication\s+.*','PubkeyAuthentication yes'
$c=$c -replace '^#?\s*PermitRootLogin\s+.*','PermitRootLogin prohibit-password'
Set-Content -Path $cf -Value $c -Encoding ascii
& 'C:\Windows\System32\OpenSSH\sshd.exe' -t     # syntax test, silent = OK
Restart-Service -Name sshd -Force
# (Optional stricter: 'AuthenticationMethods publickey' - only after pubkey proven)
```

### Firewall scope (tighten ZQM-OpenSSH-22 from /24 to admin only)
```powershell
netsh advfirewall firewall set rule name="ZQM-OpenSSH-22" new remoteip=${ADMIN_IP}
# multi:  remoteip=192.168.1.50,192.168.1.51
# PS equiv: Set-NetFirewallRule -Name "ZQM-OpenSSH-22" -RemoteAddress ${ADMIN_IP}
```

### Validation
```powershell
& 'C:\Windows\System32\OpenSSH\sshd.exe' -G | Select-String 'passwordauthentication|pubkeyauthentication|permitrootlogin'
# -> passwordauthentication no ; pubkeyauthentication yes ; permitrootlogin prohibit-password
# external:  ssh zqmco@192.168.1.218  -> Permission denied (publickey)
# keys still work: ssh -i <key> zqmco@192.168.1.218 echo OK  -> OK
netsh advfirewall firewall show rule name="ZQM-OpenSSH-22" | Select-String RemoteIP   # -> ${ADMIN_IP}
```
`sshd -G` is the ground-truth EFFECTIVE config (survives commented/default lines) - always
use it as the proof, not a grep of the file. `sshd -t` is the syntax gate before restart.

## B. Redis unauth lock (N2 / 192.168.1.21)
Run on N2's OWN shell (`redis-cli` may be absent -> raw-TCP fallback below).

### FLEET-CRITICAL - do NOT loopback-bind
N1 (LiteLLM) connects to `redis://192.168.1.21:6379`. `bind 127.0.0.1` ONLY would SEVER
N1->N2 Redis and break the AI fleet. The naive "bind to localhost" hardening is WRONG here.
Instead keep LAN reachability and enforce auth + host-firewall scope:
```
bind 192.168.1.21
protected-mode yes
requirepass ${REDACTED_STRONG_PASSWORD}
```
(127.0.0.1-only is only correct if NO remote client needs Redis - not the case here.)

### Persistence - runtime SET is lost on restart
`CONFIG SET requirepass` alone does not survive a restart unless Redis loaded a config file
AND you run `CONFIG REWRITE` (or edit the file). Find the loaded conf first:
```powershell
Get-ChildItem 'C:\Program Files\Redis\*.conf','C:\ProgramData\Redis\*.conf' -EA SilentlyContinue
```
Edit the file (above) AND apply at runtime:
```powershell
redis-cli CONFIG SET protected-mode yes
redis-cli CONFIG SET requirepass "${REDACTED_STRONG_PASSWORD}"
redis-cli -a "${REDACTED_STRONG_PASSWORD}" CONFIG SET protected-mode yes   # re-affirm post-auth
redis-cli CONFIG REWRITE        # persists into the loaded conf
```
**Raw-TCP fallback** (no redis-cli) - send RESP lines to 192.168.1.21:6379:
```
CONFIG SET protected-mode yes
CONFIG SET requirepass ${REDACTED_STRONG_PASSWORD}
AUTH ${REDACTED_STRONG_PASSWORD}
CONFIG REWRITE
```

### Never `CONFIG GET requirepass` - it logs the password in plaintext
Validate via AUTH success / unauth rejection, never by reading the value.

### Restart + host firewall scope
```powershell
Restart-Service -Name Redis            # or "RedisServer"; confirm via Get-Service *redis*
netsh advfirewall firewall add rule name="ZQM-Redis-6379" dir=in action=allow protocol=TCP localport=6379 remoteip=192.168.1.218
# add admin IPs as needed
```

### LITELLM DEPENDENCY (downstream break)
After `requirepass`, LiteLLM must authenticate or it loses Redis:
```
redis_host: redis://:${REDACTED_STRONG_PASSWORD}@192.168.1.21:6379
```
Coordinate the Redis restart + LiteLLM config update together.

### Validation
```powershell
# external (foreign LAN host, raw TCP PING w/o AUTH): -> -NOAUTH Authentication required.
# local on N2:
redis-cli -h 127.0.0.1 -a "${REDACTED}" ping   -> PONG
redis-cli -h 127.0.0.1 -a "${REDACTED}" CONFIG GET protected-mode   -> yes
redis-cli -h 127.0.0.1 -a "${REDACTED}" CONFIG GET bind             -> 192.168.1.21
# N1 LiteLLM still reaches Redis (post-password update): service healthy, no auth errors
```

## C. Read-only remediation-design discipline (deliverable template)
When the user says "design / read-only / no apply":
1. **LIVE-validate before designing** - read the actual current state (sshd_config lines,
   firewall rule RemoteIP, service status, reachability probe). Do NOT design from memory or
   pasted output (the fleet skill's standing "verify claims" rule).
2. Return three artifacts: (a) precise commands, (b) a validation checklist that proves each
   fix worked, (c) lockout/blast-risk warnings (sshd key-in-wrong-path lockout; loopback-bind
   breaking a dependent service).
3. Flag probe gaps honestly - if you cannot re-verify a finding from the sandbox (e.g. N2
   Redis unreachable from N1), say so and scope the fix to run on the node's own shell.
4. Do NOT apply. State "no files written" in the summary.
