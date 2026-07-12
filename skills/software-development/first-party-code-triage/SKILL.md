---
name: first-party-code-triage
description: >
  Triage "is this first-party agent code doing something shady?" questions —
  distinguishing benign LAN self-promotion / worldbuilding / lore-broadcast from
  real C2, exfiltration, or credential theft in the user's own repos
  (ZBit_runtime, ZQM-AI-Council, beacon/qseal/genesis modules, etc.). Use when
  the user says "investigate genesis", "what does this script do", "is this
  malware", "audit the agent code", or flags a module that broadcasts/beacons/
  signs. Read-only code analysis + egress-behavior verification, NOT a dynamic
  malware sandbox.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [zqm, triage, agent-code, security, beacon, genesis, benign-vs-malicious]
    related_skills:
    - audit-sqlite-sink
    - windows-host-audit
    - fleet-council-audit
---

# First-Party Code Triage (benign agent-code vs real threat)

## When to use
- "investigate genesis" / "what does beacon.py / qseal_recruitment.py do"
- A first-party module does UDP broadcast, LAN multicast, "signing", or "recruitment"
- User suspects their own agent code is exfiltrating / C2 / malicious
- Distinguishing the agent's own worldbuilding-lore from a real payload

## THE CONTRACT (read-only code analysis)
1. READ the module(s) line by line. Do NOT execute broadcast/network code.
2. MAP the egress surface: what protocol (UDP/TCP/HTTP), which hosts/ports,
   what payload content, and — critically — IS IT AUTO-INVOKED or only under
   `if __name__ == '__main__'` / a manual CLI? A function that sends a packet
   is harmless if nothing calls it at runtime.
3. CHECK the import graph: does `app.py` / `__init__.py` / a service actually
   import-and-run it, or just reference it? Reference ≠ execution.
4. CLASSIFY each egress primitive against the rubric below.
5. RECORD findings to the SQLite ledger (audit-sqlite-sink) as PROVEN, with the
   exact file:line evidence.

## Triage rubric — 6 questions, in order
1. **Transport** — UDP multicast/broadcast (LAN-noise) vs TCP outbound to a
   fixed foreign IP:port (C2-like). LAN-only UDP is low-signal; foreign-TCP is
   high-signal.
2. **Payload** — fixed string / lore / self-description vs harvested data
   (files, env vars, creds, key material). Read the literal bytes the code sends.
3. **Auto-invoked?** — `if __name__ == '__main__'` / manual CLI = NOT running
   unless a human/script launches it. Imported-by-a-daemon = live egress.
4. **Credential touch** — does it read `.env`, `~/.ssh`, tokens, or hardcode a
   secret used as a real auth key (vs a symmetric "invariant" used only for
   self-signing lore)? Symmetric shared-secret self-signing = forgeable but
   benign; real credential exfil = critical.
5. **Exfil path** — any `socket.send` of file contents, `requests.post` of local
   data, or write to a remote share? Absence = benign.
6. **Foreign-user hardcoded paths** — `C:/Users/<OtherUser>/...` in code = copied
   code from another machine (hygiene flag / origin-traceability), NOT active
   risk if the path is non-existent on this host. Flag it, don't alarm on it.

## Verdict language
- BENIGN SELF-PROMOTION: LAN UDP multicast of fixed lore/worldbuilding, no cred
  touch, not auto-invoked → INFO/LOW, no remediation needed.
- HARDENING-OPTIONAL: symmetric INVARIANT signing (forgeable), or a LAN TCP scan
  (noise) → LOW; recommend asymmetric per-node keys / consent-gating the scan.
- REAL THREAT: foreign-TCP C2, credential exfil, or auto-invoked egress of real
  data → escalate to CRITICAL/HIGH remediation.

## Pitfalls (burned this session)
- Do NOT assume a module that DEFINES `broadcast_x()` actually fires it. Check
  `__main__` guards + the import graph first. This session `qseal_recruitment`.
  broadcast_recruitment() looked alarming but is ONLY callable via `python
  qseal_recruitment.py` manually — inert at runtime; ZBit_runtime/__init__.py
  RE-IMPLEMENTED the qseal_* logic with the real `cryptography` lib (Ed25519) and
  never imports the original's broadcast.
- "CONTAMINATED" / "quarantine" folder names are usually Defender false-positives
  on the user's own agent KB (windows-host-audit S0b). READ before judging.
- A fixed-string "genesis/recruitment" message is worldbuilding, not a C2 beacon —
  judge by payload content + egress path, not by scary vocabulary in the code.
- HARDCODED INVARIANT across modules = symmetric secret → anyone with the source
  can forge signatures. Low risk (LAN-only, no external trust) but note it as a
  hardening item, not as "compromised".

## Output
Plain-text verdict per module: transport, payload, auto-invoked?, credential
touch, egress classification, final verdict (BENIGN / HARDENING-OPTIONAL / REAL
THREAT), with file:line evidence. Persist to ledger.

## Remediation patterns (hardening the LOW findings)
When the verdict is HARDENING-OPTIONAL and the user asks for fixes, apply these
verified recipes (full diffs + safety table in
`references/genesis-remediation.md`). All are READ-ONLY-design-first; confirm
with a compile + a round-trip test before applying.

### F38 — swap shared-INVARIANT signing for per-node Ed25519
The shared `INVARIANT` literal (find via `search_files pattern INVARIANT`) is a
symmetric secret embedded in source — anyone with the repo can forge. The
node's REAL per-node Ed25519 keypair already exists at
`ZBit_runtime/ledger/qseal_keypair.pem` (generated by `ZBit_runtime.qseal_keygen`).
- Add a `_qseal_sign(payload_str)` helper that lazy-imports `cryptography`,
  loads `Path(__file__).resolve().parent.parent / "ledger" / "qseal_keypair.pem"`,
  and returns `sk.sign(payload_str.encode()).hex()`. Fall back to the legacy
  `hashlib.sha3_512((INVARIANT + payload).hexdigest()` ONLY if the key is absent
  (keeps old references verifiable).
- Route BOTH sign and verify through the same helper so any truncation
  (e.g. `sig[:64]`) stays internally consistent. Ed25519 sig hex is exactly 64
  chars, so `[:64]` is a no-op — safe.
- Do NOT delete `INVARIANT` or `invariant_prefix` metadata — they are a compat
  shim; `compute_node_identity()`'s INVARIANT *salt* is an identity seed, not a
  forgeable broadcast signature, so leave it.
- Stop printing the secret in status output (e.g. beacon.py `show_status`'s
  `INVARIANT[:24]` line → redacted string).

### F40 — scope network scans to the fleet /24 + opt-in flag
- Replace auto-subnet-detection (the `subprocess.run(["ipconfig"])` branch) with a
  default `FLEET_SCAN_SUBNET = "192.168.1.0/24"` and a signature
  `scan_lan(subnet=None, allow_wildcard=False)`. If a non-default subnet is passed
  without `allow_wildcard=True`, return `[]` with a refusal log.
- The API endpoint that calls the scan (`app.py /v1/mesh/scan` →
  `beacon.py discover` → `scan_lan()`) must NEVER pass `allow_wildcard=True`, so
  a caller behind X-Api-Key cannot escape the fleet scope. Confirm the call site
  passes no such arg.
- Removing the ipconfig branch also drops a now-dead `import subprocess`.

### F41 — relativize hardcoded foreign-user paths
Code copied from another machine carries `C:/Users/<OtherUser>/...` absolute
paths. They don't crash reads but point at a non-existent user on this host.
- Replace `Path("C:/Users/AlexZelenski/...")` with
  `Path.home() / "..."` so it resolves to the current runtime user.
- `Path` is typically already imported in these modules — no new import needed.
- Verify with `python -m py_compile <file>` per file.

### Pitfalls learned this session (F38/F40/F41 remediation design)
- LEAD COUNTS OVER-INCLUDE. The genesis lead listed 5 files carrying INVARIANT,
  but `app.py` only has an `_invariant_node_id()` helper — NO INVARIANT literal.
  Always `search_files` to confirm which files ACTUALLY contain the secret before
  writing diffs; don't trust a hand-counted list.
- SIGN+VERIFY MUST SHARE ONE HELPER. Patching only one side (sign OR verify) to
  Ed25519 silently breaks verification. Both paths compute `expected_sig` from the
  same function.
- SCAN SCOPING IS A CALL-SITE DUTY, NOT JUST A DEFAULT. A default subnet is
  meaningless if the API caller can pass an arbitrary one — the opt-in
  `allow_wildcard` flag must be rejected at the default and the call site must not
  set it. Verify the call site, not just the function.

## References
- `references/genesis-case-study.md` — the 2026-07-11 ZQM genesis investigation:
  qseal_recruitment.py / beacon.py / hive_base.py walkthrough, verdict (BENIGN
  LAN self-promotion, NOT C2/exfil), and the exact code lines that proved it.
- `references/genesis-remediation.md` — exact old→new diffs for the LOW findings
  (F38 Ed25519 signing swap, F40 scan_lan scoping, F41 foreign-user path
  relativization), plus a design-time safety/verification table.
