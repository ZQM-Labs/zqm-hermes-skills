# Capability Mining — ZQM repos → this workstation (reproducible recipe)

Context: the ask is usually NOT "audit repos" but "what in OUR repos can enhance
THIS node?" Both ZQM orgs are the capability library. Source-verify everything;
never trust the GitHub description as a capability statement.

## Org reality (verified 2026-07-12 via `gh repo list`)
- ZQM-Computing: 5 repos (hermes, hermes-agent, hermes-config, dotfiles, profile).
- ZQM-Labs: 32 repos — the bulk of usable tooling + red-team/bounty skeletons.
- TOTAL 37. (Old skill text said "18 private repos / ZQM-Computing only" — STALE;
  ZQM-Computing alone is 5. Always list BOTH orgs.)

## Recipe (read-only, no push/install/edit)
1. Enumerate BOTH:
   `gh repo list ZQM-Computing --limit 1000 --json name,url,visibility,updatedAt,description,isPrivate`
   `gh repo list ZQM-Labs      --limit 1000 --json name,url,visibility,updatedAt,description,isPrivate`
2. For applicable candidates, pull REAL content — languages + top-level tree:
   branch-fallback master→main→develop on `repos/{org}/{repo}/git/trees/{br}?recursive=0`
   (and `/languages`). Use the tree API, not `contents/{path}` (see api-robustness.md).
3. Classify EVERY repo, emit a COUNT per class + TOTAL:
   - Tier 1 (high, drop-in capability)  - Tier 2 (medium: hardening / config / skill-currency)
   - Tier 3 (low / situational / skeleton)  - Not-applicable (framework / bounty / client / meta)
4. EXCLUDE red-team/bounty tooling (zqm-sword, zqm-auth, bounty-tools) when the goal
   is enhancing a FRIENDLY workstation — capability-library, but not for this use.
5. To ACTUALLY enhance: clone Tier-1 repos READ-ONLY into a staging dir:
   `git clone --depth 1 https://github.com/ZQM-Labs/<repo>.git <staging>/<repo>`
   Then:
   a. Verify local prereqs (e.g. `curl -s http://localhost:11434/api/tags` for Ollama;
      `python -c "import mcp,chromadb,numpy"` for deps). Note MISSING deps as gaps.
   b. Register an MCP server (verified pattern):
      `printf 'y\n' | hermes mcp add <name> --command python --args "<staging>/<repo>/mcp_server.py"`
      -> "Connected! Found N tool(s)" + saved to ~/AppData/Local/hermes/config.yaml.
   c. PROVE end-to-end BEFORE claiming it works. Example (zqm-local-tools RAG):
      - ensure an embed model exists: `ollama pull nomic-embed-text`
      - `python rag.py ingest --file <doc> --collection node1 --embed-model nomic-embed-text --store sqlite`
        (file->md needs `pip install crawl4ai markitdown`; the CORE embed/store/query/
        synthesize engine works WITHOUT them via a literal-string ingest — use that to
        prove the engine fast, then note the optional install for file/url ingest.)
      - `rag.answer("...", "node1", "qwen3:8b", backend="sqlite", embed_model="nomic-embed-text")`
        must return a correct answer synthesized by LOCAL Ollama.
   d. Tools load only after a Hermes RESTART (`hermes` relaunch). Tell the user.

## 2026-07-12 classified inventory (worked example, 37 repos)
Tier 1 (3): zqm-local-tools (RAG/crawl/vision/MCP, zero-key), zqm-node-01-indexer
  (this node's indexer + signed supervised-service installer), ollama-bridge (TS MCP
  router over Ollama w/ per-call host override).
Tier 2 (6): zqm-hermes-skills (upstream of installed skills), dotfiles (Win config),
  zqm-attestation-toolkit (CMS-signed machine-health/DFIR), zqm-shield (endpoint
  helpers), dev-setup (Win bootstrap), zqm-public-tools (system-report/attest baselines).
Tier 3 (5): pqc-readiness-toolkit (CNSA-2.0 posture), zqm-security-policy (docs),
  comfyui-setup (image-gen), Universal-Map (empty skeleton), hermes-config (CAUTION:
  live tree has session_tokens.txt/pastes/ — do NOT clone wholesale).
Not-applicable (23): hermes/hermes-agent (framework), gemini-desktop, ZQM-AI-Council,
  zqm-bounty-hub, zqm-auth, bounty-tools, zqm-sword, wiki, zqm-workstage2,
  zqm-attestation-toolkit-clean, zqm-localhost-findings, zqm-node-02-indexer (Node-2's,
  not this node), + remaining bounty/red-team skeletons. Red-team (zqm-sword/zqm-auth/
  bounty-tools) excluded from friendly-workstation use.

## Skill-sync caveat (when pulling zqm-hermes-skills onto installed skills)
- Diff FIRST. Copy whole NEW upstream-only categories + NEW files inside existing
  categories. EXCLUDE `.hub/` local state.
- HOLD conflicts (upstream differs from local) for user approval — do NOT auto-overwrite.
  "newer-on-disk: UPSTREAM" from a fresh clone = clone recency, NOT a real revision.
- PRESERVE local-only custom skills (e.g. forensics, session-history-enumeration,
  skill-automation-center, tavily-mcp, verification, zqm-bounty-hub,
  zqm-fleet-management).
