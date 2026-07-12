# Deep-Dive Technique for Repos with No Source Code Signals

## When to apply

Repo has few files, long README-only commits, no package.json/pyproject.toml/Makefile,
and meta-repo structural scaffolding (.github, CODE_OF_CONDUCT, SECURITY, CONTRIBUTING).

## Steps

1. Search tree for README/README_*.md variants (multi-loc READMEs often localize or upstream-brand docs)
2. Fetch README content via blob API
3. Detect upstream branding: look for project URLs, upstream org names, badge URLs,
   issue/PR references with upstream repo paths
4. Flag if repo is:
   - intentional meta-repo (points to other repos)
   - placeholder (README says "delete within 48 hours")
   - hosted upstream fork (all significant files are localization of upstream)
5. Conclude: "No original codebase to deep-dive" — do not retry.

## Case examples from ZQM-Computing (2026-07-09)

### hermes
Signal: tree has 13 items, no package.json, no source directories.
Conclusion: meta-repository for the Hermes ecosystem; README points to hermes-agent,
hermes-config, zqm-hermes-skills. No proprietary code signals.

### Universal-Map
Signal: tree has 14 items, no package.json, no source directories.
README explicitly says "Placeholder repo. Populate or delete."
Conclusion: no implementation exists; design references zqm-auth, wiki, ZQM-AI-Council.

### bounty-tools
Signal: tree has 18 items, README_JP/README_KR/README_TR are 57-60KB each.
README content = verbatim Naabu (projectdiscovery/naabu) upstream docs.
Conclusion: localized/Naabu distribution, not original ZQM codebase.
Comparable: projectdiscovery/naabu upstream GitHub repo.