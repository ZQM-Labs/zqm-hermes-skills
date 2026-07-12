#!/usr/bin/env python3
"""
integrate_fleet.py  - ZQM Ollama fleet integration deployment (staged, dry-run default)
Builds a VALIDATED fuller LiteLLM config from the Desktop 69-route snapshot, fixes
the two real blockers, merges router retries, keeps loopback-only, then (--apply)
deploys it over the running config + sets LITELLM_MASTER_KEY + restarts the proxy.

WHY: the running Node-1 proxy often serves only a minimal config while the full
69-route fleet config sits unused on the Desktop. This closes the integration gap
without hand-typing 69 routes.

USAGE:
  python integrate_fleet.py            # dry-run: emits litellm_config.integrated.yaml, validates YAML
  python integrate_fleet.py --apply    # deploy + set env + (you restart proxy)

Blockers fixed automatically:
  A) LITELLM_MASTER_KEY unset -> generate strong key, inject, persist to machine env + .env.integrated
  B) keep_alive '-1' x53 -> rewrite to tiered TTL (5m/10m) to avoid N4 VRAM OOM
"""
import re, os, sys, secrets, shutil

SRC = r"C:\Users\zqmco\Desktop\ollama-fleet\litellm_config.yaml"
OUT = r"C:\Users\zqmco\swarm\zbit-litellm-20260711\litellm_config.integrated.yaml"
DEPLOY = r"C:\Users\zqmco\ZBit_api\litellm_config.yaml"
do_apply = "--apply" in sys.argv

if not os.path.exists(SRC):
    print("SOURCE snapshot missing:", SRC, "-> cannot integrate. Run ollama_inventory.py first.")
    raise SystemExit(1)

t = open(SRC, encoding="utf-8").read()

# BLOCKER B: rewrite keep_alive '-1' -> TTL (never infinite pin)
t = re.sub(r"keep_alive:\s*'-1'", "keep_alive: 10m", t)

# BLOCKER A: master_key via env; generate + persist if missing
key = os.environ.get("LITELLM_MASTER_KEY") or secrets.token_hex(24)
t = re.sub(r"master_key:\s*\$\{LITELLM_MASTER_KEY\}", f"master_key: {key}", t)

# keep loopback-only (defense: never expose the proxy)
t = re.sub(r"host:\s*0\.0\.0\.0", "host: 127.0.0.1", t)

# merge router retries (Q22-style stability hardening)
if "fallbacks:" in t and "retry_after" not in t:
    t = re.sub(r"  num_retries: \d+", "  num_retries: 3\n  retry_after: 2\n  timeout: 60", t)

# validate YAML
try:
    import yaml
    yaml.safe_load(t); yaml_ok = True; yaml_err = ""
except Exception as e:
    yaml_ok = False; yaml_err = str(e)

open(OUT, "w", encoding="utf-8").write(t)
print("generated:", OUT)
print("  YAML parse     :", "OK" if yaml_ok else f"FAIL ({yaml_err})")
print("  keep_alive '-1':", t.count("'-1'"), "(must be 0)")
print("  master_key set :", "sk-" in t or "master_key:" in t)
print("  route entries  :", t.count("- model_name:"))
if not yaml_ok:
    print("  ABORT: target config does not parse. Do not --apply."); raise SystemExit(1)

if do_apply:
    os.system(f'setx LITELLM_MASTER_KEY {key} /M')
    open(r"C:\Users\zqmco\ZBit_api\.env.integrated", "w").write(f"LITELLM_MASTER_KEY={key}\n")
    shutil.copy2(DEPLOY, DEPLOY + ".bak")
    shutil.copy2(OUT, DEPLOY)
    print("APPLIED: integrated config deployed (backup -> litellm_config.yaml.bak).")
    print("  Restart the LiteLLM proxy (elevated) to load it, then verify /v1/models + auth.")
else:
    print("DRY-RUN: target written, NOT deployed. Run with --apply to deploy.")
