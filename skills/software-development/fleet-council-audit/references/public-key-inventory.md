# Public-Key Inventory (security recon) — verified walk, 2026-07-11

When the user says "investigate all public keys" / "read them all", enumerate these on a Windows host and READ each (public material — safe to display):

## Locations to check (Node-1 / ZQM pattern)
1. **User SSH identity**: `C:\Users\<user>\.ssh\id_ed25519.pub` (+ any `id_rsa.pub`, `id_ecdsa.pub`). This is the user's keypair — also inspect `.ssh\config` to see which fleet hosts it reaches (the config here revealed a ZQM-Garden fleet at 192.168.1.32–173 as user `azelenski`).
2. **User authorized_keys**: `C:\Users\<user>\.ssh\authorized_keys` — who can log IN to this host. ABSENT here → confirms why SSH key-only hardening was blocked (no key = disabling password auth would lock out).
3. **Win OpenSSH admin file**: `C:\ProgramData\ssh\administrators_authorized_keys` — default admin pubkey auth path on Windows. ABSENT here.
4. **Ollama's own key**: `C:\Users\<user>\.ollama\id_ed25519.pub` — Ollama CLI's internal tunneling key, NOT an SSH login key. Don't confuse with user SSH identity.
5. **SYSTEM-owned SSH host keys**: `C:\ProgramData\ssh\ssh_host_rsa_key.pub`, `ssh_host_ecdsa_key.pub`, `ssh_host_ed25519_key.pub` — owned by SYSTEM. **Non-elevated read is DENIED** (Permission denied). Read them via the elevated reader pattern: `scripts/read_system_file.ps1` (RunAs, dumps to .log). Host pubkeys are safe to display.
6. **known_hosts**: `C:\Users\<user>\.ssh\known_hosts` — cached peer fingerprints (Node-2/3/4 + garden hosts here). Normal trust cache.

## Hardening linkage (lockout-guard)
- To enable SSH key-only (`PasswordAuthentication no`): the user's `id_ed25519.pub` must be in `authorized_keys` FIRST. If it isn't, REFUSE (don't disable password auth with zero working auth methods). Self-contained hardening: `windows-elevated-actions → scripts/ssh_harden.ps1`.
- After hardening, re-verify: `sshd -T | grep -i passwordauthentication` (effective config) + confirm pubkey login works + password rejected.

## Verdict shape
Report each key's type + fingerprint + owner/use. Flag: missing self-authorization (pubkey exists but not in authorized_keys), any unexpected authorized_keys entries, unexpected host keys. In this run all keys were clean; the only gap was the missing self-authorization (Q6, open follow-up).
