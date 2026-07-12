# Dark-node script fetch over HTTP (round-2 correction of pitfall #16)

## The problem (round 2 of the 2026-07-10 dark-node recon)
The first fix for the node-console `-File` UNC backslash-doubling was a
local-copy wrapper:

    cmd /c "mkdir C:\zqm 2>nul & copy \\ZQM-Garden-01\web\zqm-bootstrap.ps1 C:\zqm\bootstrap.ps1 /Y & powershell -NoProfile -ExecutionPolicy Bypass -File C:\zqm\bootstrap.ps1"

That defeats doubling, but it STILL depends on the node console having a
cached SMB credential to `\\ZQM-Garden-01`. On Node-2 and Node-3 that
credential was absent, so the `copy` step died with:

    The user name or password is incorrect.

and `-File` then failed because nothing had landed. (Node-4 had the cached
cred, which is why only 2/3 failed.) So the SMB-copy wrapper is NOT the
canonical fix — it just trades one failure mode for another.

## The fix — fetch over HTTP from the Garden web server
The Garden `web/` SMB share is ALSO served by the web server at its root.
So `http://ZQM-Garden-01/zqm-bootstrap.ps1` returns the script with no
SMB session, no credential, and no backslashes to be doubled. Fetch then
run the local copy:

    cmd /c "mkdir C:\zqm 2>nul & curl -s -o C:\zqm\bootstrap.ps1 http://ZQM-Garden-01/zqm-bootstrap.ps1 & powershell -NoProfile -ExecutionPolicy Bypass -File C:\zqm\bootstrap.ps1"

Verified this session (from the agent bash host):
  http://ZQM-Garden-01/zqm-bootstrap.ps1  -> HTTP 200, size=3554 (exact script)
  http://ZQM-Garden-01/web/zqm-bootstrap.ps1 -> 404 (web/ is at root, not under /web/)

## CRITICAL hostname / IP trap
Use the **hostname `ZQM-Garden-01`** (resolves to 192.168.1.173 = correct
Garden-01). Do NOT use the IP `192.168.1.40` — that is a DIFFERENT box
(Garden-02, agent-only SMB). Probe showed `curl http://192.168.1.40/...`
returns a 5318-byte index page, NOT the script. The hostnames do NOT map
to sequential IPs (see references/zqm-topology.md), so never assume `40`
equals Garden-01.

## When to use this
- Node console reports `-File "...UNC..." does not exist` (doubling).
- OR `copy \\host\share\...` reports `The user name or password is incorrect`
  (no cached SMB cred to that host).
- OR the node resolves the `\\NAME` but not reliably (per-node WINS/NetBIOS
  gaps — DNS hostname in the HTTP form is more reliable than a UNC name).

## Type exactly
Forward slashes, hostname, no backslashes in the curl step. The only
backslashes are in the `C:\zqm\...` local paths, which never go over SMB.

## Staged copy
Verbatim one-liner also lives at `\\ZQM-Garden-01\web\oneline-fix.txt`
and templates/oneline-fix.txt in this skill.
