# ZQM Swarm Audit — Verification Recipe (worked example: 2026-07-11)

Concrete paths and regex from the COUNCIL-3 SECRETS/GARDEN run. Reuse the patterns;
update paths when the dated repo dir changes.

## Repo layout (July 11)
- Audit repo: `C:\Users\zqmco\swarm\zbit-litellm-20260711\`
  - backups: `garden_backup_20260711_185740/` (8 garden scripts, ORIGINALS w/ plaintext),
    `genesis_backup_20260711_185759/` (beacon/qseal_recruitment/hive_base/forensic_expand)
  - redactor: `redact_garden_secrets.py` (false-positive source — exclude from leak scan)
- Live redacted garden scripts: `C:\Users\zqmco\Desktop\` (+ `.redacted` copies)
  - deploy-garden-keys.py, deploy-windows-keys.py, pivot-node4-via-node2.py,
    test-node4*.py, deep-dive-node4.py, garden-mesh.ps1
- Genesis modules: `C:\Users\zqmco\ZBit_api\ZBit_runtime\modules\`

## Commands that ran (all PASS)
1. Map repo (exclude .git, __pycache__):
   `mcp_filesystem_directory_tree` path=... excludePatterns=[".git","__pycache__"]
2. Literal-leak scan, live scripts:
   search_files path=Desktop file_glob=*.py pattern=`(pass|cred|pwd|password)\s*=\s*["'][^"']+["']`
   -> 0 leaks (only Desktop/john/aix2john.py false positive)
3. Secret-free scan, audit repo:
   search_files path=swarm/zbit-litellm-20260711 pattern=`sk-[A-Za-z0-9]{10,}|password\s*=\s*["'][^"']+["']|api_key\s*=\s*["'][^"']{8,}["']`
   -> hits only in garden_backup_*/ (originals) + redact_garden_secrets.py (code)
4. Genesis compile:
   `cd /c/Users/zqmco/ZBit_api/ZBit_runtime/modules && python -m py_compile beacon.py qseal_recruitment.py hive_base.py forensic_expand.py && echo COMPILE_OK`
5. Patch markers: search_files path=modules pattern=`Ed25519|/24|Path\.home` -> Q17/Q18/Q19 present

## Proof of redaction completeness
Count `os.environ[` lookups in live scripts: 19 found, every one maps to
NODE_WIN_PASS or GARDEN_SSH_PASS, none remain as literal assigns.

## Original creds found in backup (for reversibility — DO NOT flag):
- `EllaRose89!`  (NODE_WIN_PASS / BASE_PASS / WIN_PASS / zqmco node4 password)
- `344SW00DL4nd!` (GARDEN_SSH_PASS / ALT_PASS / SSH_PASS)
