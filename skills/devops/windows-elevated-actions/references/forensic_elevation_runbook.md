# Forensic Elevation Runbook (session-specific detail, 2026-07-11 hardening)

Companion to SKILL.md. Captures the forensic-recreation methodology the user demands for
audits/diagnostics, plus the proven helper scripts that were battle-tested this session.

## User expectation: FORENSIC RECREATION, not "PASS"
When the user says "diagnostics" / "investigate fully" / "forensic science recreation", they
want EVERY claim re-derived from scratch into a timestamped, chain-of-custody artifact — not a
status summary. Concrete pattern that worked:
1. Write a `forensic_capture.ps1` that collects ALL live evidence (OS, listening ports via
   Get-NetTCPConnection, services, firewall rules w/ port+address filters, SSH state, proxy chain,
   artifact inventory) into a single `.txt` with a leading runtime timestamp + host/user.
2. Run it non-elevated; run the SYSTEM-owned reads via a separate ELEVATED reader script (P4).
3. Read the captured file back and reconcile against prior claims. Independent re-collection caught
   a duplicate WinRM 5985 rule that a prior "RESOLVED" had missed (P6).
4. Persist the recreation rows to the SQLite blackboard DB so the trail is durable.

## Proven helper scripts (copy from these; they are re-runnable)
All self-logging (write outcome to a `.log` on disk) and launched via RunAs background (P1).

- `scripts/disable_winrm_5985_all.ps1`
  Iterates ALL inbound rules, filters `LocalPort -eq 5985 -and Protocol -eq 'TCP'` across the
  WHOLE set (NOT by DisplayName — twins share a name, P6), disables every match. Re-verify with
  `Get-NetFirewallRule | ?{$_.Direction-eq'Inbound'} | %{$pf=$_|Get-NetFirewallPortFilter; if($pf -and $pf.LocalPort-eq 5985){$_.Enabled}}`.

- `scripts/ssh_harden.ps1` (self-contained, fixes P2 false-refusal)
  Installs `id_ed25519.pub` -> `authorized_keys` itself, sets permissive ACL
  (user+SYSTEM+BUILTIN\Administrators FullControl), writes `sshd_config.d/99-zqm-hardening.conf`
  (PasswordAuthentication no / PubkeyAuthentication yes / PermitRootLogin no), then
  `Restart-Service sshd`. Guard: if key install fails, ABORT before touching sshd.

- `scripts/fix_authorized_keys_acl.ps1` (fixes P5 rename SID mismatch)
  Grants BOTH `$env:USERNAME` AND the rename-aware name (`ZQM-NODE-1\AlexZ` on this host) plus
  SYSTEM + BUILTIN\Administrators. Skips any identity that doesn't resolve. GENERAL RULE: when the
  profile folder name != the live account name, never grant a single `$env:USERNAME` ACE.

- `scripts/read_system_file.ps1` (fixes P4)
  Elevated reader: copies SYSTEM-owned file content into a user-readable `.log` (content is public
  material — host keys are safe to display). Re-read once more to confirm a UAC dismissal (empty
  log) isn't mistaken for "no keys".

- `ollama_auth_proxy.py` (non-elevated, stdlib-only token-gated reverse proxy)
  Binds a token-gated proxy to the LAN IP; Ollama rebound to 127.0.0.1:11434. Loopback stays open
  (local no-token OK), LAN callers get 401 without `Bearer <token>` / 200 with. Reversible:
  kill proxy + unset OLLAMA_HOST (User env) + restart `ollama serve`.

## Verify-after checklist (elevated mutations)
- WinRM 5985: BOTH rules `Enabled=False` (port+protocol scan), 5986 `Enabled=True`.
- SSH: drop-in present + `Get-Service sshd` Running; `authorized_keys` readable by user ctx.
- Ollama: loopback 200 / LAN no-token 401 / LAN token 200.
- Always re-read the self-log AND live state. The log is a hint; live state is truth.
