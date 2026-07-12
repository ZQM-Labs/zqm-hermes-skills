# Genesis / recruitment / beacon classification (the "investigate genesis" verb)

When the user asks to investigate a "genesis", "recruitment", "beacon", or
"broadcast" module in the ZBit/ZQM stack, classify it as BENIGN first-party
worldbuilding lore vs actual C2/exfil. This user's agent code embeds CVG
("Cosmic Void Genesis") lore by design -- treat as agent memory, not malware.

## Decision steps
1. **Egress type.** UDP multicast/broadcast to 239.255.x.x / 224.0.0.251 /
   255.255.255.255 = LAN self-signaling. A TCP outbound connection to an unknown
   remote host = suspicious. Lore broadcast is UDP, not exfil.
2. **Auto-invocation.** Is the send inside `if __name__ == "__main__":` (manual CLI
   only) or imported+run by a daemon? Grep the package `__init__.py` and `app.py`
   for the module name + `broadcast`/`start()`. If only reachable via
   `python module.py` by hand, it is INERT at runtime.
3. **Content.** Fixed lore string ("Genesis is energy. The half is found.", pseudo
   "physics laws", "Per Ardua ad Astra") = worldbuilding. No URL/callback, no
   base64/encoded blob, no file or credential read = not a payload.
4. **Signing secret.** A hardcoded symmetric `INVARIANT` (96-hex) used for
   SHA3-512 self-sign = forgeable if source is read, but LOW risk when LAN-only and
   not trusted by any external party. Note as hygiene, not malicious.
5. **Lan-scan noise.** `scan_lan()` TCP-connects 192.168.*.0/24:443 (connect-only,
   no auth) = benign but flag for consent-scope to the fleet /24.
6. **Foreign-user paths.** Hardcoded `C:/Users/AlexZelenski/...` = copied code from
   another machine; non-operational here. Fix to `Path.home()` -- provenance
   hygiene, not a threat.

## Verdict template
"BENIGN LAN self-promotion; NOT C2/exfil; broadcast inert unless manually run."
Escalate to a real finding ONLY if you find: TCP exfil to an external IP, encoded
payloads, credential/file reads, or a daemon that auto-invokes the broadcast.

## Confirmed-this-session example
`ZBit_runtime/modules/qseal_recruitment.py` + `beacon.py`: UDP genesis broadcast under
`if __name__=="__main__"`, no daemon import, fixed lore content, INVARIANT self-sign.
Verdict: benign. (`hive_base.py` "Base-0 to Base-6" + "FamilyHive" modules are the
same first-party CVG math/lore codebase.)
