# Audit Completeness Checklist (pre-close)

A fleet audit is NOT "complete" just because the scan finished. Raw probe output
never surfaces judgment gaps. Before declaring the audit done (or before answering
a "whats missing?" challenge), walk every item below. Each gap must be CLOSED with
live proof OR explicitly marked UNRESOLVED with a note on what would close it.

1. **Critical exposures owned.** Every CRITICAL finding has either (a) a remediation
   applied WITH live re-probe proof, or (b) an explicit handoff ("needs Node-2
   break-glass pw" / "needs HASS_TOKEN"). No critical left dangling as "noted."
2. **Flapping / intermittent services explained.** Any port/service that was
   open→closed→timeout across passes (e.g. Node-4 :11435 2nd Ollama) must be
   diagnosed — restarted? by design? transient? — not merely noted as "intermittent."
3. **Loopback-vs-external disambiguated.** A port "open" from the control-plane is
   LOOPBACK state, not external reachability (localhost isn't firewall-filtered).
   Cross-check against externally-applied firewall mutations from PRIOR sessions.
4. **Root-cause on DOWN services.** A closed port that's supposed to be up
   (e.g. OpenClaw :18789 fleet-wide) needs a CAUSE (service down? firewall? not
   started per design?), not just a flag.
5. **Out-of-scope hosts acknowledged.** A /24 scan may show N un-scanned hosts
   (IoT/infra). State they're out of scope; don't imply "full" coverage of the LAN.
6. **Cross-node hardening parity.** If ONE node was hardened (SSH key-only,
   WinRM 5985 off), the OTHERS may still be at default. State parity status per node.
7. **Credential-leak decisions surfaced.** Any discovered secrets (NAS pw, tokens,
   phones) are flagged for rotation; deferred-user-call items are LISTED, not
   silently dropped (the user may have b-excluded them by intent).
8. **One reconciled deliverable.** When multiple sessions/ledgers exist
   (fleet-audit.db vs fleet_swarm.db + SYSTEMS_AUDIT.md + council .md), produce ONE
   consolidated report that states which ledger is authoritative and reconciles
   contradictions. Don't leave two divergent ledgers as the "final" state.
9. **Medium/low hardening dispositioned.** Telnet/FTP/NFS on appliances, WinRM
   plaintext, etc. enumerated with a disposition (accept / disable / firewall) — not
   just listed as findings.

Live case (2026-07-11 v2 "whats missing" pass): this checklist surfaced 11 gaps the
scan alone missed — most were judgment calls (items 2,3,4,6,8) that raw port data
never surfaces. Walking it is what turns a "scan report" into a "closed audit."
