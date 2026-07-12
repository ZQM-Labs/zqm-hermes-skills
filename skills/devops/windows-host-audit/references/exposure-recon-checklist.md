# Read-only exposure recon checklist (ZQM homelab)

A recurring audit class: "read-only network/exposure recon of a ZQM node from
THIS Windows host -- produce a structured findings list (severity, claim, exact
evidence command+output); change NOTHING." Use this 5-area template. Every item
is tagged PROVEN (literal command output shown) or UNVERIFIED (tool gated / not
probed). No config/firewall/service is modified.

## 1. Full local listener census
- Command: `cmd.exe /c "netstat -ano -p TCP" | Select-String LISTENING`
- Map each LISTENING port -> PID -> process path -> parent.
- Use `scripts/win_listener_proc_map.py` (bulk, enriches PID with Win32_Process
  path + parent). Report the table.
- All "hostname" references in the host are the Windows USER dir, NOT a
  hostname. Build paths under `C:\Users\<user>\...`.

## 2. LAN-bound 0.0.0.0 vs loopback 127.0.0.1
- Classify each listener: `0.0.0.0` = all interfaces (LAN-exposed if a firewall
  allow-rule scopes the subnet); `127.0.0.1` = loopback-only (correct for AI
  services, NOT a finding); interface-specific (`192.168.x.x:139`) = single adapter.
- State the loopback-vs-LAN distinction EXPLICITLY per port.

## 3. Live reachability of fleet service nodes
- Ollama: `curl -s -m 8 http://<ip>:11434/api/tags` -> HTTP 200 + real model
  JSON proves the node answers. HTTP 000 / exit 28 = not answering (do NOT infer
  models). Probe N1/N2/N3(localhost)/N4 per the canonical topology in
  `zqm-lan-node-reachability` (resolve `.lan` first; do not assume IPs).
- When probing N3 (localhost-only) use `127.0.0.1:<port>` ON the host.

## 4. Raw (non-HTTP) service auth state
- Redis: `python scripts/redis_auth_probe.py <ip> 6379`. `+PONG` with no AUTH =
  CRITICAL unsecured. Never probe Redis with httpx/curl (false "closed").
- General rule: probe raw TCP services with a raw socket, not HTTP tooling.

## 5. Windows Firewall inbound ALLOW rules touching target ports
- Target ports e.g. 22/445/139/5986/2179/11434.
- Dump once: `netsh advfirewall firewall show rule name=all dir=in verbose`
  (do NOT loop Get-NetFirewallRule per-rule -- it hangs ~120s).
- For each target port, find the rule whose `LocalPort:` equals the port, read
  the `Rule Name:` line ABOVE its block, and report Enabled / Action / RemoteIP /
  Profiles. RemoteIP=Any = unscoped (flag). Block overrides Allow at same port.
- **Do not grab the wrong rule:** `findstr <port>` also matches description lines.
  (e.g. port 2179's allow rule is "Hyper-V (REMOTE_DESKTOP_TCP_IN)", NOT the
  "Hyper-V - WMI (Async-In)" rule which is LocalPort: Any.) See SKILL.md 2d.

## Output discipline
- One finding per line/bullet: `[SEVERITY] claim -- evidence: <literal snippet>`.
- Tag each PROVEN / UNVERIFIED. Surface CONFIRMED vs CONTRADICTED vs NEW vs
  baseline items explicitly (e.g. "N2 Redis unauth -> CONFIRMED (CRITICAL)").
- Keep temp capture files under `C:/Users/<user>/AppData/Local/Temp/` -- NOT
  `/tmp` (MSYS `/tmp` != native python/curl `C:\tmp`; see SKILL.md 0c).
