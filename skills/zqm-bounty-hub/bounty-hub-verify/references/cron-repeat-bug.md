# Cron repeat-normalization bug

**File:** `hermes-agent/tools/cronjob_tools.py`

**Trigger:** LLM/runtime passes `repeat` as a string like `"forever"`.

**Crash:** `repeat <= 0` compares `str` to `int`, raising `TypeError: '<=' not supported between instances of 'str' and 'int'`.

**Fix already applied:** branch handles:
- `int` values normally, with <=0 mapped to `None`
- strings: `"forever"`, `"none"`, `"inf"`, `infinite`, `""` -> `None`; numeric strings parsed via `int()`, <=0 mapped to `None`

**Verification:**
- AST grep: `isinstance(repeat, str)` and `normalized_repeat = None` both present in `cronjob_tools.py`
- Pytest `tests/cron/test_jobs.py` should pass after installing missing `croniter` if tests complain about it

**Workaround still active:** local `hub_verify_watchdog.py` with 1h self-reschedule loop and log rotation.
