# Verify WinRM failover (5985 + 5986) alive from Node-1 — WITHOUT the zqmlocal password

## Why
When the user says "try now" / "it's installed", you need to PROVE the
WinRM failover path actually answers from Node-1 before claiming success.
You often do NOT have the zqmlocal password (it's DPAPI-LocalMachine
encrypted on the target node, not readable from here), so you can't open a
PSSession. But you CAN prove the listeners are up and serving — which is
exactly what "failover works" means at the network layer.

## Step 1 — resolve the node IP
`Get` the IP from DNS first; don't guess.
  nslookup ZQM-NODE-2      # → 192.168.1.21 (verified this session)
Node name → IP is NOT sequential (Node-3=.46, Node-4=.215, Node-2=.21).

## Step 2 — port scan (listener present?)
Use a `timeout`-wrapped single-IP probe. Do NOT scan ranges with bare
`/dev/tcp` — it hangs on unresponsive hosts (seen: 180s timeout on a 9-IP
sweep). For sweeps use the Python-socket pattern in zqm-node-reachability.ps1.
  for p in 22 5985 5986; do
    timeout 4 bash -c "exec 3<>/dev/tcp/192.168.1.21/$p" 2>/dev/null && echo "OPEN $p" || echo "closed $p"
  done
  → 5985 OPEN, 5986 OPEN, 22 CLOSED  (Node-2 this session)

## Step 3 — WSMan handshake proof (listener ANSWERS, no creds)
Run from Node-1 via native PowerShell:
  Test-WSMan -ComputerName 192.168.1.21
  → valid IdentifyResponse (ProductVendor=Microsoft, Stack 3.0) = 5985 HTTP alive.

  Test-WSMan -ComputerName 192.168.1.21 -UseSSL
  → if it returns a WSManFault "The server certificate ... has the following
    errors: The SSL certificate is signed by an unknown certificate
    authority. The SSL certificate contains a common name (CN) that does not
    match the hostname."  — THAT IS SUCCESS.
  Meaning: the TLS handshake COMPLETED and the server presented its
  self-signed 5986 cert. WSMan only refused to TRUST the self-signed cert
  by default. A truly-CLOSED 5986 would return a connection-refused /
  timeout error instead, never a cert fault.
  So: 5985-OPEN + 5986-"SSL cert error" = full WinRM failover VERIFIED
  reachable from Node-1.

## What this does NOT prove
It proves the listener answers — NOT that you can AUTHENTICATE. To actually
manage the node you still need the zqmlocal password (secure-credential-handoff).
But "listener up + answering" is the evidence that the failover redundancy
exists; if 5985/5986 are closed, no amount of correct creds will connect.

## SSH (22) check
  timeout 4 bash -c "exec 3<>/dev/tcp/192.168.1.21/22" && echo OPEN || echo closed
If CLOSED after a dism.exe OpenSSH install (pitfall #19), the install didn't
leave a listener: re-run the local command and check `sc query sshd` +
`dism /online /Get-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0`.

## This session's result (Node-2, 192.168.1.21)
5985 OPEN, 5986 OPEN (Test-WSMan -UseSSL returned the cert CN-mismatch
fault = TLS worked), 22 CLOSED (OpenSSH local dism.exe install still
pending). Confirmed the WinRM failover was live; only SSH 22 was the gap.
