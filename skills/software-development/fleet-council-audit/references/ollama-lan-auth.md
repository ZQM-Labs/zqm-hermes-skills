# Ollama LAN no-auth closure (token-gated reverse proxy)

Ollama has no native auth. The audit finding "Ollama :11434 no-auth exposure (N1/N2/N4)"
is closed on a node WITHOUT breaking local no-token callers by:

1. Rebind Ollama to loopback only (local callers unaffected):
   - set User env `OLLAMA_HOST=127.0.0.1:11434`
   - kill + restart `ollama serve`
   - verify `curl http://127.0.0.1:11434/api/version` -> 200 (no token)
   - verify `Get-NetTCPConnection -LocalPort 11434` shows 127.0.0.1 (loopback) only

2. Run `scripts/ollama_auth_proxy.py` on the LAN IP :11434 (NOT 0.0.0.0 -- that would
   also grab loopback and force local callers through the token):
   - `OLLAMA_PROXY_TOKEN_FILE=/path/token OLLAMA_PROXY_BIND=192.168.1.218 python ollama_auth_proxy.py &`
   - token: `python -c "import secrets;print(secrets.token_hex(24))"` -> chmod 600

3. Verify (live, the proof):
   - `curl http://192.168.1.218:11434/api/tags`                         -> 401 (no token)
   - `curl -H "Authorization: Bearer <token>" http://192.168.1.218:11434/api/tags` -> 200
   - `curl http://127.0.0.1:11434/api/tags`                            -> 200 (local still open)

Reversible teardown:
   - `Stop-Process` the proxy; unset `OLLAMA_HOST` (User env); restart `ollama serve`.
   Reverts to the original open LAN listener.

Caveats:
   - This binds the LAN IP; the firewall should already scope :11434 to 192.168.1.0/24
     (see scripts/ollama_fw_rule.ps1). The proxy adds auth ON TOP of that scope.
   - N2/N4 are SEPARATE hosts -- this recipe is per-node. Apply on each that needs closure.
   - Node-2's `/api/generate` was wedged (control-plane alive, backend hung) -- recover via
     the ollama-recovery skill before expecting proxy `/api/generate` to work there.

Verified live 2026-07-11 on Node-1 (192.168.1.218): 401/200/200 as above.
