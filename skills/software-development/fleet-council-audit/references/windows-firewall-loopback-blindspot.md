# Windows Firewall loopback blind-spot (verification trap, learned 2026-07-11)

## THE TRAP (decisive verification gotcha)
You install a `block` rule (e.g. block 11434 from 192.168.1.0/24) and then "prove" it
from the SAME host with:

    curl -m 6 -o /dev/null -w "%{http_code}\n" http://192.168.1.218:11434/api/tags

It returns **200**. You conclude "the block didn't work / the box is still exposed."
**This conclusion is FALSE and INVALID.** Windows Firewall does NOT filter
same-machine traffic, including a connection from the host to its OWN LAN IP
(127.0.0.1 AND <own-LAN-IP> are both loopback-exempt from the inbound filter).

So a 200 from this test proves nothing about off-box enforcement. It is a
false-negative on your *verification*, not a real failure of the rule.

## HOW TO ACTUALLY PROVE A BLOCK RULE FROM THIS HOST
1. **Loopback must stay open** (side-effect check, not the block check):
   `curl http://127.0.0.1:11434/api/tags` → expect 200. This proves you did NOT
   accidentally break local callers (e.g. a local proxy that routes 127.0.0.1:11434).
2. **The block can only be proven from a DIFFERENT machine** on the /24. Use a peer
   with a shell (WinRM/SSH) or ask the user to run one line from a sister node:
   ```powershell
   # from 192.168.1.21 / .46 / .215, NOT from .218:
   try { (Invoke-RestMethod http://192.168.1.218:11434/api/tags -TimeoutSec 6).models.Count }
   catch { "BLOCKED: $($_.Exception.Message)" }
   ```
   Expect BLOCK/timeout. If it returns 200 from a peer, the block genuinely failed
   (commonly an older `allow` rule wins on precedence, or profile mismatch).
3. **Quick local sanity that the firewall CAN filter** (optional, needs elevation):
   temporarily add an explicit `block` from 127.0.0.1; if loopback STILL answers 200,
   that confirms WinFW skips same-machine filtering — do NOT interpret the 200 as
   "rules broken." Remove the temp rule immediately after.

## BLOCK > ALLOW PRECEDENCE (why a block usually wins)
Windows evaluates `Block` rules before `Allow` at the matching level. So a new
`block 11434 from 192.168.1.0/24` overrides a pre-existing
`allow 11434 from 192.168.1.0/24` (seen live: stale `Ollama-LAN-only-11434` allow
vs new `ZQM-Ollama-LAN-Block`). But precedence is inference until proven by an
off-box probe — never claim "block confirmed" from an in-host test.

## FLEXIBLE NETSH PARSE (avoid malformed-assertion false-negatives)
Don't assert on rigid column spacing from `netsh` output — the whitespace varies.
Parse with regex so the ad-hoc verifier can't false-FAIL:
```python
import re, subprocess
out = subprocess.run(["netsh","advfirewall","firewall","show","rule","name=all"],
        capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
blocks = re.split(r"(?=Rule Name:)", out)
def find(name):
    for b in blocks:
        if "Rule Name:" in b and name in b:
            act = re.search(r"Action:\s*(\w+)", b)
            rip = re.search(r"RemoteIP:\s*(\S+)", b)
            lpt = re.search(r"LocalPort:\s*(\S+)", b)
            pro = re.search(r"Protocol:\s*(\S+)", b)
            return {"action":act.group(1) if act else None,
                    "remoteip":rip.group(1) if rip else None,
                    "localport":lpt.group(1) if lpt else None,
                    "protocol":pro.group(1) if pro else None}
    return None
```
Then assert on the dict fields, not on the raw line. A verifier that greps for
`"Action:                               Block"` (34 spaces) will FALSE-FAIL even when
the rule is correct — the direct dict read is authoritative. Label such runs
AD-HOC VERIFICATION, not suite green.
