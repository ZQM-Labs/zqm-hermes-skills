# Verification checklist for bounty hub

Use in this order:

1. `py_compile` all changed scripts under `scripts/`.
2. Import modules and assert expected callables exist.
3. Run `hub_live_cache.cache_program_details()` against 3-4 handles and assert `detail.name` and `detail.handle` are populated.
4. Run `hub_scores.build_ranked_list()`, `hub_opportunity_alerts.build_alerts()`, `hub_pipeline.build_pipeline_markdown()` against current cache.
5. Assert `hub_verify_watchdog.run_once()` returns a line matching `^(PASS|FAIL): .+$`.
6. If cron tooling changed, assert the repeat-normalization AST branch exists in `hermes-agent/tools/cronjob_tools.py`.

When canonical pytest exists, prefer it for changed paths; use this checklist only when no canonical command exists. Ad-hoc temp verifier files belong under `C:\Users\zqmco\AppData\Local\Temp\hermes-verify-*` and should be cleaned up after execution.
